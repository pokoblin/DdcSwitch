// The settings window: plain Win32 controls laid out in code, scaled for DPI.

use std::cell::{Cell, RefCell};

use windows::core::{w, HSTRING, PCWSTR};
use windows::Win32::Foundation::*;
use windows::Win32::Graphics::Gdi::*;
use windows::Win32::UI::HiDpi::{AdjustWindowRectExForDpi, GetDpiForSystem, SystemParametersInfoForDpi};
use windows::Win32::UI::Input::KeyboardAndMouse::EnableWindow;
use windows::Win32::UI::WindowsAndMessaging::*;

use crate::config::{self, Binding, Config, MOD_ALT, MOD_CONTROL, MOD_SHIFT, MOD_WIN};
use crate::i18n::{self, fmt, t};
use crate::{autostart, ddc};

const CLASS: PCWSTR = w!("DdcSwitch.Settings");
const WM_PROBE_DONE: u32 = WM_APP + 20;

const IDC_OK: i32 = 1;
const IDC_CANCEL: i32 = 2;
const IDC_MONITOR: i32 = 1001;
const IDC_REDETECT: i32 = 1002;
const IDC_ROW_BASE: i32 = 1100; // + row * 10 + field
const IDC_SD_ENABLED: i32 = 1201;
const IDC_SD_INPUT: i32 = 1202;
const IDC_SD_RESTART: i32 = 1203;
const IDC_SLEEP: i32 = 1204;
const IDC_AUTOSTART: i32 = 1205;
const IDC_NOTIFY: i32 = 1206;
const IDC_LANGUAGE: i32 = 1207;
const IDC_OPEN_LOG: i32 = 1301;

// Control styles / messages not worth importing from several modules.
const STYLE_PUSHBUTTON: u32 = 0x0;
const STYLE_DEFPUSHBUTTON: u32 = 0x1;
const STYLE_CHECKBOX: u32 = 0x3;
const STYLE_GROUPBOX: u32 = 0x7;
const STYLE_CB_DROPDOWN: u32 = 0x2;
const STYLE_CB_DROPDOWNLIST: u32 = 0x3;
const STYLE_ES_AUTOHSCROLL: u32 = 0x80;
const STYLE_SS_ENDELLIPSIS: u32 = 0x4000;
const TABSTOP: u32 = 0x0001_0000;
const VSCROLL: u32 = 0x0020_0000;
const HKM_SETHOTKEY: u32 = WM_USER + 1;
const HKM_GETHOTKEY: u32 = WM_USER + 2;
const HOTKEYF_SHIFT: u32 = 0x1;
const HOTKEYF_CONTROL: u32 = 0x2;
const HOTKEYF_ALT: u32 = 0x4;
const HOTKEYF_EXT: u32 = 0x8;
const BST_CHECKED: usize = 1;

/// Client area size in 96-DPI pixels.
const CLIENT_W: i32 = 700;
const CLIENT_H: i32 = 582;
const GROUP_W: i32 = CLIENT_W - 24;

/// Offered in the input drop-downs until the monitor reports its own list.
const STANDARD_INPUTS: &[u32] = &[15, 16, 17, 18, 27];

struct Row {
    enabled: HWND,
    name: HWND,
    input: HWND,
    hotkey: HWND,
    win: HWND,
}

struct Ui {
    hwnd: HWND,
    font: HFONT,
    monitor: HWND,
    status: HWND,
    rows: Vec<Row>,
    sd_enabled: HWND,
    sd_input: HWND,
    sd_restart: HWND,
    sleep: HWND,
    autostart: HWND,
    notify: HWND,
    language: HWND,
    monitor_names: Vec<String>,
    probe_seq: usize,
    base: Config,
}

struct Probe {
    seq: usize,
    current: Result<u32, String>,
    inputs: Result<Vec<u32>, String>,
}

thread_local! {
    static UI: RefCell<Option<Ui>> = const { RefCell::new(None) };
    static ICONS: Cell<(isize, isize)> = const { Cell::new((0, 0)) };
    static HINST: Cell<isize> = const { Cell::new(0) };
}

pub fn set_icons(small: HICON, big: HICON) {
    ICONS.with(|c| c.set((small.0 as isize, big.0 as isize)));
}

