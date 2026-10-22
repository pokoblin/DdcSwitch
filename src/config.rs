// Settings persisted as a small `key = value` file in %APPDATA%\DdcSwitch.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

// RegisterHotKey modifier bits
pub const MOD_ALT: u32 = 0x1;
pub const MOD_CONTROL: u32 = 0x2;
pub const MOD_SHIFT: u32 = 0x4;
pub const MOD_WIN: u32 = 0x8;

pub const HOTKEY_SLOTS: usize = 3;

/// VCP code for "Input Select".
pub const VCP_INPUT: u8 = 0x60;

#[derive(Clone, Debug, PartialEq)]
pub struct Binding {
    pub enabled: bool,
    pub name: String,
    pub input: u32,
    pub mods: u32,
    pub vk: u32,
}

#[derive(Clone, Debug)]
pub struct Config {
    /// 1-based monitor number, same numbering as `ddcctl -l`.
    pub monitor: usize,
    /// Preferred over `monitor` when a monitor with this name is present.
    pub monitor_name: String,
    pub bindings: Vec<Binding>,
    pub shutdown_switch: bool,
    pub shutdown_input: u32,
    pub skip_on_restart: bool,
    pub sleep_switch: bool,
    pub notify_success: bool,
    /// "auto" or a language code from `i18n::LANGUAGES`.
    pub language: String,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            monitor: 1,
            monitor_name: String::new(),
            bindings: vec![
                Binding {
                    enabled: true,
                    name: "MacBook (USB-C)".into(),
                    input: 25,
                    mods: MOD_CONTROL | MOD_ALT | MOD_WIN,
                    vk: 0x27, // Right
                },
                Binding {
                    enabled: false,
                    name: "Windows (HDMI-1)".into(),
                    input: 17,
                    mods: MOD_CONTROL | MOD_ALT | MOD_WIN,
                    vk: 0x25, // Left
                },
                Binding { enabled: false, name: String::new(), input: 15, mods: 0, vk: 0 },
            ],
            shutdown_switch: true,
            shutdown_input: 25,
            skip_on_restart: true,
            sleep_switch: false,
            notify_success: false,
            language: "auto".into(),
        }
    }
}

static CONFIG_FILE: OnceLock<PathBuf> = OnceLock::new();

pub fn init_paths(custom: Option<PathBuf>) {
    let path = custom.unwrap_or_else(|| {
        let base = std::env::var_os("APPDATA").map(PathBuf::from).unwrap_or_else(|| PathBuf::from("."));
        base.join("DdcSwitch").join("config.ini")
    });
    let _ = CONFIG_FILE.set(path);
}

pub fn config_path() -> &'static Path {
    CONFIG_FILE.get().expect("init_paths not called")
}

pub fn log_path() -> PathBuf {
    config_path().with_file_name("DdcSwitch.log")
}

