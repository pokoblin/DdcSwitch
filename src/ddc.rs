// DDC/CI access through the Windows Monitor Configuration API (dxva2.dll).
// Monitors are re-enumerated for every operation so display changes are picked up.

use std::collections::HashMap;
use std::sync::Mutex;
use std::thread;
use std::time::Duration;

use windows::core::BOOL;
use windows::Win32::Devices::Display::*;
use windows::Win32::Foundation::*;
use windows::Win32::Graphics::Gdi::*;

/// Serialises DDC/CI traffic: the monitor's I2C bus doesn't like concurrent requests.
static DDC_LOCK: Mutex<()> = Mutex::new(());

pub struct Monitor {
    pub name: String,
    handle: HANDLE,
}

pub struct Monitors(pub Vec<Monitor>);

impl Drop for Monitors {
    fn drop(&mut self) {
        for m in &self.0 {
            unsafe {
                let _ = DestroyPhysicalMonitor(m.handle);
            }
        }
    }
}

impl Monitors {
    /// Picks the monitor named `name` if present, otherwise the 1-based `index`.
    fn resolve(&self, index: usize, name: &str) -> Result<&Monitor, String> {
        if !name.is_empty() {
            if let Some(m) = self.0.iter().find(|m| m.name == name) {
                return Ok(m);
            }
        }
        self.0
            .get(index.max(1) - 1)
            .ok_or_else(|| format!("未找到显示器 #{index}（共检测到 {} 台支持 DDC/CI 的显示器）", self.0.len()))
    }
}

fn wide_to_string(w: &[u16]) -> String {
    let end = w.iter().position(|&c| c == 0).unwrap_or(w.len());
    String::from_utf16_lossy(&w[..end])
}

pub fn enumerate() -> Monitors {
    let names = friendly_names();
    let mut hmons: Vec<HMONITOR> = Vec::new();

    unsafe extern "system" fn collect(h: HMONITOR, _: HDC, _: *mut RECT, data: LPARAM) -> BOOL {
        let v = &mut *(data.0 as *mut Vec<HMONITOR>);
        v.push(h);
        TRUE
    }

    let mut out = Vec::new();
    unsafe {
        let _ = EnumDisplayMonitors(None, None, Some(collect), LPARAM(&mut hmons as *mut _ as isize));
        for h in hmons {
            let mut mi = MONITORINFOEXW::default();
            mi.monitorInfo.cbSize = std::mem::size_of::<MONITORINFOEXW>() as u32;
            let device = if GetMonitorInfoW(h, &mut mi as *mut _ as *mut MONITORINFO).as_bool() {
                wide_to_string(&mi.szDevice)
            } else {
                String::new()
            };
            let mut count = 0u32;
            if GetNumberOfPhysicalMonitorsFromHMONITOR(h, &mut count).is_err() || count == 0 {
                continue;
            }
            let mut phys = vec![PHYSICAL_MONITOR::default(); count as usize];
            if GetPhysicalMonitorsFromHMONITOR(h, &mut phys).is_err() {
                continue;
            }
            for pm in &phys {
                // PHYSICAL_MONITOR is packed: copy fields out before borrowing them.
                let desc_buf = pm.szPhysicalMonitorDescription;
                let desc = wide_to_string(&desc_buf);
                let name = match names.get(&device) {
                    Some(n) if count == 1 => n.clone(),
                    _ => desc,
                };
                let handle = pm.hPhysicalMonitor;
                out.push(Monitor { name, handle });
            }
        }
    }
    Monitors(out)
}

/// GDI device name (\\.\DISPLAY1) -> "Dell U2725QE (HDMI)".
fn friendly_names() -> HashMap<String, String> {
    let mut map = HashMap::new();
    unsafe {
        let (mut np, mut nm) = (0u32, 0u32);
        if GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &mut np, &mut nm) != ERROR_SUCCESS {
            return map;
        }
        let mut paths = vec![DISPLAYCONFIG_PATH_INFO::default(); np as usize];
        let mut modes = vec![DISPLAYCONFIG_MODE_INFO::default(); nm as usize];
        if QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &mut np, paths.as_mut_ptr(), &mut nm, modes.as_mut_ptr(), None)
            != ERROR_SUCCESS
        {
            return map;
        }
        for p in &paths[..np as usize] {
            let mut src = DISPLAYCONFIG_SOURCE_DEVICE_NAME::default();
            src.header.r#type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            src.header.size = std::mem::size_of::<DISPLAYCONFIG_SOURCE_DEVICE_NAME>() as u32;
            src.header.adapterId = p.sourceInfo.adapterId;
            src.header.id = p.sourceInfo.id;
            if DisplayConfigGetDeviceInfo(&mut src.header) != 0 {
                continue;
            }
            let mut tgt = DISPLAYCONFIG_TARGET_DEVICE_NAME::default();
            tgt.header.r#type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
            tgt.header.size = std::mem::size_of::<DISPLAYCONFIG_TARGET_DEVICE_NAME>() as u32;
            tgt.header.adapterId = p.targetInfo.adapterId;
            tgt.header.id = p.targetInfo.id;
            if DisplayConfigGetDeviceInfo(&mut tgt.header) != 0 {
                continue;
            }
            let mut name = wide_to_string(&tgt.monitorFriendlyDeviceName);
            if name.is_empty() {
                continue;
            }
            let conn = match tgt.outputTechnology {
                DISPLAYCONFIG_OUTPUT_TECHNOLOGY_HDMI => Some("HDMI"),
                DISPLAYCONFIG_OUTPUT_TECHNOLOGY_DISPLAYPORT_EXTERNAL => Some("DisplayPort"),
                DISPLAYCONFIG_OUTPUT_TECHNOLOGY_DVI => Some("DVI"),
                DISPLAYCONFIG_OUTPUT_TECHNOLOGY_HD15 => Some("VGA"),
                _ => None,
            };
            if let Some(c) = conn {
                name = format!("{name} ({c})");
            }
            map.insert(wide_to_string(&src.viewGdiDeviceName), name);
        }
    }
    map
}

