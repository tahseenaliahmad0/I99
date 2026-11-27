#!/usr/bin/env bash
# The balance run of GDD 13.8: the DriverBot at three skills, a number of
# seeds per skill per Table, headless; the report against GDD 12.5 goes to
# artifacts/balance.json.
#
#   tools/run_balance.sh [seeds per skill per Table, default 100] [jobs, default one per core]
#
# One process drives one Table; the parts are put together at the end. The
# report does not fail on the numbers: it says where they stand.
# A hundred seeds are 2,100 Tellings: some hours on four cores.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SEEDS="${1:-100}"
JOBS="${2:-$(nproc 2>/dev/null || echo 2)}"
OUT="${BALANCE_OUT:-res://artifacts/balance.json}"
PARTS="artifacts/balance_parts"
mkdir -p "$PARTS"
RUN=("$GODOT" --headless --path . --script res://tools/run_balance.gd --)

TABLES="$("${RUN[@]}" --list-tables | sed -n 's/^table //p')"
if [ -z "$TABLES" ]; then
	echo "run_balance: no Tables found" >&2
	exit 1
fi
echo "run_balance: $SEEDS seed(s) per skill at each of $(echo "$TABLES" | wc -w) Tables, $JOBS job(s)"
echo "$TABLES" | xargs -P "$JOBS" -I{} "${RUN[@]}" --seeds="$SEEDS" --tables={} --part="res://$PARTS/{}.json" | grep '^run_balance' || true

MERGE=""
for table in $TABLES; do
	MERGE="${MERGE:+$MERGE,}res://$PARTS/$table.json"
done
"${RUN[@]}" --merge="$MERGE" --out="$OUT"
