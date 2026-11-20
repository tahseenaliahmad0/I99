#!/usr/bin/env bash
# I-99 project check (GDD 13.10).
#
# Runs, in order: asset import, a parse check of every script and scene, the
# data validator, the tests in tests/tests.json, and the headless scene smoke
# tests. Exits non-zero if any step fails or prints an engine error.
# After the data validator it also runs the sound check (tools/audio_check.gd).
#
#   tools/check.sh            every step
#   tools/check.sh --final    also require every registered test to pass (GDD 18.2)
#
# Set GODOT to use a specific engine binary (default: godot on PATH).

set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
TEST_ARGS=()
for arg in "$@"; do
  case "$arg" in
    --final) TEST_ARGS+=("--final") ;;
    *) echo "check.sh: unknown option '$arg'" >&2; exit 2 ;;
  esac
done

if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "check.sh: '$GODOT' not found. Install Godot 4.7.x or set GODOT." >&2
  exit 2
fi

LOG_DIR=".godot/check"
mkdir -p "$LOG_DIR"
FAILED=()

# run_step <name> <godot args...>
# A step fails on a non-zero exit code or on any engine error line in its output.
run_step() {
  local name="$1"; shift
  local log="$LOG_DIR/$name.log"
  local started=$SECONDS
  "$GODOT" --headless --path . "$@" 2>&1 | sed -e 's/\x1b\[[0-9;]*[A-Za-z]//g' > "$log"
  local code=${PIPESTATUS[0]}
  local errors
  errors=$(grep -cE '^[[:space:]]*(SCRIPT ERROR|USER SCRIPT ERROR|USER ERROR|ERROR):' "$log")
  local took=$((SECONDS - started))
  if [ "$code" -ne 0 ] || [ "$errors" -ne 0 ]; then
    echo "[FAIL] $name (exit $code, $errors error line(s), ${took}s) -- see $log"
    grep -vE '^[[:space:]]*$' "$log" | grep -vE '^Godot Engine v' | tail -n 60 | sed 's/^/    /'
    FAILED+=("$name")
  else
    echo "[ ok ] $name (${took}s): $(grep -vE '^[[:space:]]*$' "$log" | tail -n 1)"
  fi
}

echo "I-99 check: $("$GODOT" --version)"
run_step import --import
run_step parse --script res://tools/parse_check.gd
run_step data --script res://tools/validate_data.gd
run_step audio --script res://tools/audio_check.gd
if [ "${#TEST_ARGS[@]}" -gt 0 ]; then
  run_step tests --script res://tests/run_tests.gd -- "${TEST_ARGS[@]}"
else
  run_step tests --script res://tests/run_tests.gd
fi
run_step smoke --script res://tools/smoke_all.gd
run_step postfx --script res://tools/post_fx_check.gd

if [ "${#FAILED[@]}" -ne 0 ]; then
  echo "CHECK FAILED: ${FAILED[*]}"
  exit 1
fi
echo "CHECK OK"
