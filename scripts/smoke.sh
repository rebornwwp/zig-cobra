#!/usr/bin/env bash
# Smoke tests for the example CLIs (demo + dockr).
# Guards end-to-end behavior that unit tests cannot cover: real process exit
# codes, stdout/stderr routing, help rendering, completion protocol and scripts.
#
# Usage: ./scripts/smoke.sh   (run from the repository root; requires zig 0.17)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0

fail() {
    echo "SMOKE FAIL: $1" >&2
    FAIL=$((FAIL + 1))
}
ok() {
    PASS=$((PASS + 1))
}
check_contains() { # <desc> <haystack> <needle>
    if printf '%s' "$2" | grep -qF -- "$3"; then ok; else fail "$1 (missing: $3)"; fi
}
check_exit() { # <desc> <expected> <actual>
    if [ "$2" = "$3" ]; then ok; else fail "$1 (expected exit $2, got $3)"; fi
}

echo "==> Building examples"
zig build

DEMO=./zig-out/bin/demo
DOCKR=./zig-out/bin/dockr

echo "==> demo smoke tests"

out=$($DEMO hello --name Smoke 2>&1) && rc=$? || rc=$?
check_exit "demo hello runs" 0 "$rc"
check_contains "demo hello output" "$out" "hello Smoke"

out=$($DEMO hello -n Short 2>&1) && rc=$? || rc=$?
check_exit "demo hello shorthand flag" 0 "$rc"
check_contains "demo hello shorthand output" "$out" "hello Short"

out=$($DEMO --help 2>&1) && rc=$? || rc=$?
check_exit "demo --help exits 0" 0 "$rc"
check_contains "help lists subcommands" "$out" "Available Commands:"
check_contains "help lists hello" "$out" "hello"
check_contains "help lists generated completion cmd" "$out" "completion"
check_contains "help lists generated help cmd" "$out" "help"
check_contains "help shows usage" "$out" "Usage:"

out=$($DEMO help hello 2>&1) && rc=$? || rc=$?
check_exit "demo help <cmd> exits 0" 0 "$rc"
check_contains "demo help <cmd> shows target help" "$out" "Say hello to someone"

out=$($DEMO badcmd 2>&1) && rc=$? || rc=$?
check_exit "unknown command exits 1" 1 "$rc"
check_contains "unknown command error message" "$out" 'unknown command "badcmd"'

out=$($DEMO hel 2>&1) && rc=$? || rc=$?
check_exit "typo command exits 1" 1 "$rc"
check_contains "suggestion header" "$out" "Did you mean this?"
check_contains "suggestion content" "$out" "hello"

# __complete protocol: value<TAB>description lines followed by :<directive>
out=$($DEMO __complete "" 2>/dev/null) && rc=$? || rc=$?
check_exit "__complete exits 0" 0 "$rc"
check_contains "__complete lists hello with description" "$out" "$(printf 'hello\tSay hello to someone')"
check_contains "__complete directive line" "$out" ":4"

out=$($DEMO __completeNoDesc "" 2>/dev/null) && rc=$? || rc=$?
check_exit "__completeNoDesc exits 0" 0 "$rc"
if printf '%s' "$out" | grep -qF "$(printf 'hello\t')"; then
    fail "__completeNoDesc must strip descriptions"
else
    ok
fi

out=$($DEMO __complete hello "-" 2>/dev/null) && rc=$? || rc=$?
check_exit "__complete flag names exits 0" 0 "$rc"
check_contains "__complete suggests --name" "$out" "--name"
check_contains "__complete suggests -n" "$out" "-n"

# Completion script generation for all shells
for shell in bash zsh fish powershell; do
    out=$($DEMO completion $shell 2>/dev/null) && rc=$? || rc=$?
    check_exit "demo completion $shell exits 0" 0 "$rc"
    if [ -n "$out" ]; then ok; else fail "demo completion $shell produced empty output"; fi
    check_contains "demo completion $shell references program" "$out" "demo"
    check_contains "demo completion $shell uses __complete protocol" "$out" "__complete"
done

# Generated bash script must be valid bash
if bash -n <($DEMO completion bash 2>/dev/null); then ok; else fail "demo bash completion script has syntax errors"; fi

echo "==> dockr smoke tests"

out=$($DOCKR --help 2>&1) && rc=$? || rc=$?
check_exit "dockr --help exits 0" 0 "$rc"
check_contains "dockr help lists container" "$out" "container"

out=$($DOCKR container ls 2>&1) && rc=$? || rc=$?
check_exit "dockr container ls exits 0" 0 "$rc"
check_contains "persistent pre-run hook fires" "$out" "Loaded config: /etc/dockr/config.toml"

out=$($DOCKR container ls --config /tmp/smoke.toml 2>&1) && rc=$? || rc=$?
check_exit "persistent flag parses on leaf command" 0 "$rc"
check_contains "inherited persistent flag value" "$out" "Loaded config: /tmp/smoke.toml"

out=$($DOCKR container ls --help 2>&1) && rc=$? || rc=$?
check_exit "dockr container ls --help exits 0" 0 "$rc"
check_contains "child help shows Global Flags section" "$out" "Global Flags:"
check_contains "child help lists inherited flag" "$out" "--config"

out=$($DOCKR container run --name web nginx:latest 2>&1) && rc=$? || rc=$?
check_exit "dockr container run exits 0" 0 "$rc"

out=$($DOCKR nope 2>&1) && rc=$? || rc=$?
check_exit "dockr unknown command exits 1" 1 "$rc"

out=$($DOCKR completion zsh 2>/dev/null) && rc=$? || rc=$?
check_exit "dockr completion zsh exits 0" 0 "$rc"
check_contains "zsh script has compdef header" "$out" "#compdef dockr"

echo
echo "Smoke tests: $PASS passed, $FAIL failed"
if [ "$FAIL" -ne 0 ]; then
    exit 1
fi
