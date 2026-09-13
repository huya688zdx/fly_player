[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][int]$TargetProcessId,
    [ValidateSet('Capture','Click','Login','Key','Text','Hover')][string]$Action = 'Capture',
    [string]$DataHome = (Join-Path (Split-Path $PSScriptRoot -Parent) '.runtime\oped-real-validation'),
    [string]$Name = 'observation',
    [string]$ServiceUrl = 'http://127.0.0.1:18789',
    [string]$AccessFile = 'E:\fly_play_recovere\fly-data-service\.private\initial-access.json',
    [int]$X = -1,
    [int]$Y = -1,
    [string]$Text = '',
    [ValidateSet('Space','Escape','Right','Left')][string]$Key = 'Space'
)
$ErrorActionPreference = 'Stop'
. 'E:\fly_play_recovere\fly-data-service\scripts\enter-env.ps1'
$taskProject = Split-Path $PSScriptRoot -Parent
$taskExpected = (Resolve-Path -LiteralPath (Join-Path $taskProject 'build\windows\x64-mask-p0-integrated\bundle\fly_player.exe')).Path
$taskProcess = Get-Process -Id $TargetProcessId
if ($taskProcess.Path -ne $taskExpected) { throw 'The target is not this B worktree executable.' }
$taskProfile = [IO.Path]::GetFullPath($DataHome)
if ($taskProfile -notmatch '^[Ee]:[\\/]') { throw 'Evidence must stay on E:.' }
if ($Name -notmatch '^[A-Za-z0-9_.-]+$') { throw 'Use a simple evidence filename.' }
New-Item -ItemType Directory -Path $taskProfile -Force | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FlyOpedWindow {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out Rect rect);
 [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr dc, uint flags);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
 [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr SendMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint processId);
}
'@
$taskHandle = $taskProcess.MainWindowHandle
if ($taskHandle -eq [IntPtr]::Zero) { throw 'The B process has no interactive window.' }
if ([FlyOpedWindow]::IsIconic($taskHandle)) {
    [FlyOpedWindow]::ShowWindow($taskHandle,9) | Out-Null
    Start-Sleep -Milliseconds 300
}
$taskWindow = [System.Windows.Automation.AutomationElement]::FromHandle($taskHandle)
$taskView = $taskWindow.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.ClassName -eq 'FLUTTERVIEW' -and $_.Current.NativeWindowHandle -ne 0 } | Select-Object -First 1
$taskChild = if ($null -eq $taskView) { [IntPtr]::Zero } else { [IntPtr]$taskView.Current.NativeWindowHandle }
if ($taskChild -eq [IntPtr]::Zero) { throw 'The B Flutter view is missing.' }
$taskOwner = 0u
[FlyOpedWindow]::GetWindowThreadProcessId($taskChild,[ref]$taskOwner) | Out-Null
if ($taskOwner -ne $TargetProcessId) { throw 'The Flutter view belongs to another process.' }
$taskRect = New-Object FlyOpedWindow+Rect
$taskChildRect = New-Object FlyOpedWindow+Rect
[FlyOpedWindow]::GetWindowRect($taskHandle,[ref]$taskRect) | Out-Null
[FlyOpedWindow]::GetWindowRect($taskChild,[ref]$taskChildRect) | Out-Null
$taskWidth = $taskRect.Right - $taskRect.Left
$taskHeight = $taskRect.Bottom - $taskRect.Top
if ($taskWidth -lt 300 -or $taskHeight -lt 200) { throw 'The B window is not large enough for playback evidence.' }

function Invoke-TaskClick([int]$WindowX,[int]$WindowY) {
    if ($WindowX -lt 0 -or $WindowY -lt 0 -or $WindowX -ge $taskWidth -or $WindowY -ge $taskHeight) { throw 'Click is outside the captured B window.' }
    $taskLocalX = $WindowX + $taskRect.Left - $taskChildRect.Left
    $taskLocalY = $WindowY + $taskRect.Top - $taskChildRect.Top
    $taskPoint = [IntPtr](($taskLocalY -shl 16) -bor ($taskLocalX -band 65535))
    [FlyOpedWindow]::SendMessage($taskChild,512,[IntPtr]::Zero,$taskPoint) | Out-Null
    [FlyOpedWindow]::SendMessage($taskChild,513,[IntPtr]1,$taskPoint) | Out-Null
    [FlyOpedWindow]::SendMessage($taskChild,514,[IntPtr]::Zero,$taskPoint) | Out-Null
}

