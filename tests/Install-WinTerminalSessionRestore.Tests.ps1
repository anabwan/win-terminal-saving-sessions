#Requires -Modules Pester

BeforeAll {
    $script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Install-WinTerminalSessionRestore.ps1')).Path
    . $script:ScriptPath
}

Describe 'Get-BashrcStatus' {
    It 'reports Found = $false for a missing file' {
        $tmp = Join-Path $TestDrive 'missing.bashrc'
        (Get-BashrcStatus $tmp).Found | Should -BeFalse
    }

    It 'reports Found = $false for a file with no managed block' {
        $tmp = Join-Path $TestDrive 'plain.bashrc'
        Set-Content -LiteralPath $tmp -Value 'export FOO=bar'
        (Get-BashrcStatus $tmp).Found | Should -BeFalse
    }
}

Describe 'Set-BashrcBlock idempotency' {
    It 'creates the managed block on first run and reports up to date afterwards' {
        $tmp = Join-Path $TestDrive 'first.bashrc'
        Set-BashrcBlock $tmp | Out-Null
        $status = Get-BashrcStatus $tmp
        $status.Found | Should -BeTrue
        $status.UpToDate | Should -BeTrue
        $status.BlockCount | Should -Be 1
    }

    It 'does not duplicate the block on a second run (regression: v1.0.0 -match Singleline bug)' {
        $tmp = Join-Path $TestDrive 'second.bashrc'
        Set-BashrcBlock $tmp | Out-Null
        $changed = Set-BashrcBlock $tmp
        $changed | Should -BeFalse
        (Get-BashrcStatus $tmp).BlockCount | Should -Be 1
    }

    It 'replaces an existing older/unversioned block instead of appending a duplicate' {
        $tmp = Join-Path $TestDrive 'upgrade.bashrc'
        $oldBlock = "# >>> win-terminal-saving-sessions >>>`nsome old content`n# <<< win-terminal-saving-sessions <<<"
        Set-Content -LiteralPath $tmp -Value $oldBlock
        Set-BashrcBlock $tmp | Out-Null
        $raw = Get-Content -LiteralPath $tmp -Raw
        ([regex]::Matches($raw, '# >>> win-terminal-saving-sessions')).Count | Should -Be 1
        (Get-BashrcStatus $tmp).UpToDate | Should -BeTrue
    }

    It 'preserves unrelated content in the file around the managed block' {
        $tmp = Join-Path $TestDrive 'preserve.bashrc'
        Set-Content -LiteralPath $tmp -Value "export MY_CUSTOM=1"
        Set-BashrcBlock $tmp | Out-Null
        (Get-Content -LiteralPath $tmp -Raw) | Should -Match 'export MY_CUSTOM=1'
    }
}

Describe 'Get-BashrcStatus corruption detection' {
    It 'reports BlockCount > 1 when the managed block is duplicated (regression safeguard)' {
        $tmp = Join-Path $TestDrive 'corrupted.bashrc'
        Set-BashrcBlock $tmp | Out-Null
        $content = Get-Content -LiteralPath $tmp -Raw
        Add-Content -LiteralPath $tmp -Value $content -NoNewline
        (Get-BashrcStatus $tmp).BlockCount | Should -BeGreaterThan 1
    }
}

Describe 'Get-BashrcStatus line-ending tolerance (regression: CRLF/LF checkout mismatch)' {
    It 'reports up to date for a block written with LF-only line endings' {
        $tmp = Join-Path $TestDrive 'lf.bashrc'
        Set-BashrcBlock $tmp | Out-Null
        $raw = [System.IO.File]::ReadAllText($tmp)
        [System.IO.File]::WriteAllText($tmp, ($raw -replace "`r`n", "`n"))
        (Get-BashrcStatus $tmp).UpToDate | Should -BeTrue
    }

    It 'reports up to date for a block written with CRLF-only line endings' {
        $tmp = Join-Path $TestDrive 'crlf.bashrc'
        Set-BashrcBlock $tmp | Out-Null
        $raw = [System.IO.File]::ReadAllText($tmp)
        $lf = $raw -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText($tmp, ($lf -replace "`n", "`r`n"))
        (Get-BashrcStatus $tmp).UpToDate | Should -BeTrue
    }
}

Describe 'Set-PersistedWindowLayout / Get-SettingsStatus' {
    It 'adds the setting to a fresh settings.json and marks it applied' {
        $tmp = Join-Path $TestDrive 'settings.json'
        Set-Content -LiteralPath $tmp -Value '{"foo": "bar"}'
        Set-PersistedWindowLayout $tmp | Out-Null
        Get-SettingsStatus $tmp | Should -BeTrue
    }

    It 'is idempotent on a second run' {
        $tmp = Join-Path $TestDrive 'settings2.json'
        Set-Content -LiteralPath $tmp -Value '{"foo": "bar"}'
        Set-PersistedWindowLayout $tmp | Out-Null
        Set-PersistedWindowLayout $tmp | Should -BeFalse
    }

    It 'replaces a pre-existing different firstWindowPreference value' {
        $tmp = Join-Path $TestDrive 'settings3.json'
        Set-Content -LiteralPath $tmp -Value '{"firstWindowPreference": "defaultProfile"}'
        Set-PersistedWindowLayout $tmp | Out-Null
        Get-SettingsStatus $tmp | Should -BeTrue
    }
}
