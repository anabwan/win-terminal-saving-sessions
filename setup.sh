#!/usr/bin/env bash
# Entry point for installing or uninstalling win-terminal-saving-sessions
# from a Git Bash prompt (PowerShell equivalent: setup.ps1).
#
# Usage:
#   ./setup.sh                   # install
#   ./setup.sh --dry-run         # show what would change, write nothing
#   ./setup.sh --action uninstall   # restore the most recent backups
set -euo pipefail

ACTION="install"
DRY_RUN_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --action)
            ACTION="$2"
            shift 2
            ;;
        --action=*)
            ACTION="${1#--action=}"
            shift
            ;;
        --dry-run)
            DRY_RUN_ARGS=(--dry-run)
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installer="${script_dir}/scripts/install-win-terminal-session-restore.sh"

case "$ACTION" in
    install)
        exec "$installer" "${DRY_RUN_ARGS[@]}"
        ;;
    uninstall)
        exec "$installer" --revert
        ;;
    *)
        echo "Unknown --action: $ACTION (expected 'install' or 'uninstall')" >&2
        exit 1
        ;;
esac
