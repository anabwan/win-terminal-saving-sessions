# Changelog

All notable changes to this project are documented here. Versions correspond
to git tags and the `VERSION` file.

## v1.0.3

- Added `LICENSE` (MIT) - the Scoop manifest already declared this license,
  but no license text existed in the repo.
- Added `.gitattributes` rule forcing `*.ps1 text eol=crlf` as defense in
  depth against the CRLF/LF mismatch bug class fixed in v1.0.1.
- Added `CHANGELOG.md`.
- Added README badges (latest release, CI status, Scoop bucket, license).
- Refactored both installer scripts to be testable: `Install-WinTerminalSessionRestore.ps1`
  can be dot-sourced to expose its functions without running the installer,
  and `install-win-terminal-session-restore.sh`'s dispatch logic now lives in
  a `main()` guarded by a `BASH_SOURCE` check, so it can be sourced the same way.
- Added a Pester regression suite (`tests/Install-WinTerminalSessionRestore.Tests.ps1`)
  and a dependency-free bash test harness (`tests/run-bash-tests.sh`) covering
  idempotency, corruption detection, CRLF/LF tolerance, and settings.json handling.
- Added a GitHub Actions CI workflow that validates the Scoop manifest JSON,
  syntax-checks both bash scripts, smoke-tests `--help`/`--version`/`--dry-run`
  on both implementations, and runs the regression suites above on every push/PR.

## v1.0.2

- `--status` / `-Action Status` now counts occurrences of the `.bashrc`
  managed-block marker and reports `CORRUPTED - N managed blocks found`
  instead of silently using the first match, as a tripwire against the
  duplicate-block bug class fixed in v1.0.0.

## v1.0.1

- Fixed a false "outdated" status: the `.bashrc` managed-block comparison
  could report a correctly-installed, correctly-versioned block as outdated
  because a normal `git clone` checks out `Install-WinTerminalSessionRestore.ps1`
  with CRLF line endings while GitHub's release zip (what Scoop downloads)
  keeps LF, producing different literal bytes for the same generated block.
  Both sides are now normalized before comparing.

## v1.0.0

- Initial versioned release.
- `VERSION` file as the single source of truth for the tool version,
  embedded into the `.bashrc` managed block's begin marker.
- Added `-Status`/`-Version`/`-Help` (PowerShell) and
  `--status`/`--version`/`--help` (bash) to both installer scripts and the
  `setup.ps1`/`setup.sh` wrappers.
- Fixed a bug where the PowerShell installer's `-match` operator never
  applied the `Singleline` regex option, so the existing `.bashrc` managed
  block was never detected and every install run appended a new duplicate
  block instead of replacing the existing one.
- Added a Scoop bucket (`bucket/win-terminal-saving-sessions.json`) so
  Windows users can `scoop install win-terminal-saving-sessions`.
- Set the executable bit on the `.sh` scripts so a fresh clone/download
  doesn't hit `permission denied`.
