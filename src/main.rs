#![windows_subsystem = "windows"]

//! DdcSwitch: a tray app that switches the monitor input source over DDC/CI,
//! from global hotkeys and automatically right before Windows shuts down.

mod applog;
mod autostart;
mod cli;
mod config;
mod ddc;
mod icon;
mod icon_art;
mod settings;
mod shutdown;

use std::cell::RefCell;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use windows::core::{w, HSTRING, PCWSTR};
use windows::Win32::Foundation::*;
use windows::Win32::Graphics::Gdi::HBRUSH;
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Shutdown::{ShutdownBlockReasonCreate, ShutdownBlockReasonDestroy};
use windows::Win32::System::Threading::{CreateMutexW, SetProcessShutdownParameters};
use windows::Win32::UI::Controls::{InitCommonControlsEx, ICC_HOTKEY_CLASS, ICC_STANDARD_CLASSES, INITCOMMONCONTROLSEX};
use windows::Win32::UI::HiDpi::{SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_SYSTEM_AWARE};
use windows::Win32::UI::Input::KeyboardAndMouse::{RegisterHotKey, UnregisterHotKey, HOT_KEY_MODIFIERS, MOD_NOREPEAT};
use windows::Win32::UI::Shell::*;
use windows::Win32::UI::WindowsAndMessaging::*;

use config::{Config, HOTKEY_SLOTS, VCP_INPUT};

pub(crate) const MAIN_CLASS: PCWSTR = w!("DdcSwitch.Main");
const WM_TRAY: u32 = WM_APP + 1;
const WM_SHOW_SETTINGS: u32 = WM_APP + 2;
const WM_SWITCH_DONE: u32 = WM_APP + 3;
const TRAY_UID: u32 = 1;

const ID_SWITCH_BASE: usize = 100;
const ID_TOGGLE_SHUTDOWN: usize = 200;
const ID_TOGGLE_AUTOSTART: usize = 201;
const ID_SETTINGS: usize = 202;
const ID_OPEN_LOG: usize = 203;
const ID_EXIT: usize = 299;

// lParam flags of WM_QUERYENDSESSION / WM_ENDSESSION
const ES_CLOSEAPP: u32 = 0x0000_0001;
const ES_LOGOFF: u32 = 0x8000_0000;
const NIN_KEYSELECT: u32 = NIN_SELECT | 0x1;

/// Shutdown level for SetProcessShutdownParameters: 0x100 is the last slot for
/// applications, so the input only flips once every other app has agreed to the
/// shutdown (a "these apps are preventing shutdown" screen stays visible).
const SHUTDOWN_LEVEL: u32 = 0x100;

struct App {
    hwnd: HWND,
    cfg: Config,
    icon: HICON,
}

thread_local! {
    static APP: RefCell<Option<App>> = const { RefCell::new(None) };
}
static TASKBAR_CREATED: AtomicU32 = AtomicU32::new(0);
static STARTED: OnceLock<Instant> = OnceLock::new();

fn with_app<R>(f: impl FnOnce(&mut App) -> R) -> Option<R> {
    APP.with(|a| a.try_borrow_mut().ok().and_then(|mut a| a.as_mut().map(f)))
}

fn current_config() -> Config {
    with_app(|a| a.cfg.clone()).unwrap_or_default()
}

fn main() {
    let _ = STARTED.set(Instant::now());
    let mut config_override = None;
    let mut rest = Vec::new();
    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        if a == "--config" {
            config_override = args.next().map(PathBuf::from);
        } else {
            rest.push(a);
        }
    }
    config::init_paths(config_override);

    let autostarted = rest.iter().any(|a| a == "--autostart");
    rest.retain(|a| a != "--autostart");
    if !rest.is_empty() {
        std::process::exit(cli::run(&rest));
    }
    run_gui(autostarted);
}