function Send-TaskText([string]$Value) {
    foreach ($taskCharacter in $Value.ToCharArray()) {
        [FlyOpedWindow]::SendMessage($taskChild,258,[IntPtr]([int]$taskCharacter),[IntPtr]1) | Out-Null
    }
}

switch ($Action) {
    'Click' { Invoke-TaskClick $X $Y }
    'Text' { Send-TaskText $Text }
    'Hover' {
        $taskMovePoint = [IntPtr]((($Y + $taskRect.Top - $taskChildRect.Top) -shl 16) -bor (($X + $taskRect.Left - $taskChildRect.Left) -band 65535))
        [FlyOpedWindow]::SendMessage($taskChild,512,[IntPtr]::Zero,$taskMovePoint) | Out-Null
    }
    'Key' {
        $taskCode = @{Space=32;Escape=27;Right=39;Left=37}[$Key]
        [FlyOpedWindow]::SendMessage($taskChild,256,[IntPtr]$taskCode,[IntPtr]1) | Out-Null
        [FlyOpedWindow]::SendMessage($taskChild,257,[IntPtr]$taskCode,[IntPtr](-1073741823)) | Out-Null
    }
    'Login' {
        # These coordinates were read from the fresh B profile screenshot.
        # Require its exact dimensions; use Capture/Click for other layouts.
        if ($taskWidth -ne 1600 -or $taskHeight -ne 900) { throw 'Login requires the observed fresh 1600x900 window.' }
        $taskAccess = Get-Content -LiteralPath $AccessFile -Raw | ConvertFrom-Json
        if (-not $taskAccess.username -or -not $taskAccess.password) { throw 'The local credential file has no usable account.' }
        Invoke-TaskClick 790 375
        Send-TaskText $ServiceUrl
        Invoke-TaskClick 790 460
        Send-TaskText $taskAccess.username
        Invoke-TaskClick 790 546
        Send-TaskText $taskAccess.password
        $taskAccess = $null
        Invoke-TaskClick 790 706
    }
}

if ($Action -ne 'Capture') { Start-Sleep -Milliseconds 400 }

# Capture actual window pixels. No pass/fail inference comes from image creation.
$taskBitmap = [System.Drawing.Bitmap]::new($taskWidth,$taskHeight)
$taskGraphics = [System.Drawing.Graphics]::FromImage($taskBitmap)
$taskDc = $taskGraphics.GetHdc()
try { $taskCaptured = [FlyOpedWindow]::PrintWindow($taskHandle,$taskDc,2) }
finally { $taskGraphics.ReleaseHdc($taskDc) }
$taskImagePath = Join-Path $taskProfile ($Name + '.png')
try { $taskBitmap.Save($taskImagePath) }
finally { $taskGraphics.Dispose(); $taskBitmap.Dispose() }
$taskWindow = [System.Windows.Automation.AutomationElement]::FromHandle($taskHandle)
$taskNodes = @($taskWindow.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object {
    [pscustomobject]@{ Type=$_.Current.ControlType.ProgrammaticName; Name=$(if ($_.Current.IsPassword -or $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::Edit) {'[input omitted]'} else {$_.Current.Name}); Bounds=$_.Current.BoundingRectangle.ToString() }
})
$taskResult = [pscustomobject]@{
    CapturedAt=[DateTimeOffset]::Now.ToString('o'); ProcessId=$TargetProcessId; Executable=$taskExpected;
    Action=$Action; Image=$taskImagePath; PrintWindow=$taskCaptured; Width=$taskWidth; Height=$taskHeight; Accessibility=$taskNodes
}
$taskResult | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $taskProfile ($Name + '.json')) -Encoding utf8
$taskResult | Select-Object CapturedAt,ProcessId,Action,Image,PrintWindow,Width,Height | ConvertTo-Json
