# ADR-005 dispatch watcher.
#
# Scans D:\Source\*\.exec\status.md every invocation (intended to run via
# Windows Scheduled Task every 5 minutes). For each dispatch whose status
# is `running` and whose `current_phase` is `CONTEXT_CYCLE_REQUESTED`,
# re-invokes `claude -p` in Dispatch Mode to resume the sprint.
#
# Safety:
#   - Hard cap of $MaxAttempts relaunches per directive_id (default 5)
#   - Idempotence window: skip if the last .exec/history.md line is a
#     watcher relaunch younger than $IdempotenceWindowMinutes (default 2)
#
# Logs to $env:LOCALAPPDATA\ClaudeDispatchWatcher\watcher.log.
#
# Run directly for debugging:
#   pwsh -File scripts/dispatch-watcher.ps1 -DryRun -VerboseLog

param(
    [string]$SourceRoot = "",
    [int]$MaxAttempts = 5,
    [int]$IdempotenceWindowMinutes = 2,
    [switch]$DryRun,
    [switch]$VerboseLog
)

# Resolve SourceRoot: default to parent of this script's repo
if (-not $SourceRoot) {
    $SourceRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$ErrorActionPreference = "Stop"

$logDir = Join-Path $env:LOCALAPPDATA "ClaudeDispatchWatcher"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "watcher.log"

function Write-WatcherLog {
    param([string]$Level, [string]$Message)
    $ts = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $line = "$ts [$Level] $Message"
    Add-Content -Path $logFile -Value $line
    if ($VerboseLog -or $Level -ne "DEBUG") { Write-Host $line }
}

function Get-FrontmatterValue {
    param([string]$Content, [string]$Key)
    $pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(\S+)"
    $m = [regex]::Match($Content, $pattern)
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}

function Get-UtcNowIso {
    return [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
}

function Get-AttemptCount {
    param([string]$AttemptsPath, [string]$DirectiveId)
    if (-not (Test-Path $AttemptsPath)) { return 0 }
    $escaped = [regex]::Escape($DirectiveId)
    foreach ($line in Get-Content $AttemptsPath) {
        if ($line -match "^${escaped}:\s*(\d+)") {
            return [int]$Matches[1]
        }
    }
    return 0
}

function Set-AttemptCount {
    param([string]$AttemptsPath, [string]$DirectiveId, [int]$Count)
    $escaped = [regex]::Escape($DirectiveId)
    $lines = @()
    if (Test-Path $AttemptsPath) {
        $lines = Get-Content $AttemptsPath | Where-Object { $_ -notmatch "^${escaped}:" }
    }
    $lines += "${DirectiveId}: $Count"
    Set-Content -Path $AttemptsPath -Value $lines -Encoding UTF8
}

function Test-RecentRelaunch {
    param([string]$HistoryPath, [int]$WindowMinutes)
    if (-not (Test-Path $HistoryPath)) { return $false }
    $lastLine = Get-Content $HistoryPath | Where-Object { $_ -match "watcher relaunch" } | Select-Object -Last 1
    if (-not $lastLine) { return $false }
    if ($lastLine -match "^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z)") {
        try {
            $ts = [DateTime]::Parse($Matches[1]).ToUniversalTime()
            $ageMin = ([DateTime]::UtcNow - $ts).TotalMinutes
            return ($ageMin -lt $WindowMinutes)
        } catch { return $false }
    }
    return $false
}

function Invoke-DispatchResume {
    param(
        [string]$RepoDir,
        [string]$RepoName,
        [string]$DirectiveId,
        [int]$AttemptN,
        [string]$ClaudePath
    )

    $prompt = "DISPATCH MODE RESUME: A prior session exited at CONTEXT_CYCLE_REQUESTED. " +
              "Read .exec/directive.md, then .sprint-continuation.md (if present), then " +
              ".exec/sprint-specs-*.md (if present). If .sprint-tool-count exists, reset " +
              "it to 0 as your first file write. Resume execution per the sprint-master " +
              "Dispatch Mode protocol in .claude/agents/sprint-master.md. Write status to " +
              ".exec/status.md at each phase transition. Exit cleanly on completion or blocker."

    if ($DryRun) {
        Write-WatcherLog "INFO" "[$RepoName] DRY RUN -- would relaunch directive $DirectiveId (attempt $AttemptN/$MaxAttempts)"
        return
    }

    $argList = @(
        "-p", $prompt,
        "--agent", "sprint-master",
        "--permission-mode", "bypassPermissions"
    )

    try {
        Start-Process -FilePath $ClaudePath `
            -ArgumentList $argList `
            -WorkingDirectory $RepoDir `
            -WindowStyle Hidden | Out-Null
        Write-WatcherLog "INFO" "[$RepoName] Relaunched directive $DirectiveId (attempt $AttemptN/$MaxAttempts)"
    } catch {
        Write-WatcherLog "ERROR" "[$RepoName] Start-Process failed: $_"
        throw
    }
}

function Set-StatusBlocked {
    param([string]$StatusPath, [string]$Content, [string]$Reason)
    $now = Get-UtcNowIso
    $new = $Content -replace "(?m)^status:\s*running", "status: blocked"
    $new = $new -replace "(?m)^last_updated:\s*\S+", "last_updated: $now"
    if ($new -notmatch "(?m)^blocked_reason:") {
        $new = $new -replace "(?m)^(heartbeat_ttl_minutes:.*)$", "`$1`nblocked_reason: $Reason"
    }
    Set-Content -Path $StatusPath -Value $new -Encoding UTF8 -NoNewline
}

# --- main ---

Write-WatcherLog "DEBUG" "Scan start (SourceRoot=$SourceRoot, DryRun=$DryRun)"

$claudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claudeCmd) {
    Write-WatcherLog "ERROR" "claude not found in PATH -- cannot relaunch"
    exit 1
}
$claudePath = $claudeCmd.Source

if (-not (Test-Path $SourceRoot)) {
    Write-WatcherLog "ERROR" "SourceRoot not found: $SourceRoot"
    exit 1
}

$repos = Get-ChildItem -Path $SourceRoot -Directory -ErrorAction SilentlyContinue
$scanned = 0
$cycled = 0
$relaunched = 0
$capped = 0
$skipped = 0

foreach ($repo in $repos) {
    $statusPath = Join-Path $repo.FullName ".exec\status.md"
    if (-not (Test-Path $statusPath)) { continue }
    $scanned++

    try {
        $content = Get-Content -Path $statusPath -Raw -Encoding UTF8
    } catch {
        Write-WatcherLog "WARN" "[$($repo.Name)] Could not read status.md: $_"
        continue
    }

    $status = Get-FrontmatterValue $content "status"
    $phase = Get-FrontmatterValue $content "current_phase"
    $directiveId = Get-FrontmatterValue $content "directive_id"

    if ($status -ne "running" -or $phase -ne "CONTEXT_CYCLE_REQUESTED") {
        Write-WatcherLog "DEBUG" "[$($repo.Name)] Skip (status=$status phase=$phase)"
        continue
    }
    if (-not $directiveId) {
        Write-WatcherLog "WARN" "[$($repo.Name)] status says cycle requested but no directive_id -- skipping"
        continue
    }

    $cycled++
    $historyPath = Join-Path $repo.FullName ".exec\history.md"
    $attemptsPath = Join-Path $repo.FullName ".exec\watcher-attempts"

    if (Test-RecentRelaunch -HistoryPath $historyPath -WindowMinutes $IdempotenceWindowMinutes) {
        Write-WatcherLog "INFO" "[$($repo.Name)] Skip -- recent watcher relaunch within $IdempotenceWindowMinutes min"
        $skipped++
        continue
    }

    $attempts = Get-AttemptCount -AttemptsPath $attemptsPath -DirectiveId $directiveId

    if ($attempts -ge $MaxAttempts) {
        if ($content -notmatch "watcher relaunch cap reached") {
            Write-WatcherLog "WARN" "[$($repo.Name)] Cap reached -- marking directive $directiveId blocked"
            $reason = "watcher relaunch cap reached ($MaxAttempts attempts on directive $directiveId)"
            if (-not $DryRun) {
                Set-StatusBlocked -StatusPath $statusPath -Content $content -Reason $reason
                Add-Content -Path $historyPath -Value "$(Get-UtcNowIso) -- watcher: cap reached for directive $directiveId (blocked)"
            }
        }
        $capped++
        continue
    }

    $newAttempts = $attempts + 1
    try {
        Invoke-DispatchResume -RepoDir $repo.FullName -RepoName $repo.Name -DirectiveId $directiveId -AttemptN $newAttempts -ClaudePath $claudePath
        if (-not $DryRun) {
            Set-AttemptCount -AttemptsPath $attemptsPath -DirectiveId $directiveId -Count $newAttempts
            Add-Content -Path $historyPath -Value "$(Get-UtcNowIso) -- watcher relaunch (directive $directiveId, attempt $newAttempts)"
        }
        $relaunched++
    } catch {
        Write-WatcherLog "ERROR" "[$($repo.Name)] Relaunch failed: $_"
    }
}

Write-WatcherLog "DEBUG" "Scan complete: scanned=$scanned cycled=$cycled relaunched=$relaunched capped=$capped skipped=$skipped"