pub fn register_class(hinst: HINSTANCE) {
    HINST.with(|c| c.set(hinst.0 as isize));
    unsafe {
        let wc = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            lpfnWndProc: Some(wndproc),
            hInstance: hinst,
            hCursor: LoadCursorW(None, IDC_ARROW).unwrap_or_default(),
            hbrBackground: GetSysColorBrush(COLOR_WINDOW),
            lpszClassName: CLASS,
            ..Default::default()
        };
        RegisterClassExW(&wc);
    }
}

fn ui_hwnd() -> Option<HWND> {
    UI.with(|u| u.try_borrow().ok().and_then(|u| u.as_ref().map(|u| u.hwnd)))
}

/// Gives the settings window keyboard navigation (Tab, Enter, Esc).
pub fn is_dialog_message(msg: &MSG) -> bool {
    match ui_hwnd() {
        Some(h) => unsafe { IsDialogMessageW(h, msg).as_bool() },
        None => false,
    }
}

pub fn close() {
    if let Some(h) = ui_hwnd() {
        unsafe {
            let _ = DestroyWindow(h);
        }
    }
}

// ---------------------------------------------------------------------------
// small Win32 helpers

fn send(h: HWND, msg: u32, wp: usize, lp: isize) -> isize {
    unsafe { SendMessageW(h, msg, Some(WPARAM(wp)), Some(LPARAM(lp))).0 }
}

fn get_text(h: HWND) -> String {
    unsafe {
        let len = GetWindowTextLengthW(h);
        let mut buf = vec![0u16; len as usize + 1];
        let n = GetWindowTextW(h, &mut buf);
        String::from_utf16_lossy(&buf[..n as usize])
    }
}

fn set_text(h: HWND, s: &str) {
    unsafe {
        let _ = SetWindowTextW(h, &HSTRING::from(s));
    }
}

fn checked(h: HWND) -> bool {
    send(h, BM_GETCHECK, 0, 0) as usize == BST_CHECKED
}

fn set_checked(h: HWND, on: bool) {
    send(h, BM_SETCHECK, on as usize, 0);
}

fn enable(h: HWND, on: bool) {
    unsafe {
        let _ = EnableWindow(h, on);
    }
}

fn add_item(combo: HWND, text: &str) {
    let item = HSTRING::from(text);
    send(combo, CB_ADDSTRING, 0, item.as_ptr() as isize);
}

fn message_box(owner: HWND, text: &str, style: MESSAGEBOX_STYLE) {
    unsafe {
        MessageBoxW(Some(owner), &HSTRING::from(text), w!("DdcSwitch"), style);
    }
}

/// Refills an editable combo box, keeping whatever text it currently shows.
fn fill_input_combo(h: HWND, values: &[u32]) {
    let text = get_text(h);
    send(h, CB_RESETCONTENT, 0, 0);
    for &v in values {
        add_item(h, &config::input_label(v));
    }
    set_text(h, &text);
}

fn is_extended_vk(vk: u32) -> bool {
    matches!(vk, 0x21..=0x28 | 0x2D | 0x2E | 0x6F | 0x90)
}

fn mods_to_hotkeyf(mods: u32, vk: u32) -> u32 {
    let mut f = 0;
    if mods & MOD_SHIFT != 0 {
        f |= HOTKEYF_SHIFT;
    }
    if mods & MOD_CONTROL != 0 {
        f |= HOTKEYF_CONTROL;
    }
    if mods & MOD_ALT != 0 {
        f |= HOTKEYF_ALT;
    }
    if is_extended_vk(vk) {
        f |= HOTKEYF_EXT;
    }
    f
}

fn hotkeyf_to_mods(f: u32) -> u32 {
    let mut m = 0;
    if f & HOTKEYF_SHIFT != 0 {
        m |= MOD_SHIFT;
    }
    if f & HOTKEYF_CONTROL != 0 {
        m |= MOD_CONTROL;
    }
    if f & HOTKEYF_ALT != 0 {
        m |= MOD_ALT;
    }
    m
}

struct Builder {
    parent: HWND,
    font: HFONT,
    dpi: i32,
    hinst: HINSTANCE,
}

impl Builder {
    fn s(&self, v: i32) -> i32 {
        v * self.dpi / 96
    }

