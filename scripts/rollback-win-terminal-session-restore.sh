#!/usr/bin/env bash
# Thin wrapper: restores the previous settings.json/.bashrc from backups.
# Same as install-win-terminal-session-restore.sh --revert, as its own script.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${script_dir}/install-win-terminal-session-restore.sh" --revert
