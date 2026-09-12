[CmdletBinding()]
param(
    [string]$Executable = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\windows\x64-mask-p0-integrated\bundle\fly_player.exe'),
    [string]$DataHome = (Join-Path (Split-Path $PSScriptRoot -Parent) '.runtime\llm-b-test'),
    [switch]$ShowWindow
)
$ErrorActionPreference = 'Stop'
$profilePath = [IO.Path]::GetFullPath($DataHome)
if ($DataHome -notmatch '^[Ee]:[\\/]' -or $profilePath -notmatch '^[Ee]:[\\/]') {
    throw 'This development launcher requires an absolute local E: profile path.'
}
$programPath = (Resolve-Path -LiteralPath $Executable).Path
if ($programPath -notmatch '^[Ee]:[\\/]') { throw 'The development executable must also be on E:.' }
$profileVariables = @{
    FLY_PLAYER_DATA_HOME = $profilePath
    TEMP = (Join-Path $profilePath 'tmp')
    TMP = (Join-Path $profilePath 'tmp')
    LOCALAPPDATA = (Join-Path $profilePath 'local')
    APPDATA = (Join-Path $profilePath 'roaming')
}
$previousVariables = @{}
try {
    foreach ($name in $profileVariables.Keys) {
        $previousVariables[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        New-Item -ItemType Directory -Path $profileVariables[$name] -Force | Out-Null
        [Environment]::SetEnvironmentVariable($name, $profileVariables[$name], 'Process')
    }
    $windowStyle = if ($ShowWindow) { 'Normal' } else { 'Hidden' }
    $process = Start-Process -FilePath $programPath -WorkingDirectory (Split-Path $programPath -Parent) -WindowStyle $windowStyle -PassThru
    [pscustomobject]@{ ProcessId = $process.Id; Executable = $programPath; DataHome = $profilePath }
} finally {
    foreach ($name in $previousVariables.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousVariables[$name], 'Process')
    }
}
