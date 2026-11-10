# win-terminal-saving-sessions

[![Latest release](https://img.shields.io/github/v/release/anabwan/win-terminal-saving-sessions)](https://github.com/anabwan/win-terminal-saving-sessions/releases)
[![CI](https://github.com/anabwan/win-terminal-saving-sessions/actions/workflows/ci.yml/badge.svg)](https://github.com/anabwan/win-terminal-saving-sessions/actions/workflows/ci.yml)
[![Scoop bucket](https://img.shields.io/badge/scoop-bucket-blue)](https://github.com/anabwan/win-terminal-saving-sessions#via-scoop-recommended-for-powershell-users)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Fixes the "I have to rebuild my whole terminal setup after every reboot" problem
for **Windows Terminal 1.24+** with **Git Bash** tabs.

## Repo layout

Two equivalent implementations are provided - use whichever shell you prefer
to run it from. Both touch the same two files in the same way.

```
setup.ps1                                     # PowerShell entry point: install or uninstall
setup.sh                                      # Bash entry point: install or uninstall
VERSION                                       # single source of truth for the tool version
bucket/
  win-terminal-saving-sessions.json           # Scoop bucket manifest (this repo is its own bucket)
scripts/
  Install-WinTerminalSessionRestore.ps1       # PowerShell installer (-DryRun / -Revert / -Status / -Version / -Help)
  Rollback-WinTerminalSessionRestore.ps1      # PowerShell: thin wrapper for Install...ps1 -Revert
  install-win-terminal-session-restore.sh     # Bash installer (--dry-run / --revert / --status / --version / --help)
  rollback-win-terminal-session-restore.sh    # Bash: thin wrapper for install...sh --revert
tests/
  Install-WinTerminalSessionRestore.Tests.ps1 # Pester regression tests (PowerShell)
  run-bash-tests.sh                           # Dependency-free regression tests (bash)
.github/workflows/ci.yml                      # Runs the tests above on every push/PR
LICENSE                                       # MIT
CHANGELOG.md
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

## Installing

### Via Scoop (recommended for PowerShell users)

This repo doubles as its own [Scoop](https://scoop.sh) bucket:

```powershell
scoop bucket add win-terminal-saving-sessions https://github.com/anabwan/win-terminal-saving-sessions
scoop install win-terminal-saving-sessions
```

This puts `win-terminal-saving-sessions` on your `PATH` (it's `setup.ps1`, so
all the flags below work the same way). Nothing is applied automatically at
install time — run it yourself:

```powershell
win-terminal-saving-sessions                # install
win-terminal-saving-sessions -Action Status # check install state/version
```

`scoop update win-terminal-saving-sessions` picks up new tagged releases.

### Manual (PowerShell or Git Bash)

Clone or download the repo (a [Release](https://github.com/anabwan/win-terminal-saving-sessions/releases)
zip works too), then from the repo root:

```powershell
.\setup.ps1
```

```bash
./setup.sh
```

If PowerShell refuses to run `setup.ps1` because it was downloaded as a zip
(Windows marks it "blocked"), run `Unblock-File .\setup.ps1` first, or launch
it with `powershell -ExecutionPolicy Bypass -File .\setup.ps1`.

## What the script changes

Run, from PowerShell:

```powershell
.\setup.ps1
```

or, from Git Bash:

```bash
./setup.sh
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

PowerShell:

```powershell
.\setup.ps1                     # install (equivalent to -Action Install)
.\setup.ps1 -DryRun             # show what would change, write nothing
.\setup.ps1 -Action Uninstall   # restore the most recent backups it made
.\setup.ps1 -Action Status      # check whether it's installed, and which version
.\setup.ps1 -Version            # print the installed tool's version
.\setup.ps1 -Help               # print usage
```

Bash:

```bash
./setup.sh                      # install (equivalent to --action install)
./setup.sh --dry-run            # show what would change, write nothing
./setup.sh --action uninstall   # restore the most recent backups it made
./setup.sh --action status      # check whether it's installed, and which version
./setup.sh --version            # print the installed tool's version
./setup.sh --help               # print usage
```

Sample `-Action Status` / `--action status` output:

```
== win-terminal-saving-sessions status (tool v1.0.0) ==
  settings.json: applied (C:\Users\you\...\settings.json)
  .bashrc: installed, v1.0.0 (up to date)
```

If a newer version of this repo is pulled (`VERSION` bumped) and `.bashrc` was
installed by an older one, status reports it as outdated and tells you to
re-run the installer - which then updates the managed block to the new
version's content automatically (same idempotent replace logic used today).

The underlying scripts in `scripts/` can still be run directly if you prefer:

```powershell
.\scripts\Install-WinTerminalSessionRestore.ps1 -DryRun
.\scripts\Install-WinTerminalSessionRestore.ps1 -Revert
.\scripts\Rollback-WinTerminalSessionRestore.ps1          # same as -Revert, as its own script
```

```bash
./scripts/install-win-terminal-session-restore.sh --dry-run
./scripts/install-win-terminal-session-restore.sh --revert
./scripts/rollback-win-terminal-session-restore.sh          # same as --revert, as its own script
```

Use the rollback script (or `-Revert`/`--revert`) to undo the current install
before applying a newer version of this setup — each install run backs up
whatever was there beforehand, so rollback always steps back to the
pre-install state.

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

## Releasing a new version

1. Bump the version in `VERSION` (single line, e.g. `1.0.2`).
2. Commit the change (plus whatever fix/feature triggered it).
3. Tag and push:
   ```powershell
   git tag -a v1.0.2 -m "v1.0.2: <summary>"
   git push origin main
   git push origin v1.0.2
   ```
4. Update the Scoop manifest ([bucket/win-terminal-saving-sessions.json](bucket/win-terminal-saving-sessions.json))
   to point at the new tag and hash:
   ```powershell
   Invoke-WebRequest -Uri "https://github.com/anabwan/win-terminal-saving-sessions/archive/refs/tags/v1.0.2.zip" -OutFile wtss.zip
   (Get-FileHash wtss.zip -Algorithm SHA256).Hash
   ```
   Put that hash, the new `version`, `url` and `extract_dir` into the manifest,
   then commit and push.
5. Optionally draft a GitHub Release from the new tag with release notes.
6. Scoop users pick it up via `scoop update; scoop update win-terminal-saving-sessions`.

`--status`/`-Action Status` on an older install will report it as outdated
once `VERSION` is ahead of what's in `.bashrc`, and tells the user to re-run
the installer.