pub fn list_names() -> Vec<String> {
    let _g = DDC_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    enumerate().0.iter().map(|m| m.name.clone()).collect()
}

/// Sets a VCP feature (retrying a few times, DDC/CI is flaky). Returns the monitor name.
pub fn set_vcp(index: usize, name: &str, code: u8, value: u32) -> Result<String, String> {
    let _g = DDC_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mons = enumerate();
    let m = mons.resolve(index, name)?;
    let mut last = 0;
    for attempt in 0..4 {
        if attempt > 0 {
            thread::sleep(Duration::from_millis(80));
        }
        if unsafe { SetVCPFeature(m.handle, code, value) } != 0 {
            return Ok(m.name.clone());
        }
        last = unsafe { GetLastError().0 };
    }
    Err(format!("{}: SetVCPFeature(0x{code:02X}, {value}) 失败，错误码 0x{last:08X}", m.name))
}

/// Reads a VCP feature, returning (current, maximum).
pub fn get_vcp(index: usize, name: &str, code: u8) -> Result<(u32, u32), String> {
    let _g = DDC_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mons = enumerate();
    let m = mons.resolve(index, name)?;
    let mut last = 0;
    // Monitors often reject requests that arrive right after another one; back off.
    for delay in [0, 100, 300, 600] {
        thread::sleep(Duration::from_millis(delay));
        let (mut cur, mut max) = (0u32, 0u32);
        if unsafe { GetVCPFeatureAndVCPFeatureReply(m.handle, code, None, &mut cur, Some(&mut max)) } != 0 {
            return Ok((cur, max));
        }
        last = unsafe { GetLastError().0 };
    }
    Err(format!("{}: 读取 VCP 0x{code:02X} 失败，错误码 0x{last:08X}", m.name))
}

/// Current input source. Only the low byte is meaningful: e.g. Dell answers 0x1111 for HDMI-1 (0x11).
pub fn get_input(index: usize, name: &str) -> Result<u32, String> {
    get_vcp(index, name, crate::config::VCP_INPUT).map(|(cur, _)| cur & 0xFF)
}

/// Raw MCCS capabilities string (slow: ~1-2 s on most monitors).
pub fn capabilities(index: usize, name: &str) -> Result<String, String> {
    let _g = DDC_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    let mons = enumerate();
    let m = mons.resolve(index, name)?;
    let mut error = String::new();
    for delay in [0, 300, 800] {
        thread::sleep(Duration::from_millis(delay));
        unsafe {
            let mut len = 0u32;
            if GetCapabilitiesStringLength(m.handle, &mut len) == 0 || len == 0 {
                error = format!("{}: 无法读取能力字符串（显示器可能关闭了 DDC/CI）", m.name);
                continue;
            }
            let mut buf = vec![0u8; len as usize];
            if CapabilitiesRequestAndCapabilitiesReply(m.handle, &mut buf) == 0 {
                error = format!("{}: 读取能力字符串失败", m.name);
                continue;
            }
            let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
            return Ok(String::from_utf8_lossy(&buf[..end]).into_owned());
        }
    }
    Err(error)
}

/// Values listed for VCP 0x60 in an MCCS capabilities string, e.g. `vcp(... 60( 19 0F 11) ...)`.
pub fn parse_input_caps(caps: &str) -> Vec<u32> {
    let lower = caps.to_ascii_lowercase();
    let Some(start) = lower.find("vcp(") else { return Vec::new() };
    let s = lower[start + 4..].as_bytes();
    let mut i = 0;
    let skip_ws = |i: &mut usize| {
        while *i < s.len() && s[*i].is_ascii_whitespace() {
            *i += 1;
        }
    };
    let read_hex = |i: &mut usize| -> Option<u32> {
        let st = *i;
        while *i < s.len() && s[*i].is_ascii_hexdigit() {
            *i += 1;
        }
        std::str::from_utf8(&s[st..*i]).ok().and_then(|t| u32::from_str_radix(t, 16).ok())
    };
    loop {
        skip_ws(&mut i);
        if i >= s.len() || s[i] == b')' {
            return Vec::new();
        }
        let Some(code) = read_hex(&mut i) else {
            i += 1; // unexpected character, skip it
            continue;
        };
        skip_ws(&mut i);
        if i < s.len() && s[i] == b'(' {
            i += 1;
            let mut values = Vec::new();
            loop {
                skip_ws(&mut i);
                if i >= s.len() || s[i] == b')' {
                    i += 1;
                    break;
                }
                match read_hex(&mut i) {
                    Some(v) => values.push(v),
                    None => i += 1,
                }
            }
            if code == 0x60 {
                return values;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn caps_inputs() {
        let caps = "(prot(monitor)type(lcd)model(U2725QE)cmds(01 02)vcp(02 04 14(01 04 05) 16 60( 19 0F 11) 66(00F2) E2(00 02))mccs_ver(2.1))";
        assert_eq!(super::parse_input_caps(caps), vec![0x19, 0x0F, 0x11]);
        assert!(super::parse_input_caps("vcp(10 12)").is_empty());
    }
}
