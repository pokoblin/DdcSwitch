# 编译并安装 DdcSwitch 到 %LOCALAPPDATA%\Programs\DdcSwitch，然后启动。
# 首次启动会自动加入“开机自动运行”（可在托盘菜单中关闭）。
$ErrorActionPreference = 'Stop'

cargo build --release --manifest-path "$PSScriptRoot\Cargo.toml"
if ($LASTEXITCODE -ne 0) { throw "cargo build 失败" }

$dest = Join-Path $env:LOCALAPPDATA 'Programs\DdcSwitch'
$exe = Join-Path $dest 'DdcSwitch.exe'
New-Item -ItemType Directory -Force $dest | Out-Null

# 先让正在运行的实例正常退出（这样托盘图标会被移除），再覆盖文件
if (Test-Path $exe) { & $exe --quit | Out-Null }
Get-Process DdcSwitch -ErrorAction SilentlyContinue | Stop-Process -Force

Copy-Item "$PSScriptRoot\target\release\DdcSwitch.exe" $exe -Force
Start-Process $exe
Write-Host "已安装到 $exe 并启动"
