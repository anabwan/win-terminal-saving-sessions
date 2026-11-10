#!/usr/bin/env bash
# Configures Windows Terminal + Git Bash so tabs/panes, working directories,
# and command history survive a PC restart.
#
# Bash equivalent of Install-WinTerminalSessionRestore.ps1 - run this from a
# Git Bash prompt instead of PowerShell. Same two changes, each backed up
# before being touched:
#
#   1. Windows Terminal settings.json: sets
#        "firstWindowPreference": "persistedWindowLayout"
#   2. ~/.bashrc: adds a managed block that flushes history to disk after
#      every command (and immediately via a DEBUG trap) and emits the
#      OSC 9;9 escape sequence so Windows Terminal can track each pane's CWD.
#
# NOTE: Windows Terminal does not support restoring pane scrollback/output
# content. This script does not attempt to work around that.
#
# Usage:
#   ./install-win-terminal-session-restore.sh [--dry-run] [--revert] [--status] [--version] [--help]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TOOL_VERSION="$(tr -d '[:space:]' < "${REPO_ROOT}/VERSION")"

DRY_RUN=0
REVERT=0
STATUS=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --revert) REVERT=1 ;;
        --status) STATUS=1 ;;
        --version)
            echo "win-terminal-saving-sessions v${TOOL_VERSION}"
            exit 0
            ;;
        -h|--help)
            cat <<EOF
win-terminal-saving-sessions v${TOOL_VERSION}

Usage: install-win-terminal-session-restore.sh [--dry-run] [--revert] [--status] [--version] [--help]

  (no flags)  Apply the Windows Terminal + Git Bash changes.
  --dry-run   Show what would change without writing anything.
  --revert    Restore the most recent backups (undo install).
  --status    Report current install state and version, write nothing.
  --version   Print the tool version.
  --help      Print this message.
EOF
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

section() {
    printf '\n\033[36m== %s ==\033[0m\n' "$1"
}

ok() { printf '\033[32m%s\033[0m\n' "$1"; }
warn() { printf '\033[33m%s\033[0m\n' "$1"; }
muted() { printf '\033[90m%s\033[0m\n' "$1"; }

backup_file() {
    local path="$1"
    local stamp
    stamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="${path}.bak-${stamp}"
    cp -p "$path" "$backup_path"
    printf '%s' "$backup_path"
}

restore_latest_backup() {
    local path="$1"
    local dir backup
    dir=$(dirname -- "$path")
    backup=$(find "$dir" -maxdepth 1 -name "$(basename -- "$path").bak-*" 2>/dev/null | sort -r | head -n1)
    if [[ -z "$backup" ]]; then
        warn "  No backup found for $path, skipping."
        return
    fi
    cp -p "$backup" "$path"
    ok "  Restored $path from $(basename -- "$backup")"
}

get_windows_terminal_settings_paths() {
    local candidates=(
        "${LOCALAPPDATA}/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
        "${LOCALAPPDATA}/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"
        "${LOCALAPPDATA}/Microsoft/Windows Terminal/settings.json"
    )
    local p
    for p in "${candidates[@]}"; do
        local unix_path
        unix_path=$(cygpath -u "$p" 2>/dev/null || echo "$p")
        [[ -f "$unix_path" ]] && printf '%s\n' "$unix_path"
    done
}

