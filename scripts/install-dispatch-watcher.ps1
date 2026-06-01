# ADR-005 installer.
#
# Registers a Windows Scheduled Task that runs dispatch-watcher.ps1 every
# 5 minutes while the user is logged on. Re-registering is safe: any
# previous task with the same name is removed first.
#
# Requires elevation to register the task in the root task folder.
#
# Uninstall:
#   Unregister-ScheduledTask -TaskName ClaudeDispatchWatcher -Confirm:$false

#Requires -RunAsAdministrator

param(
    [string]$TaskName = "ClaudeDispatchWatcher",
    [int]$IntervalMinutes = 5
)

$ErrorActionPreference = "Stop"

$watcherPath = Join-Path $PSScriptRoot "dispatch-watcher.ps1"
$vbsPath = Join-Path $PSScriptRoot "dispatch-watcher-hidden.vbs"
if (-not (Test-Path $watcherPath)) {
    throw "dispatch-watcher.ps1 not found at $watcherPath"
}
if (-not (Test-Path $vbsPath)) {
    throw "dispatch-watcher-hidden.vbs not found at $vbsPath"
}

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-Warning "claude not found in PATH for the current user. The scheduled task will inherit this PATH; the watcher will fail until claude resolves."
}

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing task '$TaskName'..."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Headless invocation chain: Task Scheduler -> wscript.exe (no console) ->
# VBS wrapper -> powershell.exe with SW_HIDE. Fully headless under
# LogonType Interactive; no window flash, no focus steal.
$action = New-ScheduledTaskAction `
    -Execute "wscript.exe" `
    -Argument "//nologo `"$vbsPath`""

$trigger = New-ScheduledTaskTrigger `
    -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 4) `
    -MultipleInstances IgnoreNew

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Limited

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal `
    -Description "ADR-005 dispatch watcher: re-invokes Claude dispatches stalled at CONTEXT_CYCLE_REQUESTED. Source: highest-level-project-management/scripts/dispatch-watcher.ps1" | Out-Null

Write-Host "Registered scheduled task '$TaskName' (every $IntervalMinutes minutes)."
Write-Host ""
Write-Host "Inspect:    schtasks /query /tn $TaskName /v /fo list"
Write-Host "Run once:   Start-ScheduledTask -TaskName $TaskName"
Write-Host "Logs:       $env:LOCALAPPDATA\ClaudeDispatchWatcher\watcher.log"
Write-Host "Uninstall:  Unregister-ScheduledTask -TaskName $TaskName -Confirm:`$false"
