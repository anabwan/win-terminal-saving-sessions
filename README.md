# win-terminal-saving-sessions

Fixes the "I have to rebuild my whole terminal setup after every reboot" problem
for **Windows Terminal 1.24+** with **Git Bash** tabs.

## Repo layout

```
setup.ps1                                  # entry point: install or uninstall
scripts/
  Install-WinTerminalSessionRestore.ps1    # main installer (-DryRun / -Revert)
  Rollback-WinTerminalSessionRestore.ps1   # thin wrapper for Install...ps1 -Revert
README.md
```

## What this actually solves

Windows Terminal has no single "save my session" button. The reality, straight
from Microsoft's own docs:

| Thing you want back | Can Windows Terminal do it? |
|---|---|
| Same windows/tabs/panes/profiles reopened | Yes - `firstWindowPreference: persistedWindowLayout` |
| Each pane's working directory restored | Only if the shell emits an OSC 9;9 escape sequence on its prompt. Git Bash doesn't do this out of the box. |
| Command history (up-arrow) surviving a reboot | Not a Terminal feature at all - bash only writes `~/.bash_history` on a *clean* exit, and a reboot never gives it one |
| Scrollback / pane output content | **Not supported**, at all, by design. There is no workaround built into Windows Terminal itself. |

This repo fixes the first three. The fourth (scrollback) is intentionally out
of scope — recovering real pane output requires something like `tmux` (which
needs WSL to work reliably; MSYS/Git Bash support is poor) and was explicitly
descoped per discussion.

## What the script changes

Run:

```powershell
.\setup.ps1
```

It touches two files, backing each up first (`<file>.bak-<timestamp>`):

1. **Windows Terminal `settings.json`** (auto-detected for stable/Preview/
   unpackaged installs) — adds/updates:
   ```json
   "firstWindowPreference": "persistedWindowLayout"
   ```
2. **`~/.bashrc`** — appends a marked block (between
   `# >>> win-terminal-saving-sessions >>>` / `# <<< ... <<<`) that:
   - turns on `histappend` and runs `history -a; history -c; history -r` in
     `PROMPT_COMMAND`, so every command is flushed to `~/.bash_history`
     immediately instead of only at clean shell exit
   - emits the OSC 9;9 sequence (via `cygpath`) on every prompt, so Windows
     Terminal can track and later restore each pane's working directory

The script is idempotent — running it again won't duplicate the block or
re-apply an already-correct setting.

## Options

```powershell
.\setup.ps1                 # install (equivalent to -Action Install)
.\setup.ps1 -DryRun         # show what would change, write nothing
.\setup.ps1 -Action Uninstall   # restore the most recent backups it made
```

The underlying scripts in `scripts/` can still be run directly if you prefer:

```powershell
.\scripts\Install-WinTerminalSessionRestore.ps1 -DryRun
.\scripts\Install-WinTerminalSessionRestore.ps1 -Revert
.\scripts\Rollback-WinTerminalSessionRestore.ps1          # same as -Revert, as its own script
```

Use the rollback script (or `-Revert`) to undo the current install before
applying a newer version of this setup — each install run backs up whatever
was there beforehand, so rollback always steps back to the pre-install state.

## After running

- Fully close Windows Terminal (close every window, or use Quit) rather than
  leaving it running, then reopen it to verify tabs restore.
- **Any Git Bash tab that was already open before you ran the installer will
  not track its working directory**, because bash only reads `.bashrc` when a
  shell starts, not while it's running. Run `source ~/.bashrc` in each
  already-open tab once (or just close/reopen it) to activate CWD tracking
  for it. Tabs opened after the install pick this up automatically - no
  action needed.
- To test history: run a command, then kill the Windows Terminal process
  directly (simulating an unclean shutdown/reboot) and reopen - the command
  should still be in `history`/`~/.bash_history`.
