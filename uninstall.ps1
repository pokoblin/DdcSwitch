# Removes DdcSwitch installed by install.ps1: program folder, Start menu shortcut,
# "Start with Windows" and the Settings > Apps entry.
# Settings and the log in %APPDATA%\DdcSwitch are kept unless -RemoveSettings is given.
param([switch]$RemoveSettings)

$dest = Join-Path $env:LOCALAPPDATA 'Programs\DdcSwitch'
$exe = Join-Path $dest 'DdcSwitch.exe'

if (Test-Path $exe) { & $exe --quit | Out-Null }
Get-Process DdcSwitch -ErrorAction SilentlyContinue | Stop-Process -Force

Remove-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name DdcSwitch -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Programs')) 'DdcSwitch.lnk') -ErrorAction SilentlyContinue
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\DdcSwitch' -Recurse -ErrorAction SilentlyContinue
if ($RemoveSettings) { Remove-Item -Recurse "$env:APPDATA\DdcSwitch" -ErrorAction SilentlyContinue }

# This script lives inside the program folder, so remove the folder once it has exited.
Start-Process cmd.exe -ArgumentList "/c ping -n 3 127.0.0.1 >nul & rmdir /s /q `"$dest`"" -WindowStyle Hidden
Write-Host 'DdcSwitch uninstalled'