fn run_gui(autostarted: bool) {
    unsafe {
        let _ = SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_SYSTEM_AWARE);
        let icc = INITCOMMONCONTROLSEX {
            dwSize: std::mem::size_of::<INITCOMMONCONTROLSEX>() as u32,
            dwICC: ICC_HOTKEY_CLASS | ICC_STANDARD_CLASSES,
        };
        let _ = InitCommonControlsEx(&icc);

        // Single instance: a second launch just opens the settings of the running one.
        let _mutex = CreateMutexW(None, true, w!("Local\\DdcSwitch.SingleInstance"));
        if GetLastError() == ERROR_ALREADY_EXISTS {
            if !autostarted {
                if let Ok(h) = FindWindowW(MAIN_CLASS, PCWSTR::null()) {
                    let _ = PostMessageW(Some(h), WM_SHOW_SETTINGS, WPARAM(0), LPARAM(0));
                }
            }
            return;
        }

        let (cfg, existed) = Config::load();
        if existed {
            autostart::refresh_path();
        } else {
            // First run: the shutdown hook only works while the app runs, so start with Windows by default.
            let _ = cfg.save();
            if let Err(e) = autostart::set(true) {
                applog::log(format!("设置开机启动失败: {e}"));
            }
        }

        let hinst: HINSTANCE = GetModuleHandleW(None).unwrap_or_default().into();
        let icon_small = icon::create(GetSystemMetrics(SM_CXSMICON));
        let icon_big = icon::create(GetSystemMetrics(SM_CXICON));
        settings::set_icons(icon_small, icon_big);

        let wc = WNDCLASSEXW {
            cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
            lpfnWndProc: Some(wndproc),
            hInstance: hinst,
            hIcon: icon_big,
            hIconSm: icon_small,
            hbrBackground: HBRUSH::default(),
            lpszClassName: MAIN_CLASS,
            ..Default::default()
        };
        RegisterClassExW(&wc);
        settings::register_class(hinst);

        // A hidden *top-level* window: message-only windows don't get WM_QUERYENDSESSION.
        let hwnd = match CreateWindowExW(
            WS_EX_TOOLWINDOW,
            MAIN_CLASS,
            w!("DdcSwitch"),
            WS_OVERLAPPED,
            0,
            0,
            0,
            0,
            None,
            None,
            Some(hinst),
            None,
        ) {
            Ok(h) => h,
            Err(e) => {
                applog::log(format!("创建窗口失败: {e}"));
                return;
            }
        };

        TASKBAR_CREATED.store(RegisterWindowMessageW(w!("TaskbarCreated")), Ordering::Relaxed);
        APP.with(|a| *a.borrow_mut() = Some(App { hwnd, cfg: cfg.clone(), icon: icon_small }));

        if let Err(e) = SetProcessShutdownParameters(SHUTDOWN_LEVEL, 0) {
            applog::log(format!("SetProcessShutdownParameters 失败: {e}"));
        }
        tray_add(hwnd);
        let errors = register_hotkeys(hwnd, &cfg);
        applog::log(format!(
            "启动 v{}，配置: {}，关机切换: {}",
            env!("CARGO_PKG_VERSION"),
            config::config_path().display(),
            if cfg.shutdown_switch { cfg.input_title(cfg.shutdown_input) } else { "关闭".into() }
        ));
        if !errors.is_empty() {
            notify("部分快捷键注册失败", &errors.join("\n"), true);
        } else if !existed {
            notify("DdcSwitch 已在后台运行", "点击托盘图标可以切换输入源、修改快捷键和设置。", false);
        }

        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).0 > 0 {
            if settings::is_dialog_message(&msg) {
                continue;
            }
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
}

