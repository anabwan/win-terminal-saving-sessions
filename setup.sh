#!/usr/bin/env bash
# Entry point for installing or uninstalling win-terminal-saving-sessions
# from a Git Bash prompt (PowerShell equivalent: setup.ps1).
#
# Usage:
#   ./setup.sh                      # install
#   ./setup.sh --dry-run            # show what would change, write nothing
#   ./setup.sh --action uninstall   # restore the most recent backups
#   ./setup.sh --action status      # report install state and version
#   ./setup.sh --version            # print the tool version
#   ./setup.sh --help               # print usage
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
        --version|--help|-h)
            flag="$1"
            script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            exec "${script_dir}/scripts/install-win-terminal-session-restore.sh" "$flag"
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
    status)
        exec "$installer" --status
        ;;
    *)
        echo "Unknown --action: $ACTION (expected 'install', 'uninstall', or 'status')" >&2
        exit 1
        ;;
esac
