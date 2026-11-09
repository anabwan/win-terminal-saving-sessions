<#
.SYNOPSIS
    Entry point for installing or uninstalling win-terminal-saving-sessions.

.PARAMETER Action
    'Install' (default) applies the Windows Terminal + Git Bash changes.
    'Uninstall' restores the most recent pre-install backups (same as -Revert).
    'Status' reports current install state and version, writes nothing.

.PARAMETER DryRun
    Passed through to the installer: shows what would change without writing anything.
    Ignored for Uninstall/Status.

.PARAMETER Version
    Prints the tool version and exits.

.PARAMETER Help
    Prints usage and exits.

.EXAMPLE
    .\setup.ps1
.EXAMPLE
    .\setup.ps1 -Action Uninstall
.EXAMPLE
    .\setup.ps1 -Action Status
.EXAMPLE
    .\setup.ps1 -DryRun
.EXAMPLE
    .\setup.ps1 -Version
#>
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Uninstall', 'Status')]
    [string]$Action = 'Install',

    [switch]$DryRun,
    [switch]$Version,
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$installer = Join-Path $scriptDir 'scripts\Install-WinTerminalSessionRestore.ps1'

if ($Help) {
    & $installer -Help
    return
}

if ($Version) {
    & $installer -Version
    return
}

switch ($Action) {
    'Uninstall' { & $installer -Revert }
    'Status' { & $installer -Status }
    default { & $installer -DryRun:$DryRun }
}