impl Config {
    /// Loads the config file; the bool is false when no file existed yet.
    pub fn load() -> (Config, bool) {
        let mut cfg = Config::default();
        let Ok(text) = fs::read_to_string(config_path()) else {
            return (cfg, false);
        };
        // Notepad and PowerShell like to prepend a UTF-8 BOM.
        for line in text.trim_start_matches('\u{feff}').lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
                continue;
            }
            let Some((k, v)) = line.split_once('=') else { continue };
            cfg.apply(k.trim(), v.trim());
        }
        (cfg, true)
    }

    fn apply(&mut self, key: &str, val: &str) {
        let flag = || matches!(val.to_ascii_lowercase().as_str(), "1" | "true" | "yes" | "on");
        match key {
            "monitor" => self.monitor = val.parse().unwrap_or(1).max(1),
            "monitor_name" => self.monitor_name = val.to_string(),
            "shutdown_switch" => self.shutdown_switch = flag(),
            "shutdown_input" => self.shutdown_input = parse_input(val).unwrap_or(self.shutdown_input),
            "skip_on_restart" => self.skip_on_restart = flag(),
            "sleep_switch" => self.sleep_switch = flag(),
            "notify_success" => self.notify_success = flag(),
            "language" => self.language = val.to_string(),
            _ => {
                // hotkeyN, hotkeyN_enabled, hotkeyN_name, hotkeyN_input
                let Some(rest) = key.strip_prefix("hotkey") else { return };
                let (num, field) = rest.split_once('_').unwrap_or((rest, ""));
                let Ok(n) = num.parse::<usize>() else { return };
                let Some(b) = n.checked_sub(1).and_then(|i| self.bindings.get_mut(i)) else { return };
                match field {
                    "" => {
                        let (mods, vk) = parse_hotkey(val).unwrap_or((0, 0));
                        b.mods = mods;
                        b.vk = vk;
                    }
                    "enabled" => b.enabled = flag(),
                    "name" => b.name = val.to_string(),
                    "input" => b.input = parse_input(val).unwrap_or(b.input),
                    _ => {}
                }
            }
        }
    }

    pub fn save(&self) -> io::Result<()> {
        let mut s = String::from("# DdcSwitch settings (also editable from the tray icon -> Settings)\r\n");
        s += &format!("language = {}\r\n", self.language);
        s += &format!("monitor = {}\r\nmonitor_name = {}\r\n\r\n", self.monitor, self.monitor_name);
        for (i, b) in self.bindings.iter().enumerate() {
            let n = i + 1;
            s += &format!("hotkey{n} = {}\r\n", hotkey_to_string(b.mods, b.vk));
            s += &format!("hotkey{n}_enabled = {}\r\n", b.enabled);
            s += &format!("hotkey{n}_name = {}\r\n", b.name);
            s += &format!("hotkey{n}_input = {}\r\n\r\n", b.input);
        }
        s += &format!("shutdown_switch = {}\r\n", self.shutdown_switch);
        s += &format!("shutdown_input = {}\r\n", self.shutdown_input);
        s += &format!("skip_on_restart = {}\r\n", self.skip_on_restart);
        s += &format!("sleep_switch = {}\r\n", self.sleep_switch);
        s += &format!("notify_success = {}\r\n", self.notify_success);
        if let Some(dir) = config_path().parent() {
            fs::create_dir_all(dir)?;
        }
        fs::write(config_path(), s)
    }

    /// "MacBook (USB-C) [25]" style title for an input value, using a binding name if one targets it.
    pub fn input_title(&self, input: u32) -> String {
        match self.bindings.iter().find(|b| b.input == input && !b.name.trim().is_empty()) {
            Some(b) => format!("{} [{}]", b.name.trim(), input),
            None => input_label(input),
        }
    }
}

// ---------------------------------------------------------------------------
// Input source names (MCCS VCP 0x60 values)

pub fn input_name(v: u32) -> Option<&'static str> {
    Some(match v {
        1 => "VGA-1",
        2 => "VGA-2",
        3 => "DVI-1",
        4 => "DVI-2",
        5 => "Composite-1",
        6 => "Composite-2",
        7 => "S-Video-1",
        8 => "S-Video-2",
        12 => "Component-1",
        13 => "Component-2",
        15 => "DP-1",
        16 => "DP-2",
        17 => "HDMI-1",
        18 => "HDMI-2",
        27 => "USB-C",
        _ => return None,
    })
}

pub fn input_label(v: u32) -> String {
    match input_name(v) {
        Some(n) => format!("{v} - {n}"),
        None => format!("{v} (0x{v:02X})"),
    }
}

/// Accepts "25", "0x19", "25 - USB-C", or ddcctl-style aliases like "hdmi1".
pub fn parse_input(s: &str) -> Option<u32> {
    let s = s.trim();
    let token: String = s.chars().take_while(|c| c.is_ascii_alphanumeric()).collect();
    let lower = token.to_ascii_lowercase();
    let v = if let Some(hex) = lower.strip_prefix("0x") {
        u32::from_str_radix(hex, 16).ok()
    } else if lower.chars().all(|c| c.is_ascii_digit()) && !lower.is_empty() {
        lower.parse().ok()
    } else {
        match lower.as_str() {
            "vga1" => Some(1),
            "dvi1" => Some(3),
            "dvi2" => Some(4),
            "composite" => Some(8),
            "svideo" => Some(9),
            "dp1" => Some(15),
            "dp2" => Some(16),
            "hdmi1" => Some(17),
            "hdmi2" => Some(18),
            "usbc" => Some(27),
            _ => None,
        }
    }?;
    (1..=0xFFFF).contains(&v).then_some(v)
}

// ---------------------------------------------------------------------------
// Hotkey text <-> (modifiers, virtual key)