unsafe extern "system" fn wndproc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    match msg {
        WM_TRAY => {
            let event = (lparam.0 as u32) & 0xFFFF;
            if event == WM_CONTEXTMENU || event == NIN_SELECT || event == NIN_KEYSELECT {
                show_menu(hwnd);
            }
            LRESULT(0)
        }
        WM_HOTKEY => {
            let slot = wparam.0;
            let cfg = current_config();
            if let Some(b) = slot.checked_sub(1).and_then(|i| cfg.bindings.get(i)) {
                switch_async(hwnd, &cfg, b.input, "快捷键");
            }
            LRESULT(0)
        }
        WM_SWITCH_DONE => {
            let r = Box::from_raw(lparam.0 as *mut SwitchResult);
            if !r.ok {
                notify("切换输入源失败", &r.message, true);
            } else if current_config().notify_success {
                notify("已切换输入源", &r.message, false);
            }
            LRESULT(0)
        }
        WM_SHOW_SETTINGS => {
            settings::open(current_config());
            LRESULT(0)
        }
        WM_QUERYENDSESSION => {
            applog::log(format!("收到 WM_QUERYENDSESSION (lParam=0x{:08X})", lparam.0 as u32));
            LRESULT(1)
        }
        WM_ENDSESSION => {
            if wparam.0 != 0 {
                on_end_session(hwnd, lparam.0 as u32);
            } else {
                applog::log("收到 WM_ENDSESSION(FALSE)：关机已取消");
            }
            LRESULT(0)
        }
        WM_POWERBROADCAST => {
            if wparam.0 as u32 == PBT_APMSUSPEND {
                on_suspend();
            }
            LRESULT(1)
        }
        WM_DESTROY => {
            settings::close();
            for id in 1..=HOTKEY_SLOTS as i32 {
                let _ = UnregisterHotKey(Some(hwnd), id);
            }
            tray_delete(hwnd);
            applog::log("退出");
            PostQuitMessage(0);
            LRESULT(0)
        }
        _ => {
            let tc = TASKBAR_CREATED.load(Ordering::Relaxed);
            if tc != 0 && msg == tc {
                // Explorer restarted: the tray icon has to be added again.
                tray_add(hwnd);
            }
            DefWindowProcW(hwnd, msg, wparam, lparam)
        }
    }
}

// ---------------------------------------------------------------------------
// Switching

struct SwitchResult {
    ok: bool,
    message: String,
}

fn switch_async(hwnd: HWND, cfg: &Config, input: u32, source: &'static str) {
    let (index, name) = (cfg.monitor, cfg.monitor_name.clone());
    let title = cfg.input_title(input);
    let hwnd_raw = hwnd.0 as isize;
    std::thread::spawn(move || {
        let result = ddc::set_vcp(index, &name, VCP_INPUT, input);
        let (ok, message) = match result {
            Ok(mon) => (true, format!("{mon} → {title}")),
            Err(e) => (false, e),
        };
        applog::log(format!("[{source}] 切换到 {title}: {}", if ok { "成功" } else { "失败" }));
        if !ok {
            applog::log(format!("    {message}"));
        }
        let boxed = Box::into_raw(Box::new(SwitchResult { ok, message }));
        unsafe {
            if PostMessageW(Some(HWND(hwnd_raw as _)), WM_SWITCH_DONE, WPARAM(0), LPARAM(boxed as isize)).is_err() {
                drop(Box::from_raw(boxed));
            }
        }
    });
}

/// Synchronous switch used while the system is going down.
fn switch_now(hwnd: HWND, cfg: &Config, reason: &str) {
    let title = cfg.input_title(cfg.shutdown_input);
    unsafe {
        let _ = ShutdownBlockReasonCreate(hwnd, w!("正在切换显示器输入源…"));
    }
    let started = Instant::now();
    match ddc::set_vcp(cfg.monitor, &cfg.monitor_name, VCP_INPUT, cfg.shutdown_input) {
        Ok(mon) => applog::log(format!("[{reason}] 已切换 {mon} → {title}（{} ms）", started.elapsed().as_millis())),
        Err(e) => applog::log(format!("[{reason}] 切换到 {title} 失败: {e}")),
    }
    unsafe {
        let _ = ShutdownBlockReasonDestroy(hwnd);
    }
}

fn on_end_session(hwnd: HWND, flags: u32) {
    let cfg = current_config();
    applog::log(format!("收到 WM_ENDSESSION(TRUE) (lParam=0x{flags:08X})"));
    if !cfg.shutdown_switch {
        applog::log("    关机切换未启用，跳过");
        return;
    }
    if flags & ES_CLOSEAPP != 0 {
        applog::log("    只是重启管理器要求关闭本程序（安装/更新），跳过");
        return;
    }
    if flags & ES_LOGOFF != 0 {
        applog::log("    注销，不是关机，跳过");
        return;
    }
    if cfg.skip_on_restart {
        // Only look at events raised while we've been running (max. 10 minutes back).
        let uptime = STARTED.get().map(|s| s.elapsed().as_millis() as u64).unwrap_or(0);
        let window = uptime.clamp(5_000, 600_000);
        let mut kind = shutdown::Kind::Unknown;
        for attempt in 0..4 {
            if attempt > 0 {
                std::thread::sleep(Duration::from_millis(250));
            }
            let (k, detail) = shutdown::detect(window);
            applog::log(format!("    关机类型判断: {k:?} — {detail}"));
            kind = k;
            if k != shutdown::Kind::Unknown {
                break;
            }
        }
        if kind == shutdown::Kind::Restart {
            applog::log("    这是重启，不切换输入源");
            return;
        }
    }
    switch_now(hwnd, &cfg, "关机");
}

