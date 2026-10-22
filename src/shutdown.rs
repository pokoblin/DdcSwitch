// Works out whether the session is ending because of a power-off or a restart.
//
// Window messages don't carry that information, but every user-initiated
// shutdown/restart (Start menu, shutdown.exe, Windows Update, ...) writes
// event 1074 (User32) to the System log *before* applications are notified.
// Its param5 is "power off" or "restart".

use windows::core::{w, HSTRING};
use windows::Win32::System::EventLog::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    PowerOff,
    Restart,
    Unknown,
}

/// Looks at the newest event 1074 no older than `max_age_ms`.
/// Returns the kind plus a human readable description for the log.
pub fn detect(max_age_ms: u64) -> (Kind, String) {
    match newest_1074_xml(max_age_ms) {
        Ok(Some(xml)) => {
            let what = data_value(&xml, "param5").unwrap_or_default();
            let who = data_value(&xml, "param1").unwrap_or_default();
            let l = what.to_lowercase();
            let kind = if l.contains("restart") || l.contains("重新启动") || l.contains("重启") {
                Kind::Restart
            } else if l.contains("power off") || l.contains("shutdown") || l.contains("关机") || l.contains("关闭") {
                Kind::PowerOff
            } else {
                Kind::Unknown
            };
            (kind, format!("事件 1074: 类型=\"{what}\"，发起者={who}"))
        }
        Ok(None) => (Kind::Unknown, format!("最近 {} 秒内没有 1074 事件", max_age_ms / 1000)),
        Err(e) => (Kind::Unknown, format!("读取系统事件日志失败: {e}")),
    }
}

fn newest_1074_xml(max_age_ms: u64) -> windows::core::Result<Option<String>> {
    let query = HSTRING::from(format!(
        "*[System[(EventID=1074) and TimeCreated[timediff(@SystemTime) <= {max_age_ms}]]]"
    ));
    unsafe {
        let results = EvtQuery(
            None,
            w!("System"),
            &query,
            (EvtQueryChannelPath.0 | EvtQueryReverseDirection.0) as u32,
        )?;
        let mut events = [0isize; 1];
        let mut returned = 0u32;
        let next = EvtNext(results, &mut events, 2000, 0, &mut returned);
        if next.is_err() || returned == 0 {
            let _ = EvtClose(results);
            return Ok(None);
        }
        let event = EVT_HANDLE(events[0]);
        let xml = render_xml(event);
        let _ = EvtClose(event);
        let _ = EvtClose(results);
        xml.map(Some)
    }
}

unsafe fn render_xml(event: EVT_HANDLE) -> windows::core::Result<String> {
    let (mut used, mut props) = (0u32, 0u32);
    // First call only reports the needed size.
    let _ = EvtRender(None, event, EvtRenderEventXml.0 as u32, 0, None, &mut used, &mut props);
    let mut buf = vec![0u16; (used as usize / 2) + 1];
    EvtRender(
        None,
        event,
        EvtRenderEventXml.0 as u32,
        (buf.len() * 2) as u32,
        Some(buf.as_mut_ptr().cast()),
        &mut used,
        &mut props,
    )?;
    let end = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    Ok(String::from_utf16_lossy(&buf[..end]))
}

/// Text of `<Data Name='name'>...</Data>` in rendered event XML.
fn data_value(xml: &str, name: &str) -> Option<String> {
    let pos = xml
        .find(&format!("Name='{name}'"))
        .or_else(|| xml.find(&format!("Name=\"{name}\"")))?;
    let rest = &xml[pos..];
    let rest = &rest[rest.find('>')? + 1..];
    let raw = &rest[..rest.find('<')?];
    Some(
        raw.replace("&lt;", "<")
            .replace("&gt;", ">")
            .replace("&quot;", "\"")
            .replace("&apos;", "'")
            .replace("&amp;", "&"),
    )
}

#[cfg(test)]
mod tests {
    #[test]
    fn data_value() {
        let xml = "<EventData><Data Name='param1'>C:\\x.exe (PC)</Data><Data Name='param5'>power off</Data><Data Name='param6'></Data></EventData>";
        assert_eq!(super::data_value(xml, "param5").as_deref(), Some("power off"));
        assert_eq!(super::data_value(xml, "param6").as_deref(), Some(""));
        assert_eq!(super::data_value(xml, "param9"), None);
    }
}
