# DdcSwitch

Windows 托盘小工具，通过 DDC/CI 切换显示器输入源：

- **关机前自动切换**：在 Windows 11 中点「关机」时先把显示器切到 Mac 所在的输入源（例如 USB-C = 25），然后 Windows 照常关机。
- **快捷键切换**：Windows 使用中按快捷键随时切换，最多 3 组（默认 `Ctrl+Alt+Win+Right` → 25）。
- **托盘图标**：点击图标弹出菜单，可以切换输入源、开关关机切换和开机自动运行、打开设置、查看日志、退出。

它直接调用 Windows 的显示器配置 API（dxva2），不依赖 `ddcctl.exe`，所以关机过程中也不用启动外部进程。

## 安装

```powershell
.\install.ps1
```

这个脚本会编译 release 版，复制到 `%LOCALAPPDATA%\Programs\DdcSwitch\DdcSwitch.exe` 并启动。第一次运行时会自动加入开机启动（注册表 `HKCU\...\Run`），因为程序必须在后台运行才能在关机时切换输入源。

> 原来的 AutoHotkey 脚本如果还绑着 `Ctrl+Alt+Win+Right`，请删掉那一段，否则一次按键会切换两次。

## 关机时具体做了什么

1. 程序有一个隐藏的顶层窗口，并通过 `SetProcessShutdownParameters` 把自己排在应用程序关机顺序的最后。
2. 只在 `WM_ENDSESSION(TRUE)` 时才切换，也就是关机已经确定的时候。如果有其他程序阻止关机、Windows 显示“这些应用正在阻止关机”，这个界面仍然显示在 Windows 输入源上；取消关机则什么都不做。
3. 「重启时不切换」：读取系统日志里的 User32 事件 1074（开始菜单、`shutdown.exe`、Windows 更新等都会在通知应用之前写入这个事件），根据其中的 `power off` / `restart` 判断是关机还是重启。判断不出来时按关机处理，照样切换。
4. 注销、安装程序通过重启管理器关闭本程序时不切换。
5. 每一步都写进日志，开机后可以在托盘菜单 → 查看日志 中确认上次关机时发生了什么。

可选：「睡眠前也切换」（`PBT_APMSUSPEND`），默认关闭。

## 设置

托盘菜单 → 设置…：

| 项目 | 说明 |
| --- | --- |
| 显示器 | 编号和 `ddcctl -l` 相同；打开设置窗口时会读取当前输入源以及显示器报告支持的输入源 |
| 快捷键 | 名称 / 目标输入源 / 组合键。Win 键录制不进快捷键框，需要时勾选「+ Win」 |
| 关机前切换到 | 关机时要切到的输入源 |
| 重启时不切换 | 见上文 |
| 开机时自动运行 | 写入或删除 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\DdcSwitch` |

输入源可以直接填数字（`25`）、十六进制（`0x19`）或别名（`hdmi1`、`dp1`、`usbc`）。

配置文件和日志在 `%APPDATA%\DdcSwitch\`（`config.ini`、`DdcSwitch.log`），也可以直接编辑 `config.ini`，改完后重启程序生效。

## 命令行（诊断用）

```
DdcSwitch.exe --list            列出显示器
DdcSwitch.exe --get             读取当前输入源
DdcSwitch.exe --set 25          切换输入源
DdcSwitch.exe --caps            读取显示器能力字符串和支持的输入源
DdcSwitch.exe --detect          查看最近一次关机/重启事件的判断结果
DdcSwitch.exe --quit            退出正在运行的托盘程序
  可选：--monitor N、--config <路径>
```

不带参数运行时常驻托盘；如果已经在运行，再启动一次会打开设置窗口。

## 构建

需要 Rust（MSVC 工具链）。如果装了 Windows SDK（`rc.exe`），图标和版本信息会嵌入 exe。

```powershell
cargo build --release
cargo test --release
```

## 已知限制

- 显示器的 OSD 菜单里要开启 DDC/CI。
- 关机后显示器停在 Mac 的输入源；下次开 Windows 时，如果显示器不会自动找信号，需要在 Mac 上切回来（或者按显示器按钮）。
- 「重启时不切换」依赖系统日志事件 1074。如果系统被强制断电，或者其他工具绕过 `InitiateShutdown` 关机，就判断不出类型，这时按关机处理。