fn on_suspend() {
    let cfg = current_config();
    if !cfg.sleep_switch {
        return;
    }
    applog::log("收到 PBT_APMSUSPEND（即将睡眠）");
    let hwnd = with_app(|a| a.hwnd).unwrap_or_default();
    switch_now(hwnd, &cfg, "睡眠");
}

// ---------------------------------------------------------------------------
// Hotkeys

fn register_hotkeys(hwnd: HWND, cfg: &Config) -> Vec<String> {
    let mut errors = Vec::new();
    unsafe {
        for id in 1..=HOTKEY_SLOTS as i32 {
            let _ = UnregisterHotKey(Some(hwnd), id);
        }
        for (i, b) in cfg.bindings.iter().enumerate() {
            if !b.enabled || b.vk == 0 {
                continue;
            }
            let text = config::hotkey_to_string(b.mods, b.vk);
            if RegisterHotKey(Some(hwnd), i as i32 + 1, HOT_KEY_MODIFIERS(b.mods) | MOD_NOREPEAT, b.vk).is_err() {
                applog::log(format!("快捷键 {text} 注册失败"));
                errors.push(format!("{text} 已被其他程序占用（例如 AutoHotkey 脚本）"));
            }
        }
    }
    errors
}

/// Called by the settings window after the user pressed OK.
pub fn apply_settings(new: Config, autostart_on: bool) -> Vec<String> {
    let mut errors = Vec::new();
    if let Err(e) = new.save() {
        errors.push(format!("保存配置失败: {e}"));
    }
    if autostart_on != autostart::is_enabled() {
        if let Err(e) = autostart::set(autostart_on) {
            errors.push(e);
        }
    }
    let Some(hwnd) = with_app(|a| {
        a.cfg = new.clone();
        a.hwnd
    }) else {
        return errors;
    };
    errors.extend(register_hotkeys(hwnd, &new));
    tray_update_tip(hwnd);
    applog::log("设置已更新");
    errors
}

// ---------------------------------------------------------------------------
// Tray icon & menu

fn copy_wide(dst: &mut [u16], s: &str) {
    let n = dst.len() - 1;
    let mut i = 0;
    for c in s.encode_utf16().take(n) {
        dst[i] = c;
        i += 1;
    }
    dst[i] = 0;
}

fn tray_data(hwnd: HWND) -> NOTIFYICONDATAW {
    NOTIFYICONDATAW {
        cbSize: std::mem::size_of::<NOTIFYICONDATAW>() as u32,
        hWnd: hwnd,
        uID: TRAY_UID,
        ..Default::default()
    }
}

fn tray_tip() -> String {
    let cfg = current_config();
    let mut tip = String::from("DdcSwitch 显示器输入源切换");
    for b in cfg.bindings.iter().filter(|b| b.enabled && b.vk != 0) {
        tip += &format!("\n{} → {}", config::hotkey_to_string(b.mods, b.vk), cfg.input_title(b.input));
    }
    tip
}

fn tray_add(hwnd: HWND) {
    let mut nid = tray_data(hwnd);
    nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
    nid.uCallbackMessage = WM_TRAY;
    nid.hIcon = with_app(|a| a.icon).unwrap_or_default();
    copy_wide(&mut nid.szTip, &tray_tip());
    unsafe {
        let _ = Shell_NotifyIconW(NIM_DELETE, &nid);
        if !Shell_NotifyIconW(NIM_ADD, &nid).as_bool() {
            applog::log("添加托盘图标失败");
        }
        nid.Anonymous.uVersion = NOTIFYICON_VERSION_4;
        let _ = Shell_NotifyIconW(NIM_SETVERSION, &nid);
    }
}

