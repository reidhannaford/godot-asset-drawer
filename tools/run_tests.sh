#!/usr/bin/env bash
# Runs the headless tests: test/drawer_test.gd in two passes (the first
# builds libraries, the second checks they come back from project metadata),
# then test/placement_test.gd. Uses a throwaway HOME, and puts back this
# project's own drawer metadata after.
# Set GODOT to use a different Godot binary.
set -uo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-/Applications/Godot 4.7.2.app/Contents/MacOS/Godot}"
home="$(mktemp -d)"
metadata="$here/.godot/editor/project_metadata.cfg"
backup="$home/project_metadata.cfg"

[[ -f "$metadata" ]] && mv "$metadata" "$backup"
cleanup() {
	rm -f "$here"/test_tmp_*.tres "$metadata"
	[[ -f "$backup" ]] && mv "$backup" "$metadata"
	rm -rf "$home"
}
trap cleanup EXIT

HOME="$home" "$godot" --headless --import --path "$here" >/dev/null 2>&1
status=0
run_test() {
	echo "== $1${2:+ (pass $2)}"
	HOME="$home" RUN="${2:-}" "$godot" --headless --editor --path "$here" -s "res://test/$1" 2>&1 \
		| grep -E '^(PASS|FAIL|FAILURES|WATCHDOG)|SCRIPT ERROR'
	[[ ${PIPESTATUS[0]} -eq 0 ]] || status=1
}
run_test drawer_test.gd 1
run_test drawer_test.gd 2
rm -f "$metadata"
run_test placement_test.gd
exit $status
