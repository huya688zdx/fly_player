[CmdletBinding()]
param([switch]$ShowWindow)
$ErrorActionPreference = 'Stop'
$bifProject = Split-Path $PSScriptRoot -Parent
& (Join-Path $PSScriptRoot 'run-windows-isolated.ps1') `
    -Executable (Join-Path $bifProject 'build\windows\x64-mask-p0-integrated\bundle\fly_player.exe') `
    -DataHome (Join-Path $bifProject '.runtime\bif-integration') `
    -ShowWindow:$ShowWindow