    #[allow(clippy::too_many_arguments)]
    fn add(&self, class: PCWSTR, text: &str, style: u32, ex: WINDOW_EX_STYLE, x: i32, y: i32, w: i32, h: i32, id: i32) -> HWND {
        unsafe {
            let hwnd = CreateWindowExW(
                ex,
                class,
                &HSTRING::from(text),
                WS_CHILD | WS_VISIBLE | WINDOW_STYLE(style),
                self.s(x),
                self.s(y),
                self.s(w),
                self.s(h),
                Some(self.parent),
                Some(HMENU(id as isize as *mut _)),
                Some(self.hinst),
                None,
            )
            .unwrap_or_default();
            send(hwnd, WM_SETFONT, self.font.0 as usize, 1);
            hwnd
        }
    }

    fn label(&self, text: &str, x: i32, y: i32, w: i32) -> HWND {
        self.add(w!("STATIC"), text, STYLE_SS_ENDELLIPSIS, WINDOW_EX_STYLE(0), x, y, w, 20, -1)
    }

    fn group(&self, text: &str, y: i32, h: i32) {
        self.add(w!("BUTTON"), text, STYLE_GROUPBOX, WINDOW_EX_STYLE(0), 12, y, GROUP_W, h, -1);
    }

    fn check(&self, text: &str, x: i32, y: i32, w: i32, id: i32) -> HWND {
        self.add(w!("BUTTON"), text, STYLE_CHECKBOX | TABSTOP, WINDOW_EX_STYLE(0), x, y, w, 22, id)
    }

    fn button(&self, text: &str, x: i32, y: i32, w: i32, id: i32, default: bool) -> HWND {
        let style = if default { STYLE_DEFPUSHBUTTON } else { STYLE_PUSHBUTTON };
        self.add(w!("BUTTON"), text, style | TABSTOP, WINDOW_EX_STYLE(0), x, y, w, 30, id)
    }

    fn combo(&self, editable: bool, x: i32, y: i32, w: i32, id: i32) -> HWND {
        let style = if editable { STYLE_CB_DROPDOWN | STYLE_ES_AUTOHSCROLL } else { STYLE_CB_DROPDOWNLIST };
        self.add(w!("COMBOBOX"), "", style | TABSTOP | VSCROLL, WINDOW_EX_STYLE(0), x, y, w, 300, id)
    }
}

// ---------------------------------------------------------------------------

