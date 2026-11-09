<#
.SYNOPSIS
    Configures Windows Terminal + Git Bash so tabs/panes, working directories,
    and command history survive a PC restart.

.DESCRIPTION
    Makes two changes, each backed up before being touched:

    1. Windows Terminal settings.json: sets
         "firstWindowPreference": "persistedWindowLayout"
       so Windows Terminal reopens the same windows/tabs/panes (and profile
       per pane) after a restart or crash.

    2. Git Bash ~/.bashrc: adds a managed block that
         - flushes bash history to disk after every command (instead of only
           on a clean shell exit, which a reboot never gives you), and
         - emits the OSC 9;9 escape sequence on every prompt so Windows
           Terminal knows each pane's current working directory and can
           restore it as part of the persisted layout.

    NOTE: Windows Terminal does not support restoring pane scrollback/output
    content. This script does not attempt to work around that.

.PARAMETER Revert
    Restores the most recent backup of settings.json and .bashrc instead of
    applying changes.

.PARAMETER DryRun
    Shows what would change without writing anything.

.PARAMETER Status
    Reports whether each change is currently applied, and which installed
    version (if any) the .bashrc block is at, without writing anything.

.PARAMETER Version
    Prints the tool version and exits.

.PARAMETER Help
    Prints usage and exits.
#>
[CmdletBinding()]
param(
    [switch]$Revert,
    [switch]$DryRun,
    [switch]$Status,
    [switch]$Version,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ToolVersion = (Get-Content -LiteralPath (Join-Path $RepoRoot 'VERSION') -Raw).Trim()

if ($Help) {
    Write-Host @"
win-terminal-saving-sessions v$ToolVersion

Usage: Install-WinTerminalSessionRestore.ps1 [-DryRun] [-Revert] [-Status] [-Version] [-Help]

  (no flags)  Apply the Windows Terminal + Git Bash changes.
  -DryRun     Show what would change without writing anything.
  -Revert     Restore the most recent backups (undo install).
  -Status     Report current install state and version, write nothing.
  -Version    Print the tool version.
  -Help       Print this message.
"@
    return
}

if ($Version) {
    Write-Host "win-terminal-saving-sessions v$ToolVersion"
    return
}

function Write-Section($text) {
    Write-Host ""
    Write-Host "== $text ==" -ForegroundColor Cyan
}

function Get-WindowsTerminalSettingsPaths {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    $candidates | Where-Object { Test-Path -LiteralPath $_ }
}

function Backup-File($path) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$path.bak-$stamp"
    Copy-Item -LiteralPath $path -Destination $backupPath -Force
    return $backupPath
}

function Restore-LatestBackup($path) {
    $dir = Split-Path -Parent $path
    $name = Split-Path -Leaf $path
    $backup = Get-ChildItem -LiteralPath $dir -Filter "$name.bak-*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $backup) {
        Write-Host "  No backup found for $path, skipping." -ForegroundColor Yellow
        return
    }
    Copy-Item -LiteralPath $backup.FullName -Destination $path -Force
    Write-Host "  Restored $path from $($backup.Name)" -ForegroundColor Green
}

function Set-PersistedWindowLayout($path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $encoding = New-Object System.Text.UTF8Encoding($hasBom)
    $raw = [System.IO.File]::ReadAllText($path)

    $pattern = '"firstWindowPreference"\s*:\s*"[^"]*"'
    $desired = '"firstWindowPreference": "persistedWindowLayout"'

    if ($raw -match $pattern) {
        if ($Matches[0] -eq $desired) {
            Write-Host "  Already set: $path" -ForegroundColor DarkGray
            return $false
        }
        $newRaw = [regex]::Replace($raw, $pattern, { param($m) $desired })
    }
    else {
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.AddRange([string[]]($raw -split "`r?`n"))
        $insertAt = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $t = $lines[$i].Trim()
            if ($t.StartsWith('{') -and -not $t.StartsWith('//')) {
                $insertAt = $i
                break
            }
        }
        if ($insertAt -lt 0) {
            throw "Could not find the opening '{' in $path to insert the setting."
        }
        $lines.Insert($insertAt + 1, "    $desired,")
        $newRaw = [string]::Join("`r`n", $lines)
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would update: $path" -ForegroundColor Yellow
        return $true
    }

    $backupPath = Backup-File $path
    [System.IO.File]::WriteAllText($path, $newRaw, $encoding)
    Write-Host "  Updated: $path (backup: $(Split-Path -Leaf $backupPath))" -ForegroundColor Green
    return $true
}

