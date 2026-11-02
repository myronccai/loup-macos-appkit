#!/usr/bin/env bash
# run_all.sh — the gate for loup-macos-appkit and the loup-macos-* example apps.
# Lives in loup-macos-appkit; the apps are sibling checkouts in its PARENT directory.
# For each ../loup-macos-* app (this library excluded), or the apps named on the line:
#   1. `loup build` (self-hosted)   2. `loup-bootstrap build --target native` (Stage0)
#   3. `loup test --strict src`           (the app's host.dual logic tests)
#   4. `./<app> --self-test`              for both builds, against selftest.out
#      (under lldb when it is installed: a crash prints a backtrace instead of
#      opening a crash-report window)
# --screenshots: the self-test also rewrites the app's screenshot.png.
# --probes: the library's probes (probes/*_probe here) are checked the same way.
# Usage, from inside loup-macos-appkit:  bash run_all.sh [--probes] [--screenshots] [app…]
#   bash run_all.sh --probes   |   bash run_all.sh loup-macos-calculator
# From an app checkout:  bash ../loup-macos-appkit/run_all.sh loup-macos-calculator
# Needs macOS, the Xcode Command Line Tools, and Loup newer than 1.27.0 (loup, loup-build,
# loup-llvm, loup-test, loup-bootstrap) on PATH. If links fail with "tapi error …
# unknown architecture", export SDKROOT to an older SDK (see README.md).
#   env: TIMEOUT (seconds per self-test, default 30)
set -uo pipefail
# The apps are sibling checkouts of this repository, in its parent directory (see README.md).
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TIMEOUT="${TIMEOUT:-30}"
SHOTS=0
PROBES=0
APPS=()
for a in "$@"; do
    case "$a" in
        --screenshots) SHOTS=1 ;;
        --probes) PROBES=1 ;;
        -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
        *) APPS+=("$a") ;;
    esac
done
[ "$(uname -s)" = "Darwin" ] || { echo "SKIP: macOS only"; exit 0; }
for tool in loup loup-build loup-llvm loup-test loup-bootstrap clang; do
    command -v "$tool" >/dev/null 2>&1 || { echo "FAIL: $tool not on PATH"; exit 1; }
done
if [ ${#APPS[@]} -eq 0 ]; then
    for d in "$HERE"/loup-macos-*/; do [ -d "$d" ] && [ "$(basename "$d")" != loup-macos-appkit ] && APPS+=("$(basename "$d")"); done
fi
T="$(mktemp -d "${TMPDIR:-/tmp}/loup-macos-examples.XXXXXX")"
trap 'rm -rf "$T"' EXIT
fail=0

# Run "$@" with a deadline; returns its status (killed → 124).
deadline() {
    "$@" &
    local pid=$!
    ( sleep "$TIMEOUT"; kill -9 "$pid" 2>/dev/null ) &
    local w=$!
    wait "$pid"; local rc=$?
    kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
    [ "$rc" -eq 137 ] && rc=124
    return $rc
}

# <out> <err> <bin> <args…>: run the binary under lldb (when it is there), so a
# crash stops in the debugger, prints a backtrace to <err>, and never opens a
# crash-report window. Returns the program's exit status (a crash → 139).
safe_run() {
    local out="$1" err="$2"; shift 2
    if ! command -v lldb >/dev/null 2>&1; then
        deadline "$@" >"$out" 2>"$err"
        return $?
    fi
    local bin="$1"; shift
    local log="$err.lldb"
    deadline lldb --batch --no-lldbinit \
        -o "process launch -o $out -e $err -- $*" \
        -k "thread backtrace" -k "process kill" -k "quit" \
        -- "$bin" >"$log" 2>&1
    local rc=$?
    [ "$rc" -eq 124 ] && return 124
    # A stop (a signal, a trap) is a crash: the kill that follows also "exits".
    if grep -q 'stop reason = ' "$log"; then
        cat "$log" >>"$err"
        return 139
    fi
    local st; st="$(sed -n 's/.*exited with status = \([0-9]*\).*/\1/p' "$log" | tail -1)"
    if [ -z "$st" ]; then
        cat "$log" >>"$err"
        return 139
    fi
    return "$st"
}

clean() {
    local dir="$1" bin="$2"
    rm -rf "$dir/.temp" "$dir/.loup-cache" "$dir/$bin" "$dir"/*.loupbuild.fp
}

# <dir>: check one project; its binary is the manifest's package name.
check() {
    local dir="$1"
    local manifest; manifest="$(ls "$dir"/*.lppkg 2>/dev/null | head -1)"
    [ -n "$manifest" ] || { printf '%-28s FAIL (no manifest)\n' "$(basename "$dir")"; fail=1; return; }
    local bin; bin="$(sed -n 's/^name *= *"\(.*\)"/\1/p' "$manifest" | head -1)"
    local name; name="$(basename "$dir")"
    local status="OK" detail=""
    local golden="$dir/selftest.out"
    for driver in sh s0; do
        clean "$dir" "$bin"
        if [ "$driver" = sh ]; then
            (cd "$dir" && loup build) >"$T/$name.$driver.build" 2>&1
        else
            (cd "$dir" && loup-bootstrap build --target native) >"$T/$name.$driver.build" 2>&1
        fi
        if [ ! -x "$dir/$bin" ]; then status="FAIL"; detail="$detail $driver:build"; continue; fi
        local shot=()
        if [ "$SHOTS" = 1 ] && [ "$driver" = sh ] && [ -f "$golden" ]; then shot=("$dir/screenshot.png"); fi
        (cd "$dir" && safe_run "$T/$name.$driver.out" "$T/$name.$driver.err" "./$bin" --self-test "${shot[@]+"${shot[@]}"}")
        local rc=$?
        if [ "$rc" -ne 0 ]; then status="FAIL"; detail="$detail $driver:exit=$rc"; continue; fi
        if [ -f "$golden" ]; then
            diff -q "$golden" "$T/$name.$driver.out" >/dev/null || { status="FAIL"; detail="$detail $driver:selftest-differs"; }
        fi
    done
    if [ -f "$T/$name.sh.out" ] && [ -f "$T/$name.s0.out" ] && ! diff -q "$T/$name.sh.out" "$T/$name.s0.out" >/dev/null; then
        status="FAIL"; detail="$detail drivers-differ"
    fi
    clean "$dir" "$bin"
    if ls "$dir"/src/*_test.lpscr >/dev/null 2>&1; then
        (cd "$dir" && loup test --strict src) >"$T/$name.test" 2>&1 || { status="FAIL"; detail="$detail loup-test"; }
        detail="$detail ($(grep -E '^test:' "$T/$name.test" | tail -1))"
    fi
    printf '%-28s %s%s\n' "$name" "$status" "$detail"
    if [ "$status" != OK ]; then
        fail=1
        for f in "$T/$name".*.err "$T/$name".*.build "$T/$name.test"; do
            [ -s "$f" ] && { echo "    --- $(basename "$f")"; grep -v -E 'warning|^\s*$' "$f" | tail -6 | sed 's/^/    /'; }
        done
        if [ -f "$golden" ] && [ -f "$T/$name.sh.out" ]; then
            diff "$golden" "$T/$name.sh.out" | head -10 | sed 's/^/    /'
        fi
    fi
}

for app in ${APPS[@]+"${APPS[@]}"}; do check "$HERE/$app"; done
if [ "$PROBES" = 1 ]; then
    for p in "$HERE"/loup-macos-appkit/probes/*_probe/; do check "${p%/}"; done
fi
[ "$fail" -eq 0 ] && echo "PASS" || { echo "FAIL"; exit 1; }
