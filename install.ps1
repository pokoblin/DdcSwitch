# Installs DdcSwitch for the current user:
#   %LOCALAPPDATA%\Programs\DdcSwitch\DdcSwitch.exe, a Start menu shortcut,
#   "Start with Windows" and an entry in Settings > Apps (removed again by uninstall.ps1).
#
#   .\install.ps1                 build from source, then install
#   .\install.ps1 -Exe <path>     install a prebuilt DdcSwitch.exe, e.g. from a release
param([string]$Exe)

if (-not $Exe) {
    # cargo reports progress on stderr; don't let that count as a failure.
    cargo build --release --manifest-path "$PSScriptRoot\Cargo.toml"
    if ($LASTEXITCODE -ne 0) { throw "cargo build failed" }
    $Exe = "$PSScriptRoot\target\release\DdcSwitch.exe"
}

$ErrorActionPreference = 'Stop'
$Exe = (Resolve-Path $Exe).Path
$dest = Join-Path $env:LOCALAPPDATA 'Programs\DdcSwitch'
$target = Join-Path $dest 'DdcSwitch.exe'
New-Item -ItemType Directory -Force $dest | Out-Null

# Let a running copy (wherever it lives) exit cleanly so its tray icon disappears.
& $Exe --quit | Out-Null
Get-Process DdcSwitch -ErrorAction SilentlyContinue | Stop-Process -Force

Copy-Item $Exe $target -Force
Copy-Item "$PSScriptRoot\uninstall.ps1" $dest -Force
$version = (Get-Item $target).VersionInfo.FileVersion

# Start menu shortcut
$lnk = Join-Path ([Environment]::GetFolderPath('Programs')) 'DdcSwitch.lnk'
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$shortcut.TargetPath = $target
$shortcut.WorkingDirectory = $dest
$shortcut.Description = 'Switch the monitor input source over DDC/CI'
$shortcut.Save()

# Start with Windows
Set-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name DdcSwitch -Value "`"$target`" --autostart"

# Settings > Apps entry
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DdcSwitch'
New-Item $key -Force | Out-Null
$strings = @{
    DisplayName     = 'DdcSwitch'
    DisplayVersion  = $version
    Publisher       = 'pokoblin'
    DisplayIcon     = "$target,0"
    InstallLocation = $dest
    URLInfoAbout    = 'https://github.com/pokoblin/DdcSwitch'
    UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$dest\uninstall.ps1`""
}
foreach ($name in $strings.Keys) { New-ItemProperty $key -Name $name -Value $strings[$name] -PropertyType String -Force | Out-Null }
$dwords = @{ NoModify = 1; NoRepair = 1; EstimatedSize = [int]((Get-Item $target).Length / 1KB) }
foreach ($name in $dwords.Keys) { New-ItemProperty $key -Name $name -Value $dwords[$name] -PropertyType DWord -Force | Out-Null }

Start-Process $target
Write-Host "DdcSwitch $version installed to $dest and started"