# Matches both the current versioned marker and the original unversioned one,
# so upgrades from any prior install are detected and replaced.
$BashrcBeginPattern = '# >>> win-terminal-saving-sessions(?: v[0-9][0-9.]*)? >>>'
$BashrcBlockBegin = "# >>> win-terminal-saving-sessions v$ToolVersion >>>"
$BashrcBlockEnd = '# <<< win-terminal-saving-sessions <<<'
$BashrcBlockBody = @'
# Managed by win-terminal-saving-sessions. Safe to delete this block to revert.

# Flush bash history to disk after every command instead of only on a clean
# shell exit, so history survives an unclean shutdown/reboot.
shopt -s histappend
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTCONTROL=ignoreboth:erasedups
PROMPT_COMMAND=${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'history -a; history -c; history -r'

# PROMPT_COMMAND only runs once a command finishes and bash shows its next
# prompt. If a command takes over the terminal and never returns control
# (ssh, vim, tmux, etc.) before the terminal is killed, that command is never
# flushed. This trap flushes immediately when the command is entered instead.
trap 'history -a' DEBUG

# Report the current working directory to Windows Terminal (OSC 9;9) so this
# pane's CWD is restored when using "firstWindowPreference": "persistedWindowLayout".
PROMPT_COMMAND=${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'printf "\e]9;9;%s\e\\" "`cygpath -w "$PWD" -C ANSI`"'
'@
# Normalize to LF: the here-string above picks up whatever line endings this
# .ps1 file was checked out with (CRLF from a normal git clone, LF from a
# GitHub zip/Scoop install), which must not affect the block we write/compare.
$BashrcBlockBody = $BashrcBlockBody -replace "`r`n", "`n"

function Set-BashrcBlock($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        if ($DryRun) {
            Write-Host "  [DryRun] Would create: $path" -ForegroundColor Yellow
            return $true
        }
        New-Item -ItemType File -Path $path -Force | Out-Null
    }

    $raw = [System.IO.File]::ReadAllText($path)
    $blockPattern = $BashrcBeginPattern + '.*?' + [regex]::Escape($BashrcBlockEnd)
    $newBlock = "$BashrcBlockBegin`n$BashrcBlockBody`n$BashrcBlockEnd"

    $existingMatch = [regex]::Match($raw, $blockPattern, 'Singleline')
    if ($existingMatch.Success) {
        if (($existingMatch.Value -replace "`r`n", "`n") -eq $newBlock) {
            Write-Host "  Already configured: $path" -ForegroundColor DarkGray
            return $false
        }
        $newRaw = [regex]::Replace($raw, $blockPattern, { param($m) $newBlock }, 'Singleline')
    }
    else {
        $separator = if ($raw.Length -gt 0 -and -not $raw.EndsWith("`n")) { "`n`n" } else { "`n" }
        $newRaw = "$raw$separator$newBlock`n"
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would update: $path" -ForegroundColor Yellow
        return $true
    }

    if (Test-Path -LiteralPath $path) {
        Backup-File $path | Out-Null
    }
    $noBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $newRaw, $noBom)
    Write-Host "  Updated: $path" -ForegroundColor Green
    return $true
}

function Get-BashrcStatus($path) {
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{ Found = $false; InstalledVersion = $null; UpToDate = $false }
    }
    $raw = [System.IO.File]::ReadAllText($path)
    $beginMatch = [regex]::Match($raw, $BashrcBeginPattern)
    if (-not $beginMatch.Success) {
        return [pscustomobject]@{ Found = $false; InstalledVersion = $null; UpToDate = $false }
    }
    $verMatch = [regex]::Match($beginMatch.Value, 'v([0-9][0-9.]*)')
    $installedVersion = if ($verMatch.Success) { $verMatch.Groups[1].Value } else { 'pre-1.0.0 (unversioned)' }

    $blockPattern = $BashrcBeginPattern + '.*?' + [regex]::Escape($BashrcBlockEnd)
    $blockMatch = [regex]::Match($raw, $blockPattern, 'Singleline')
    $newBlock = "$BashrcBlockBegin`n$BashrcBlockBody`n$BashrcBlockEnd"
    $upToDate = $blockMatch.Success -and (($blockMatch.Value -replace "`r`n", "`n") -eq $newBlock)

    return [pscustomobject]@{ Found = $true; InstalledVersion = $installedVersion; UpToDate = $upToDate }
}