pub fn open(cfg: Config) {
    if let Some(h) = ui_hwnd() {
        unsafe {
            let _ = ShowWindow(h, SW_RESTORE);
            let _ = SetForegroundWindow(h);
        }
        return;
    }
    let tr = t();
    unsafe {
        let dpi = GetDpiForSystem();
        let hinst = HINSTANCE(HINST.with(|c| c.get()) as *mut _);
        let style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;
        let ex = WS_EX_CONTROLPARENT | WS_EX_APPWINDOW;
        let scale = |v: i32| v * dpi as i32 / 96;
        let mut rc = RECT { left: 0, top: 0, right: scale(CLIENT_W), bottom: scale(CLIENT_H) };
        let _ = AdjustWindowRectExForDpi(&mut rc, style, false, ex, dpi);
        let (w, h) = (rc.right - rc.left, rc.bottom - rc.top);
        let x = (GetSystemMetrics(SM_CXSCREEN) - w) / 2;
        let y = (GetSystemMetrics(SM_CYSCREEN) - h) / 2;
        let Ok(hwnd) =
            CreateWindowExW(ex, CLASS, &HSTRING::from(tr.settings_title), style, x, y, w, h, None, None, Some(hinst), None)
        else {
            return;
        };
        let (small, big) = ICONS.with(|c| c.get());
        send(hwnd, WM_SETICON, ICON_SMALL as usize, small);
        send(hwnd, WM_SETICON, ICON_BIG as usize, big);

        let mut ncm = NONCLIENTMETRICSW { cbSize: std::mem::size_of::<NONCLIENTMETRICSW>() as u32, ..Default::default() };
        let _ = SystemParametersInfoForDpi(
            SPI_GETNONCLIENTMETRICS.0,
            ncm.cbSize,
            Some(&mut ncm as *mut _ as *mut _),
            0,
            dpi,
        );
        let font = CreateFontIndirectW(&ncm.lfMessageFont);

        let b = Builder { parent: hwnd, font, dpi: dpi as i32, hinst };

        // Monitor
        b.group(tr.grp_monitor, 10, 86);
        b.label(tr.lbl_monitor, 26, 38, 80);
        let monitor = b.combo(false, 110, 34, 440, IDC_MONITOR);
        b.button(tr.btn_redetect, 562, 33, 112, IDC_REDETECT, false);
        let status = b.label("", 26, 68, 650);

        // Hotkeys
        b.group(tr.grp_hotkeys, 106, 172);
        b.label(tr.col_enabled, 22, 128, 46);
        b.label(tr.col_name, 72, 128, 180);
        b.label(tr.col_input, 262, 128, 150);
        b.label(tr.col_hotkey, 422, 128, 262);
        let mut rows = Vec::new();
        for i in 0..config::HOTKEY_SLOTS as i32 {
            let y = 150 + i * 32;
            let id = IDC_ROW_BASE + i * 10;
            rows.push(Row {
                enabled: b.check("", 36, y + 1, 22, id),
                name: b.add(w!("EDIT"), "", STYLE_ES_AUTOHSCROLL | TABSTOP, WS_EX_CLIENTEDGE, 72, y, 180, 24, id + 1),
                input: b.combo(true, 262, y, 150, id + 2),
                hotkey: b.add(w!("msctls_hotkey32"), "", TABSTOP, WS_EX_CLIENTEDGE, 422, y, 170, 24, id + 3),
                win: b.check("+ Win", 602, y + 1, 76, id + 4),
            });
        }
        b.label(tr.hint_win, 26, 248, 650);

        // Shutdown / sleep
        b.group(tr.grp_shutdown, 288, 116);
        let sd_enabled = b.check(tr.chk_shutdown, 26, 312, 300, IDC_SD_ENABLED);
        let sd_input = b.combo(true, 330, 310, 150, IDC_SD_INPUT);
        let sd_restart = b.check(tr.chk_skip_restart, 26, 342, 650, IDC_SD_RESTART);
        let sleep = b.check(tr.chk_sleep, 26, 370, 650, IDC_SLEEP);

        // General
        b.group(tr.grp_general, 414, 114);
        let autostart_chk = b.check(tr.chk_autostart, 26, 438, 650, IDC_AUTOSTART);
        let notify = b.check(tr.chk_notify, 26, 466, 650, IDC_NOTIFY);
        b.label(tr.lbl_language, 26, 498, 150);
        let language = b.combo(false, 180, 494, 240, IDC_LANGUAGE);

        b.button(tr.btn_open_log, 12, 540, 140, IDC_OPEN_LOG, false);
        b.button(tr.btn_ok, 476, 540, 100, IDC_OK, true);
        b.button(tr.btn_cancel, 588, 540, 100, IDC_CANCEL, false);

        // Fill in values
        for (row, bind) in rows.iter().zip(&cfg.bindings) {
            set_checked(row.enabled, bind.enabled);
            set_text(row.name, &bind.name);
            fill_input_combo(row.input, STANDARD_INPUTS);
            set_text(row.input, &config::input_label(bind.input));
            let f = mods_to_hotkeyf(bind.mods, bind.vk);
            send(row.hotkey, HKM_SETHOTKEY, (bind.vk | (f << 8)) as usize, 0);
            set_checked(row.win, bind.mods & MOD_WIN != 0);
        }
        set_checked(sd_enabled, cfg.shutdown_switch);
        fill_input_combo(sd_input, STANDARD_INPUTS);
        set_text(sd_input, &config::input_label(cfg.shutdown_input));
        set_checked(sd_restart, cfg.skip_on_restart);
        set_checked(sleep, cfg.sleep_switch);
        set_checked(autostart_chk, autostart::is_enabled());
        set_checked(notify, cfg.notify_success);

        add_item(language, tr.lang_auto);
        for (_, strings) in i18n::LANGUAGES {
            add_item(language, strings.lang_name);
        }
        let lang_sel = i18n::LANGUAGES
            .iter()
            .position(|(code, _)| code.eq_ignore_ascii_case(&cfg.language))
            .map_or(0, |i| i + 1);
        send(language, CB_SETCURSEL, lang_sel, 0);

        UI.with(|u| {
            *u.borrow_mut() = Some(Ui {
                hwnd,
                font,
                monitor,
                status,
                rows,
                sd_enabled,
                sd_input,
                sd_restart,
                sleep,
                autostart: autostart_chk,
                notify,
                language,
                monitor_names: Vec::new(),
                probe_seq: 0,
                base: cfg,
            })
        });
        fill_monitors();
        update_enabled_states();

        let _ = ShowWindow(hwnd, SW_SHOW);
        let _ = SetForegroundWindow(hwnd);
        probe();
    }
}

