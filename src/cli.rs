// Small command line interface, mostly for diagnostics:
//   DdcSwitch.exe --list | --get | --set <input> | --caps | --detect  [--monitor N]

use windows::core::PCWSTR;
use windows::Win32::Foundation::{LPARAM, WPARAM};
use windows::Win32::System::Console::{AttachConsole, ATTACH_PARENT_PROCESS};
use windows::Win32::UI::WindowsAndMessaging::{FindWindowW, PostMessageW, WM_CLOSE};

use crate::config::{self, Config, VCP_INPUT};
use crate::{ddc, shutdown};

const USAGE: &str = "DdcSwitch — 显示器输入源切换（托盘程序）

不带参数运行时常驻托盘。诊断用命令行：
  --list            列出显示器
  --get             读取当前输入源
  --set <输入源>    切换输入源（数字、0x 十六进制或 hdmi1/dp1/usbc 等别名）
  --caps            读取显示器支持的输入源
  --detect          查看最近 24 小时的关机/重启事件判断结果
  --quit            退出正在运行的托盘程序
  --monitor <N>     指定显示器（默认使用配置文件中的显示器）
  --config <路径>   使用指定的配置文件";

pub fn run(args: &[String]) -> i32 {
    unsafe {
        let _ = AttachConsole(ATTACH_PARENT_PROCESS);
    }
    let (cfg, _) = Config::load();
    let mut monitor = cfg.monitor;
    let mut monitor_name = cfg.monitor_name.clone();
    let mut command: Option<(&str, Option<&str>)> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--monitor" | "-d" => {
                monitor = args.get(i + 1).and_then(|v| v.parse().ok()).unwrap_or(1);
                monitor_name.clear();
                i += 1;
            }
            "--set" => {
                command = Some(("set", args.get(i + 1).map(|s| s.as_str())));
                i += 1;
            }
            c @ ("--list" | "--get" | "--caps" | "--detect" | "--quit") => command = Some((c.trim_start_matches('-'), None)),
            _ => command = Some(("help", None)),
        }
        i += 1;
    }

    let result: Result<(), String> = match command {
        Some(("list", _)) => {
            let names = ddc::list_names();
            println!("检测到 {} 台支持 DDC/CI 的显示器:", names.len());
            for (i, n) in names.iter().enumerate() {
                println!("  {}: {}", i + 1, n);
            }
            Ok(())
        }
        Some(("get", _)) => ddc::get_input(monitor, &monitor_name).map(|cur| {
            println!("当前输入源: {}", config::input_label(cur));
        }),
        Some(("set", Some(v))) => match config::parse_input(v) {
            Some(input) => ddc::set_vcp(monitor, &monitor_name, VCP_INPUT, input)
                .map(|m| println!("{m} → {}", config::input_label(input))),
            None => Err(format!("无效的输入源: {v}")),
        },
        Some(("caps", _)) => ddc::capabilities(monitor, &monitor_name).map(|caps| {
            println!("{caps}\n");
            println!("支持的输入源 (VCP 0x60):");
            for v in ddc::parse_input_caps(&caps) {
                println!("  {}", config::input_label(v));
            }
        }),
        Some(("detect", _)) => {
            let (kind, detail) = shutdown::detect(24 * 3600 * 1000);
            println!("{kind:?}: {detail}");
            Ok(())
        }
        Some(("quit", _)) => {
            quit_running();
            Ok(())
        }
        _ => {
            println!("{USAGE}");
            Ok(())
        }
    };
    match result {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("错误: {e}");
            1
        }
    }
}

/// Asks a running tray instance to exit (removing its tray icon cleanly) and waits for it.
fn quit_running() {
    unsafe {
        let find = || FindWindowW(crate::MAIN_CLASS, PCWSTR::null()).ok();
        let Some(h) = find() else {
            println!("没有正在运行的 DdcSwitch");
            return;
        };
        let _ = PostMessageW(Some(h), WM_CLOSE, WPARAM(0), LPARAM(0));
        for _ in 0..50 {
            if find().is_none() {
                println!("已退出");
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        println!("等待退出超时");
    }
}
