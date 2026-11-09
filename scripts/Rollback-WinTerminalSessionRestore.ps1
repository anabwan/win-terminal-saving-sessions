<#
.SYNOPSIS
    Rolls back changes made by Install-WinTerminalSessionRestore.ps1.

.DESCRIPTION
    Restores Windows Terminal's settings.json and ~/.bashrc from the most
    recent backup file created by the installer (<file>.bak-<timestamp>).
    Use this before installing a newer version of the setup, or to undo it
    entirely.

    This is a thin wrapper around:
        Install-WinTerminalSessionRestore.ps1 -Revert
#>
[CmdletBinding()]
param()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptDir 'Install-WinTerminalSessionRestore.ps1') -Revert
