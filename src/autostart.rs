// "Run at login" via HKCU\Software\Microsoft\Windows\CurrentVersion\Run.

use windows::core::{w, PCWSTR};
use windows::Win32::Foundation::ERROR_SUCCESS;
use windows::Win32::System::Registry::*;

const RUN_KEY: PCWSTR = w!("Software\\Microsoft\\Windows\\CurrentVersion\\Run");
const VALUE: PCWSTR = w!("DdcSwitch");

fn command_line() -> String {
    let exe = std::env::current_exe().unwrap_or_default();
    format!("\"{}\" --autostart", exe.display())
}

fn current_value() -> Option<String> {
    unsafe {
        let mut size = 0u32;
        if RegGetValueW(HKEY_CURRENT_USER, RUN_KEY, VALUE, RRF_RT_REG_SZ, None, None, Some(&mut size)) != ERROR_SUCCESS {
            return None;
        }
        let mut buf = vec![0u16; size as usize / 2 + 1];
        let mut size = (buf.len() * 2) as u32;
        if RegGetValueW(
            HKEY_CURRENT_USER,
            RUN_KEY,
            VALUE,
            RRF_RT_REG_SZ,
            None,
            Some(buf.as_mut_ptr().cast()),
            Some(&mut size),
        ) != ERROR_SUCCESS
        {
            return None;
        }
        let end = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
        Some(String::from_utf16_lossy(&buf[..end]))
    }
}

pub fn is_enabled() -> bool {
    current_value().is_some()
}

pub fn set(enable: bool) -> Result<(), String> {
    let err = unsafe {
        if enable {
            let data: Vec<u16> = command_line().encode_utf16().chain(Some(0)).collect();
            RegSetKeyValueW(
                HKEY_CURRENT_USER,
                RUN_KEY,
                VALUE,
                REG_SZ.0,
                Some(data.as_ptr().cast()),
                (data.len() * 2) as u32,
            )
        } else {
            let e = RegDeleteKeyValueW(HKEY_CURRENT_USER, RUN_KEY, VALUE);
            if e == windows::Win32::Foundation::ERROR_FILE_NOT_FOUND {
                ERROR_SUCCESS
            } else {
                e
            }
        }
    };
    if err == ERROR_SUCCESS {
        Ok(())
    } else {
        Err(format!("写入注册表失败，错误码 {}", err.0))
    }
}

/// If autostart is on but points at another copy of the exe (it was moved), repoint it here.
pub fn refresh_path() {
    if let Some(v) = current_value() {
        if v != command_line() {
            let _ = set(true);
        }
    }
}
