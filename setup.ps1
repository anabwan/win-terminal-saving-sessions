<#
.SYNOPSIS
    Entry point for installing or uninstalling win-terminal-saving-sessions.

.PARAMETER Action
    'Install' (default) applies the Windows Terminal + Git Bash changes.
    'Uninstall' restores the most recent pre-install backups (same as -Revert).

.PARAMETER DryRun
    Passed through to the installer: shows what would change without writing anything.
    Ignored for Uninstall.

.EXAMPLE
    .\setup.ps1
.EXAMPLE
    .\setup.ps1 -Action Uninstall
.EXAMPLE
    .\setup.ps1 -DryRun
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall')]
    [string]$Action = 'Install',

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $scriptDir 'scripts\Install-WinTerminalSessionRestore.ps1'

if ($Action -eq 'Uninstall') {
    & $installer -Revert
}
else {
    & $installer -DryRun:$DryRun
}
