$ErrorActionPreference = 'Stop'
. 'E:\fly_play_recovere\.tools\portable-build\enter-portable-env.ps1'
$taskPlayer = Join-Path $PSScriptRoot 'build\windows\x64-mask-p0-integrated\bundle\fly_player.exe'
if (-not (Test-Path -LiteralPath $taskPlayer)) {
    throw '此独立目录尚未完成构建，请先构建 NAS 弹幕修复版。'
}
Start-Process -FilePath $taskPlayer -WorkingDirectory (Split-Path -Parent $taskPlayer)