set_persisted_window_layout() {
    local path="$1"
    local desired='"firstWindowPreference": "persistedWindowLayout"'

    if grep -Eq '"firstWindowPreference"[[:space:]]*:[[:space:]]*"[^"]*"' "$path"; then
        if grep -Eq "^[[:space:]]*${desired}," "$path" || grep -Fq "$desired" "$path"; then
            muted "  Already set: $path"
            return 1
        fi
        if [[ "$DRY_RUN" -eq 1 ]]; then
            warn "  [DryRun] Would update: $path"
            return 0
        fi
        backup_file "$path" >/dev/null
        sed -i -E 's/"firstWindowPreference"[[:space:]]*:[[:space:]]*"[^"]*"/"firstWindowPreference": "persistedWindowLayout"/' "$path"
        ok "  Updated: $path"
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "  [DryRun] Would update: $path"
        return 0
    fi
    backup_file "$path" >/dev/null
    awk -v desired="    ${desired}," '
        !done && $0 ~ /^[[:space:]]*\{/ { print; print desired; done=1; next }
        { print }
    ' "$path" > "${path}.tmp" && mv "${path}.tmp" "$path"
    ok "  Updated: $path"
}

# Matches both the current versioned marker and the original unversioned one,
# so upgrades from any prior install are detected and replaced.
BASHRC_BEGIN_PATTERN='# >>> win-terminal-saving-sessions( v[0-9][0-9.]*)? >>>'
BASHRC_BLOCK_BEGIN="# >>> win-terminal-saving-sessions v${TOOL_VERSION} >>>"
BASHRC_BLOCK_END='# <<< win-terminal-saving-sessions <<<'
BASHRC_BLOCK_BODY='# Managed by win-terminal-saving-sessions. Safe to delete this block to revert.

# Flush bash history to disk after every command instead of only on a clean
# shell exit, so history survives an unclean shutdown/reboot.
shopt -s histappend
export HISTSIZE=100000
export HISTFILESIZE=200000
export HISTCONTROL=ignoreboth:erasedups
PROMPT_COMMAND=${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'"'"'history -a; history -c; history -r'"'"'

# PROMPT_COMMAND only runs once a command finishes and bash shows its next
# prompt. If a command takes over the terminal and never returns control
# (ssh, vim, tmux, etc.) before the terminal is killed, that command is never
# flushed. This trap flushes immediately when the command is entered instead.
trap '"'"'history -a'"'"' DEBUG

# Report the current working directory to Windows Terminal (OSC 9;9) so this
# pane'"'"'s CWD is restored when using "firstWindowPreference": "persistedWindowLayout".
PROMPT_COMMAND=${PROMPT_COMMAND:+"$PROMPT_COMMAND; "}'"'"'printf "\e]9;9;%s\e\\" "`cygpath -w "$PWD" -C ANSI`"'"'"''

set_bashrc_block() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            warn "  [DryRun] Would create: $path"
            return 0
        fi
        : > "$path"
    fi

    local new_block="${BASHRC_BLOCK_BEGIN}
${BASHRC_BLOCK_BODY}
${BASHRC_BLOCK_END}"

    if grep -Eq "$BASHRC_BEGIN_PATTERN" "$path"; then
        local current_block
        current_block=$(awk -v b="$BASHRC_BEGIN_PATTERN" -v e="$BASHRC_BLOCK_END" '
            $0 ~ b{p=1} p{print} $0==e{exit}
        ' "$path")
        if [[ "$current_block" == "$new_block" ]]; then
            muted "  Already configured: $path"
            return 1
        fi
        if [[ "$DRY_RUN" -eq 1 ]]; then
            warn "  [DryRun] Would update: $path"
            return 0
        fi
        backup_file "$path" >/dev/null
        awk -v b="$BASHRC_BEGIN_PATTERN" -v e="$BASHRC_BLOCK_END" -v new="$new_block" '
            $0 ~ b{print new; skip=1; next}
            skip && $0==e{skip=0; next}
            skip{next}
            {print}
        ' "$path" > "${path}.tmp" && mv "${path}.tmp" "$path"
        ok "  Updated: $path"
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        warn "  [DryRun] Would update: $path"
        return 0
    fi
    if [[ -s "$path" ]]; then
        backup_file "$path" >/dev/null
    fi
    printf '\n%s\n' "$new_block" >> "$path"
    ok "  Updated: $path"
}

# Prints "found|version|uptodate|blockcount" (pipe-separated) without writing anything.
get_bashrc_status() {
    local path="$1"
    if [[ ! -f "$path" ]] || ! grep -Eq "$BASHRC_BEGIN_PATTERN" "$path"; then
        printf 'false|||0\n'
        return
    fi
    local block_count begin_line version
    block_count=$(grep -Ec "$BASHRC_BEGIN_PATTERN" "$path")
    begin_line=$(grep -E "$BASHRC_BEGIN_PATTERN" "$path" | head -n1)
    version=$(grep -oE 'v[0-9][0-9.]*' <<< "$begin_line" | sed 's/^v//')
    [[ -z "$version" ]] && version='pre-1.0.0 (unversioned)'

    local current_block new_block
    current_block=$(awk -v b="$BASHRC_BEGIN_PATTERN" -v e="$BASHRC_BLOCK_END" '
        $0 ~ b{p=1} p{print} $0==e{exit}
    ' "$path")
    new_block="${BASHRC_BLOCK_BEGIN}
${BASHRC_BLOCK_BODY}
${BASHRC_BLOCK_END}"
    local uptodate='false'
    [[ "$current_block" == "$new_block" ]] && uptodate='true'
    printf 'true|%s|%s|%s\n' "$version" "$uptodate" "$block_count"
}

get_settings_status() {
    local path="$1"
    grep -Eq '"firstWindowPreference"[[:space:]]*:[[:space:]]*"persistedWindowLayout"' "$path"
}

# ---------------------------------------------------------------------------
# Source this script (`source install-win-terminal-session-restore.sh`) to load
# the functions above for testing without running main() below.
main() {
mapfile -t settings_paths < <(get_windows_terminal_settings_paths)
bashrc_path="${HOME}/.bashrc"

if [[ "$STATUS" -eq 1 ]]; then
    section "win-terminal-saving-sessions status (tool v${TOOL_VERSION})"

    if [[ ${#settings_paths[@]} -eq 0 ]]; then
        warn '  settings.json: not found. Is Windows Terminal installed?'
    fi
    for p in "${settings_paths[@]}"; do
        if get_settings_status "$p"; then
            ok "  settings.json: applied ($p)"
        else
            warn "  settings.json: NOT applied ($p)"
        fi
    done

    IFS='|' read -r found version uptodate blockcount <<< "$(get_bashrc_status "$bashrc_path")"
    if [[ "$found" != "true" ]]; then
        warn "  .bashrc: not installed ($bashrc_path)"
    elif [[ "$blockcount" -gt 1 ]]; then
        printf '\033[31m  .bashrc: CORRUPTED - %s managed blocks found (expected 1). Manual cleanup required - see %s.\033[0m\n' "$blockcount" "$bashrc_path"
    elif [[ "$version" == "$TOOL_VERSION" && "$uptodate" == "true" ]]; then
        ok "  .bashrc: installed, v${version} (up to date)"
    else
        warn "  .bashrc: installed, v${version} (outdated - latest is v${TOOL_VERSION}, run install to update)"
    fi
    exit 0
fi

if [[ "$REVERT" -eq 1 ]]; then
    section 'Reverting Windows Terminal settings.json'
    if [[ ${#settings_paths[@]} -eq 0 ]]; then
        warn '  No settings.json found.'
    fi
    for p in "${settings_paths[@]}"; do
        restore_latest_backup "$p"
    done

    section 'Reverting .bashrc'
    restore_latest_backup "$bashrc_path"

    printf '\n\033[36mDone. Restart Windows Terminal and open a new Git Bash tab for changes to take effect.\033[0m\n'
    exit 0
fi

section 'Windows Terminal: persisted window layout'
if [[ ${#settings_paths[@]} -eq 0 ]]; then
    warn '  No settings.json found. Is Windows Terminal installed?'
fi
for p in "${settings_paths[@]}"; do
    echo "  Found: $p"
    set_persisted_window_layout "$p" || true
done

section 'Git Bash: ~/.bashrc history + CWD reporting'
echo "  Target: $bashrc_path"
set_bashrc_block "$bashrc_path" || true

section 'Done'
printf '\033[36mRestart Windows Terminal fully (not just close the window - use the X on every window or Quit) for the settings.json change to apply.\033[0m\n'
warn "IMPORTANT: bash only reads .bashrc when a shell STARTS. Any Git Bash tab that was already open before running this script won't track its working directory until you run \`source ~/.bashrc\` in it (or close and reopen that tab). New tabs opened from now on pick it up automatically."
muted "Run with --revert to restore the previous settings.json/.bashrc from the backups this script made."
muted "Note: Windows Terminal cannot restore pane scrollback/output content - only tabs, panes, profiles and (now) working directories."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
