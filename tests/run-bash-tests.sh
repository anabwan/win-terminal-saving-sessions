#!/usr/bin/env bash
# Lightweight, dependency-free regression tests for
# install-win-terminal-session-restore.sh - no bats/framework required.
#
# Usage: ./tests/run-bash-tests.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TARGET="${REPO_ROOT}/scripts/install-win-terminal-session-restore.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '\033[32m[PASS]\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '\033[31m[FAIL]\033[0m %s\n' "$1"; }

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$desc"
    else
        fail "$desc (expected '$expected', got '$actual')"
    fi
}

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

# Each test runs in its own `bash -c` subshell (no extra args, so the sourced
# script's own `for arg in "$@"` loop sees an empty arg list) that sources the
# target script and then calls one or more of its functions directly.
run() {
    bash -c 'source "'"$TARGET"'"; '"$1"
}

echo "== get_bashrc_status: missing / plain file =="
out=$(run 'get_bashrc_status "'"$WORKDIR"'/missing.bashrc"')
assert_eq "reports not found for a missing file" "false|||0" "$out"

echo 'export FOO=bar' > "$WORKDIR/plain.bashrc"
out=$(run 'get_bashrc_status "'"$WORKDIR"'/plain.bashrc"')
assert_eq "reports not found for a file with no managed block" "false|||0" "$out"

echo "== set_bashrc_block idempotency =="
rm -f "$WORKDIR/first.bashrc"
run 'set_bashrc_block "'"$WORKDIR"'/first.bashrc" >/dev/null 2>&1' || true
status=$(run 'get_bashrc_status "'"$WORKDIR"'/first.bashrc"')
IFS='|' read -r found version uptodate blockcount <<< "$status"
assert_eq "creates the managed block on first run" "true" "$found"
assert_eq "block count is 1 after first run" "1" "$blockcount"
assert_eq "up to date after first run" "true" "$uptodate"

run 'set_bashrc_block "'"$WORKDIR"'/first.bashrc" >/dev/null 2>&1' || true
status2=$(run 'get_bashrc_status "'"$WORKDIR"'/first.bashrc"')
IFS='|' read -r _ _ _ blockcount2 <<< "$status2"
assert_eq "does not duplicate the block on a second run (regression)" "1" "$blockcount2"

echo "== set_bashrc_block replaces an older/unversioned block =="
printf '# >>> win-terminal-saving-sessions >>>\nsome old content\n# <<< win-terminal-saving-sessions <<<\n' > "$WORKDIR/upgrade.bashrc"
run 'set_bashrc_block "'"$WORKDIR"'/upgrade.bashrc" >/dev/null 2>&1' || true
markercount=$(grep -c '# >>> win-terminal-saving-sessions' "$WORKDIR/upgrade.bashrc")
assert_eq "replaces old block instead of appending a duplicate" "1" "$markercount"

echo "== set_bashrc_block preserves unrelated content =="
echo 'export MY_CUSTOM=1' > "$WORKDIR/preserve.bashrc"
run 'set_bashrc_block "'"$WORKDIR"'/preserve.bashrc" >/dev/null 2>&1' || true
if grep -q 'export MY_CUSTOM=1' "$WORKDIR/preserve.bashrc"; then
    pass "preserves unrelated content around the managed block"
else
    fail "preserves unrelated content around the managed block"
fi

echo "== get_bashrc_status corruption detection =="
run 'set_bashrc_block "'"$WORKDIR"'/corrupted.bashrc" >/dev/null 2>&1' || true
corrupted_content=$(cat "$WORKDIR/corrupted.bashrc")
printf '%s\n' "$corrupted_content" >> "$WORKDIR/corrupted.bashrc"
status3=$(run 'get_bashrc_status "'"$WORKDIR"'/corrupted.bashrc"')
IFS='|' read -r _ _ _ blockcount3 <<< "$status3"
if [[ "$blockcount3" -gt 1 ]]; then
    pass "reports block count > 1 when the managed block is duplicated (regression safeguard)"
else
    fail "reports block count > 1 when the managed block is duplicated (got $blockcount3)"
fi

echo "== get_settings_status / set_persisted_window_layout =="
echo '{"foo": "bar"}' > "$WORKDIR/settings.json"
run 'set_persisted_window_layout "'"$WORKDIR"'/settings.json" >/dev/null 2>&1' || true
if run 'get_settings_status "'"$WORKDIR"'/settings.json"'; then
    pass "adds the setting to a fresh settings.json and marks it applied"
else
    fail "adds the setting to a fresh settings.json and marks it applied"
fi

run 'set_persisted_window_layout "'"$WORKDIR"'/settings.json" >/dev/null 2>&1'
rc=$?
assert_eq "is idempotent on a second run (no-op exit code 1)" "1" "$rc"

echo "---"
echo "Passed: $PASS, Failed: $FAIL"
[[ "$FAIL" -eq 0 ]]
