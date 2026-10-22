// Small command line interface, mostly for diagnostics:
//   DdcSwitch.exe --list | --get | --set <input> | --caps | --detect  [--monitor N]

use windows::core::PCWSTR;
use windows::Win32::Foundation::{LPARAM, WPARAM};
use windows::Win32::System::Console::{AttachConsole, ATTACH_PARENT_PROCESS};
use windows::Win32::UI::WindowsAndMessaging::{FindWindowW, PostMessageW, WM_CLOSE};

use crate::config::{self, Config, VCP_INPUT};
use crate::{ddc, shutdown};

const USAGE: &str = "DdcSwitch - switch the monitor input source over DDC/CI

Without arguments DdcSwitch runs in the system tray. Diagnostic commands:
  --list            list monitors
  --get             read the current input source
  --set <input>     switch input (number, 0x hex, or an alias such as hdmi1/dp1/usbc)
  --caps            read the capabilities string and supported inputs
  --detect          show how the last shutdown/restart (past 24 h) is classified
  --quit            ask the running tray app to exit
  --monitor <N>     monitor number (default: the one in the config file)
  --config <path>   use another config file";

pub fn run(args: &[String]) -> i32 {
    unsafe {
        let _ = AttachConsole(ATTACH_PARENT_PROCESS);
    }
    let (cfg, _) = Config::load();
    crate::i18n::apply(&cfg.language);
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
            println!("{} DDC/CI monitor(s) detected:", names.len());
            for (i, n) in names.iter().enumerate() {
                println!("  {}: {}", i + 1, n);
            }
            Ok(())
        }
        Some(("get", _)) => ddc::get_input(monitor, &monitor_name).map(|cur| {
            println!("Current input: {}", config::input_label(cur));
        }),
        Some(("set", Some(v))) => match config::parse_input(v) {
            Some(input) => ddc::set_vcp(monitor, &monitor_name, VCP_INPUT, input)
                .map(|m| println!("{m} → {}", config::input_label(input))),
            None => Err(format!("Invalid input source: {v}")),
        },
        Some(("caps", _)) => ddc::capabilities(monitor, &monitor_name).map(|caps| {
            println!("{caps}\n");
            println!("Supported inputs (VCP 0x60):");
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
            eprintln!("Error: {e}");
            1
        }
    }
}

/// Asks a running tray instance to exit (removing its tray icon cleanly) and waits for it.
fn quit_running() {
    unsafe {
        let find = || FindWindowW(crate::MAIN_CLASS, PCWSTR::null()).ok();
        let Some(h) = find() else {
            println!("DdcSwitch is not running");
            return;
        };
        let _ = PostMessageW(Some(h), WM_CLOSE, WPARAM(0), LPARAM(0));
        for _ in 0..50 {
            if find().is_none() {
                println!("Exited");
                return;
            }
            std::thread::sleep(std::time::Duration::from_millis(100));
        }
        println!("Timed out waiting for DdcSwitch to exit");
    }
}
