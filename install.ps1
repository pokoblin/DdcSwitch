# Builds DdcSwitch, installs it to %LOCALAPPDATA%\Programs\DdcSwitch and starts it.
# On first launch DdcSwitch adds itself to "Start with Windows" (can be turned off in the tray menu).

# cargo reports progress on stderr; don't let that count as a failure.
cargo build --release --manifest-path "$PSScriptRoot\Cargo.toml"
if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }

$ErrorActionPreference = 'Stop'
$dest = Join-Path $env:LOCALAPPDATA 'Programs\DdcSwitch'
$exe = Join-Path $dest 'DdcSwitch.exe'
New-Item -ItemType Directory -Force $dest | Out-Null

# Let a running copy exit cleanly (so its tray icon disappears) before replacing the file.
if (Test-Path $exe) { & $exe --quit | Out-Null }
Get-Process DdcSwitch -ErrorAction SilentlyContinue | Stop-Process -Force

Copy-Item "$PSScriptRoot\target\release\DdcSwitch.exe" $exe -Force
Start-Process $exe
Write-Host "Installed to $exe and started"
