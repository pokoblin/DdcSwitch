// Append-only log next to the config file. Flushed to disk on every line so
// that entries written during shutdown survive.

use std::fs::{self, OpenOptions};
use std::io::Write;

use windows::Win32::System::SystemInformation::GetLocalTime;

use crate::config;

const MAX_SIZE: u64 = 512 * 1024;

pub fn log(msg: impl AsRef<str>) {
    let t = unsafe { GetLocalTime() };
    let line = format!(
        "{:04}-{:02}-{:02} {:02}:{:02}:{:02}.{:03}  {}\r\n",
        t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, t.wMilliseconds,
        msg.as_ref()
    );
    let path = config::log_path();
    if let Some(dir) = path.parent() {
        let _ = fs::create_dir_all(dir);
    }
    if fs::metadata(&path).map(|m| m.len() > MAX_SIZE).unwrap_or(false) {
        let _ = fs::rename(&path, path.with_extension("old.log"));
    }
    if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(&path) {
        let _ = f.write_all(line.as_bytes());
        let _ = f.sync_data();
    }
}