fn fill_monitors() {
    let names = ddc::list_names();
    UI.with(|u| {
        let mut u = u.borrow_mut();
        let Some(u) = u.as_mut() else { return };
        let previous = u.monitor_names.get(send(u.monitor, CB_GETCURSEL, 0, 0).max(0) as usize).cloned();
        send(u.monitor, CB_RESETCONTENT, 0, 0);
        for (i, n) in names.iter().enumerate() {
            add_item(u.monitor, &format!("{}: {}", i + 1, n));
        }
        if names.is_empty() {
            add_item(u.monitor, t().no_monitors);
        }
        let wanted = previous.unwrap_or_else(|| u.base.monitor_name.clone());
        let sel = names
            .iter()
            .position(|n| *n == wanted)
            .unwrap_or_else(|| u.base.monitor.saturating_sub(1).min(names.len().saturating_sub(1)));
        send(u.monitor, CB_SETCURSEL, sel, 0);
        u.monitor_names = names;
    });
}

fn selected_monitor(u: &Ui) -> (usize, String) {
    let sel = send(u.monitor, CB_GETCURSEL, 0, 0).max(0) as usize;
    (sel + 1, u.monitor_names.get(sel).cloned().unwrap_or_default())
}

/// Reads the current input and the supported inputs on a worker thread
/// (the capabilities request takes a second or two).
fn probe() {
    let Some((hwnd, index, name, seq)) = UI.with(|u| {
        let mut u = u.borrow_mut();
        let u = u.as_mut()?;
        u.probe_seq += 1;
        set_text(u.status, t().status_reading);
        let (index, name) = selected_monitor(u);
        Some((u.hwnd, index, name, u.probe_seq))
    }) else {
        return;
    };
    let hwnd_raw = hwnd.0 as isize;
    std::thread::spawn(move || {
        let current = ddc::get_input(index, &name);
        let inputs = ddc::capabilities(index, &name).map(|c| ddc::parse_input_caps(&c));
        let boxed = Box::into_raw(Box::new(Probe { seq, current, inputs }));
        unsafe {
            if PostMessageW(Some(HWND(hwnd_raw as _)), WM_PROBE_DONE, WPARAM(0), LPARAM(boxed as isize)).is_err() {
                drop(Box::from_raw(boxed));
            }
        }
    });
}

fn on_probe_done(p: Probe) {
    UI.with(|u| {
        let u = u.borrow();
        let Some(u) = u.as_ref() else { return };
        if p.seq != u.probe_seq {
            return;
        }
        let tr = t();
        let mut text = match &p.current {
            Ok(cur) => fmt(tr.status_current, &[&config::input_label(*cur)]),
            Err(e) => fmt(tr.status_read_failed, &[e]),
        };
        if let Ok(list) = &p.inputs {
            if !list.is_empty() {
                let labels: Vec<String> = list.iter().map(|&v| config::input_label(v)).collect();
                text += "    ";
                text += &fmt(tr.status_supported, &[&labels.join(tr.list_sep)]);
                for row in &u.rows {
                    fill_input_combo(row.input, list);
                }
                fill_input_combo(u.sd_input, list);
            }
        }
        set_text(u.status, &text);
    });
}

fn update_enabled_states() {
    UI.with(|u| {
        let u = u.borrow();
        let Some(u) = u.as_ref() else { return };
        for row in &u.rows {
            let on = checked(row.enabled);
            for h in [row.name, row.input, row.hotkey, row.win] {
                enable(h, on);
            }
        }
        let on = checked(u.sd_enabled);
        enable(u.sd_input, on);
        enable(u.sd_restart, on);
        enable(u.sleep, on);
    });
}