function Get-SettingsStatus($path) {
    $raw = [System.IO.File]::ReadAllText($path)
    $pattern = '"firstWindowPreference"\s*:\s*"[^"]*"'
    $desired = '"firstWindowPreference": "persistedWindowLayout"'
    return ($raw -match $pattern) -and ($Matches[0] -eq $desired)
}

# ---------------------------------------------------------------------------

$settingsPaths = @(Get-WindowsTerminalSettingsPaths)
$bashrcPath = Join-Path $env:USERPROFILE '.bashrc'

if ($Status) {
    Write-Section "win-terminal-saving-sessions status (tool v$ToolVersion)"

    if ($settingsPaths.Count -eq 0) {
        Write-Host '  settings.json: not found. Is Windows Terminal installed?' -ForegroundColor Yellow
    }
    foreach ($p in $settingsPaths) {
        if (Get-SettingsStatus $p) {
            Write-Host "  settings.json: applied ($p)" -ForegroundColor Green
        }
        else {
            Write-Host "  settings.json: NOT applied ($p)" -ForegroundColor Yellow
        }
    }

    $bashrcStatus = Get-BashrcStatus $bashrcPath
    if (-not $bashrcStatus.Found) {
        Write-Host "  .bashrc: not installed ($bashrcPath)" -ForegroundColor Yellow
    }
    elseif ($bashrcStatus.InstalledVersion -eq $ToolVersion -and $bashrcStatus.UpToDate) {
        Write-Host "  .bashrc: installed, v$($bashrcStatus.InstalledVersion) (up to date)" -ForegroundColor Green
    }
    else {
        Write-Host "  .bashrc: installed, v$($bashrcStatus.InstalledVersion) (outdated - latest is v$ToolVersion, run install to update)" -ForegroundColor Yellow
    }
    return
}

if ($Revert) {
    Write-Section 'Reverting Windows Terminal settings.json'
    if ($settingsPaths.Count -eq 0) {
        Write-Host '  No settings.json found.' -ForegroundColor Yellow
    }
    foreach ($p in $settingsPaths) { Restore-LatestBackup $p }

    Write-Section 'Reverting .bashrc'
    Restore-LatestBackup $bashrcPath

    Write-Host "`nDone. Restart Windows Terminal and open a new Git Bash tab for changes to take effect." -ForegroundColor Cyan
    return
}

Write-Section 'Windows Terminal: persisted window layout'
if ($settingsPaths.Count -eq 0) {
    Write-Host '  No settings.json found. Is Windows Terminal installed?' -ForegroundColor Yellow
}
foreach ($p in $settingsPaths) {
    Write-Host "  Found: $p"
    Set-PersistedWindowLayout $p | Out-Null
}

Write-Section 'Git Bash: ~/.bashrc history + CWD reporting'
Write-Host "  Target: $bashrcPath"
Set-BashrcBlock $bashrcPath | Out-Null

Write-Section 'Done'
Write-Host 'Restart Windows Terminal fully (not just close the window - use the X on every window or Quit) for the settings.json change to apply.' -ForegroundColor Cyan
Write-Host "IMPORTANT: bash only reads .bashrc when a shell STARTS. Any Git Bash tab that was already open before running this script won't track its working directory until you run ``source ~/.bashrc`` in it (or close and reopen that tab). New tabs opened from now on pick it up automatically." -ForegroundColor Yellow
Write-Host "Run with -Revert to restore the previous settings.json/.bashrc from the backups this script made." -ForegroundColor DarkGray
Write-Host "Note: Windows Terminal cannot restore pane scrollback/output content - only tabs, panes, profiles and (now) working directories." -ForegroundColor DarkGray