const NAMED_KEYS: &[(u32, &str)] = &[
    (0x08, "Backspace"),
    (0x09, "Tab"),
    (0x0D, "Enter"),
    (0x13, "Pause"),
    (0x14, "CapsLock"),
    (0x1B, "Esc"),
    (0x20, "Space"),
    (0x21, "PageUp"),
    (0x22, "PageDown"),
    (0x23, "End"),
    (0x24, "Home"),
    (0x25, "Left"),
    (0x26, "Up"),
    (0x27, "Right"),
    (0x28, "Down"),
    (0x2C, "PrintScreen"),
    (0x2D, "Insert"),
    (0x2E, "Delete"),
    (0x6A, "Num*"),
    (0x6B, "Num+"),
    (0x6D, "Num-"),
    (0x6E, "Num."),
    (0x6F, "Num/"),
    (0x90, "NumLock"),
    (0x91, "ScrollLock"),
    (0xBA, ";"),
    (0xBB, "="),
    (0xBC, ","),
    (0xBD, "-"),
    (0xBE, "."),
    (0xBF, "/"),
    (0xC0, "`"),
    (0xDB, "["),
    (0xDC, "\\"),
    (0xDD, "]"),
    (0xDE, "'"),
];

pub fn vk_name(vk: u32) -> String {
    match vk {
        0x30..=0x39 | 0x41..=0x5A => char::from_u32(vk).unwrap().to_string(),
        0x60..=0x69 => format!("Num{}", vk - 0x60),
        0x70..=0x87 => format!("F{}", vk - 0x6F),
        _ => NAMED_KEYS
            .iter()
            .find(|(k, _)| *k == vk)
            .map(|(_, n)| n.to_string())
            .unwrap_or_else(|| format!("VK{vk:02X}")),
    }
}

fn vk_from_name(name: &str) -> Option<u32> {
    let up = name.to_ascii_uppercase();
    if up.len() == 1 {
        let c = up.as_bytes()[0];
        if c.is_ascii_alphanumeric() {
            return Some(c as u32);
        }
    }
    if let Some(n) = up.strip_prefix('F').and_then(|n| n.parse::<u32>().ok()) {
        if (1..=24).contains(&n) {
            return Some(0x6F + n);
        }
    }
    if let Some(n) = up.strip_prefix("NUM").and_then(|n| n.parse::<u32>().ok()) {
        if n <= 9 {
            return Some(0x60 + n);
        }
    }
    if let Some(hex) = up.strip_prefix("VK") {
        return u32::from_str_radix(hex, 16).ok();
    }
    NAMED_KEYS.iter().find(|(_, n)| n.eq_ignore_ascii_case(name)).map(|(k, _)| *k)
}

pub fn hotkey_to_string(mods: u32, vk: u32) -> String {
    if vk == 0 {
        return String::new();
    }
    let mut s = String::new();
    for (bit, name) in [(MOD_CONTROL, "Ctrl"), (MOD_ALT, "Alt"), (MOD_SHIFT, "Shift"), (MOD_WIN, "Win")] {
        if mods & bit != 0 {
            s += name;
            s += "+";
        }
    }
    s + &vk_name(vk)
}

/// Parses "Ctrl+Alt+Win+Right". Returns (0, 0) for an empty string.
pub fn parse_hotkey(s: &str) -> Option<(u32, u32)> {
    let mut rest = s.trim();
    if rest.is_empty() {
        return Some((0, 0));
    }
    let mut mods = 0;
    'outer: loop {
        for (bit, prefix) in [
            (MOD_CONTROL, "ctrl+"),
            (MOD_CONTROL, "control+"),
            (MOD_ALT, "alt+"),
            (MOD_SHIFT, "shift+"),
            (MOD_WIN, "win+"),
        ] {
            if rest.len() > prefix.len() && rest[..prefix.len()].eq_ignore_ascii_case(prefix) {
                mods |= bit;
                rest = rest[prefix.len()..].trim_start();
                continue 'outer;
            }
        }
        break;
    }
    vk_from_name(rest.trim()).map(|vk| (mods, vk))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hotkey_roundtrip() {
        for (m, vk) in [(MOD_CONTROL | MOD_ALT | MOD_WIN, 0x27), (MOD_SHIFT, 0x6B), (0, 0x7B), (MOD_ALT, 0x41)] {
            let s = hotkey_to_string(m, vk);
            assert_eq!(parse_hotkey(&s), Some((m, vk)), "{s}");
        }
        assert_eq!(parse_hotkey("ctrl+alt+win+pageup"), Some((MOD_CONTROL | MOD_ALT | MOD_WIN, 0x21)));
    }

    #[test]
    fn input_parsing() {
        assert_eq!(parse_input("25"), Some(25));
        assert_eq!(parse_input("0x19"), Some(25));
        assert_eq!(parse_input("17 - HDMI-1"), Some(17));
        assert_eq!(parse_input("25 (0x19)"), Some(25));
        assert_eq!(parse_input("hdmi1"), Some(17));
        assert_eq!(parse_input(""), None);
        assert_eq!(parse_input("abc"), None);
    }
}