fn tray_update_tip(hwnd: HWND) {
    let mut nid = tray_data(hwnd);
    nid.uFlags = NIF_TIP | NIF_SHOWTIP;
    copy_wide(&mut nid.szTip, &tray_tip());
    unsafe {
        let _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
    }
}

fn tray_delete(hwnd: HWND) {
    let nid = tray_data(hwnd);
    unsafe {
        let _ = Shell_NotifyIconW(NIM_DELETE, &nid);
    }
}

fn notify(title: &str, text: &str, error: bool) {
    let Some(hwnd) = with_app(|a| a.hwnd) else { return };
    let mut nid = tray_data(hwnd);
    nid.uFlags = NIF_INFO;
    nid.dwInfoFlags = if error { NIIF_ERROR } else { NIIF_INFO };
    copy_wide(&mut nid.szInfoTitle, title);
    copy_wide(&mut nid.szInfo, text);
    unsafe {
        let _ = Shell_NotifyIconW(NIM_MODIFY, &nid);
    }
}

fn show_menu(hwnd: HWND) {
    let cfg = current_config();
    let autostart_on = autostart::is_enabled();
    unsafe {
        let Ok(menu) = CreatePopupMenu() else { return };
        let add = |flags: MENU_ITEM_FLAGS, id: usize, text: &str| {
            let _ = AppendMenuW(menu, flags, id, &HSTRING::from(text));
        };
        let checked = |on: bool| if on { MF_CHECKED } else { MF_UNCHECKED };

        let mut any = false;
        for (i, b) in cfg.bindings.iter().enumerate() {
            if !b.enabled {
                continue;
            }
            any = true;
            let mut label = format!("切换到 {}", cfg.input_title(b.input));
            if b.vk != 0 {
                label += &format!("\t{}", config::hotkey_to_string(b.mods, b.vk));
            }
            add(MF_STRING, ID_SWITCH_BASE + i, &label);
        }
        if !any {
            add(MF_STRING | MF_GRAYED, 0, "（尚未设置快捷键）");
        }
        add(MF_SEPARATOR, 0, "");
        add(
            MF_STRING | checked(cfg.shutdown_switch),
            ID_TOGGLE_SHUTDOWN,
            &format!("关机前切换到 {}", cfg.input_title(cfg.shutdown_input)),
        );
        add(MF_STRING | checked(autostart_on), ID_TOGGLE_AUTOSTART, "开机自动运行");
        add(MF_SEPARATOR, 0, "");
        add(MF_STRING, ID_SETTINGS, "设置…");
        add(MF_STRING, ID_OPEN_LOG, "查看日志");
        add(MF_SEPARATOR, 0, "");
        add(MF_STRING, ID_EXIT, "退出");
        let _ = SetMenuDefaultItem(menu, ID_SETTINGS as u32, 0);

        let mut pt = POINT::default();
        let _ = GetCursorPos(&mut pt);
        let _ = SetForegroundWindow(hwnd);
        let cmd = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, pt.x, pt.y, None, hwnd, None).0
            as usize;
        let _ = PostMessageW(Some(hwnd), WM_NULL, WPARAM(0), LPARAM(0));
        let _ = DestroyMenu(menu);

        match cmd {
            0 => {}
            ID_TOGGLE_SHUTDOWN => {
                let mut new = cfg.clone();
                new.shutdown_switch = !new.shutdown_switch;
                apply_settings(new, autostart_on);
            }
            ID_TOGGLE_AUTOSTART => {
                if let Err(e) = autostart::set(!autostart_on) {
                    notify("设置开机启动失败", &e, true);
                }
            }
            ID_SETTINGS => settings::open(cfg),
            ID_OPEN_LOG => open_log(),
            ID_EXIT => {
                let _ = DestroyWindow(hwnd);
            }
            id if id >= ID_SWITCH_BASE && id < ID_SWITCH_BASE + HOTKEY_SLOTS => {
                let input = cfg.bindings[id - ID_SWITCH_BASE].input;
                switch_async(hwnd, &cfg, input, "菜单");
            }
            _ => {}
        }
    }
}

pub fn open_log() {
    let path = config::log_path();
    if !path.exists() {
        applog::log("日志已创建");
    }
    unsafe {
        ShellExecuteW(None, w!("open"), &HSTRING::from(path.as_os_str()), None, None, SW_SHOWNORMAL);
    }
}