fn collect(u: &Ui) -> Result<(Config, bool), String> {
    let tr = t();
    let mut cfg = u.base.clone();
    if !u.monitor_names.is_empty() {
        let (index, name) = selected_monitor(u);
        cfg.monitor = index;
        cfg.monitor_name = name;
    }

    let mut used: Vec<(u32, u32)> = Vec::new();
    for (i, row) in u.rows.iter().enumerate() {
        let n = i + 1;
        let enabled = checked(row.enabled);
        let input_text = get_text(row.input);
        let input = config::parse_input(&input_text);
        let hk = send(row.hotkey, HKM_GETHOTKEY, 0, 0) as u32;
        let vk = hk & 0xFF;
        let mut mods = hotkeyf_to_mods((hk >> 8) & 0xFF);
        if checked(row.win) {
            mods |= MOD_WIN;
        }
        if enabled {
            if input.is_none() {
                return Err(fmt(tr.err_row_input, &[&n, &input_text]));
            }
            if vk == 0 {
                return Err(fmt(tr.err_row_no_hotkey, &[&n]));
            }
            if mods == 0 && !(0x70..=0x87).contains(&vk) {
                return Err(fmt(tr.err_row_modifier, &[&n]));
            }
            if used.contains(&(mods, vk)) {
                return Err(fmt(tr.err_row_duplicate, &[&n, &config::hotkey_to_string(mods, vk)]));
            }
            used.push((mods, vk));
        }
        let old = &u.base.bindings[i];
        cfg.bindings[i] = Binding {
            enabled,
            name: get_text(row.name).trim().to_string(),
            input: input.unwrap_or(old.input),
            mods: if vk == 0 { 0 } else { mods },
            vk,
        };
    }

    cfg.shutdown_switch = checked(u.sd_enabled);
    let sd_text = get_text(u.sd_input);
    match config::parse_input(&sd_text) {
        Some(v) => cfg.shutdown_input = v,
        None if cfg.shutdown_switch => return Err(fmt(tr.err_shutdown_input, &[&sd_text])),
        None => {}
    }
    cfg.skip_on_restart = checked(u.sd_restart);
    cfg.sleep_switch = checked(u.sleep);
    cfg.notify_success = checked(u.notify);
    let lang_sel = send(u.language, CB_GETCURSEL, 0, 0);
    cfg.language = match lang_sel {
        1.. => i18n::LANGUAGES.get(lang_sel as usize - 1).map_or("auto", |(code, _)| code).to_string(),
        _ => "auto".to_string(),
    };
    Ok((cfg, checked(u.autostart)))
}

fn on_ok(hwnd: HWND) {
    let collected = UI.with(|u| u.borrow().as_ref().map(collect));
    match collected {
        Some(Ok((cfg, autostart_on))) => {
            let errors = crate::apply_settings(cfg, autostart_on);
            if !errors.is_empty() {
                message_box(hwnd, &fmt(t().saved_with_problems, &[&errors.join("\n")]), MB_ICONWARNING);
            }
            unsafe {
                let _ = DestroyWindow(hwnd);
            }
        }
        Some(Err(msg)) => message_box(hwnd, &msg, MB_ICONERROR),
        None => {}
    }
}

unsafe extern "system" fn wndproc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_COMMAND => {
            let id = (wparam.0 & 0xFFFF) as i32;
            let code = ((wparam.0 >> 16) & 0xFFFF) as u32;
            match id {
                IDC_OK => on_ok(hwnd),
                IDC_CANCEL => {
                    let _ = DestroyWindow(hwnd);
                }
                IDC_MONITOR if code == CBN_SELCHANGE => probe(),
                IDC_REDETECT => {
                    fill_monitors();
                    probe();
                }
                IDC_OPEN_LOG => crate::open_log(),
                IDC_SD_ENABLED => update_enabled_states(),
                id if id >= IDC_ROW_BASE && id < IDC_ROW_BASE + 100 && (id - IDC_ROW_BASE) % 10 == 0 => {
                    update_enabled_states()
                }
                _ => {}
            }
            LRESULT(0)
        }
        WM_PROBE_DONE => {
            let p = Box::from_raw(lparam.0 as *mut Probe);
            on_probe_done(*p);
            LRESULT(0)
        }
        WM_CTLCOLORSTATIC => {
            // Labels, check boxes and group boxes on the white window background.
            let hdc = HDC(wparam.0 as *mut _);
            SetBkColor(hdc, COLORREF(GetSysColor(COLOR_WINDOW)));
            LRESULT(GetSysColorBrush(COLOR_WINDOW).0 as isize)
        }
        WM_CLOSE => {
            let _ = DestroyWindow(hwnd);
            LRESULT(0)
        }
        WM_DESTROY => {
            let ui = UI.with(|u| u.borrow_mut().take());
            if let Some(ui) = ui {
                let _ = DeleteObject(ui.font.into());
            }
            LRESULT(0)
        }
        _ => DefWindowProcW(hwnd, msg, wparam, lparam),
    }
}
