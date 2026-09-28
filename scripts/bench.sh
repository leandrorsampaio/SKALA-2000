#!/usr/bin/env bash
#
# Launches build/SKALA-2000.app in one bench scenario, measures its CPU and memory, quits.
# Refuses to start while another SKALA-2000 runs: it would measure the wrong one.
#
#   scripts/bench.sh static|flash|demo|real [seconds=60] [warmup=10]
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:?usage: bench.sh static|flash|demo|real [seconds=60] [warmup=10]}"; SECONDS_TO_SAMPLE="${2:-60}"; WARMUP="${3:-10}"
if pgrep -x SKALA-2000 >/dev/null; then
    echo "SKALA-2000 is running. Quit it first; the bench starts its own copy." >&2
    exit 1
fi
# Whatever fails below, the copy this starts is quit, and quit properly: it saves.
trap 'osascript -e '"'"'quit app "SKALA-2000"'"'"' >/dev/null 2>&1 || true' EXIT
open -n "$ROOT/build/SKALA-2000.app" --env SKALA_BENCH="$MODE" --env SKALA_BENCH_HIDE="${HIDE:-0}" --env SKALA_BENCH_FULLSCREEN="${FULLSCREEN:-0}"
sleep 2
PID=$(pgrep -n -x SKALA-2000)
CPU=$("$ROOT/scripts/measure-cpu.sh" "$PID" "$SECONDS_TO_SAMPLE" "$WARMUP")
MEM=$(footprint -p "$PID" 2>/dev/null | awk '/phys_footprint:/ {print $2, $3; exit}')
LOG="$HOME/Library/Application Support/SKALA-2000/bench.log"
WITH_CHILDREN=$(python3 - "$LOG" "$WARMUP" <<'PY'
import sys
rows=[list(map(float,l.split())) for l in open(sys.argv[1]) if l.strip()]
warm=float(sys.argv[2])
start=next((r for r in rows if r[0]-rows[0][0]>=warm), rows[0]); end=rows[-1]
span=end[0]-start[0]
print(f"with children {100*((end[1]+end[2])-(start[1]+start[2]))/span:.2f}% over {span:.0f} s" if span>0 else "no span")
PY
)
echo "$MODE: $CPU ($WITH_CHILDREN), footprint ${MEM:-?}"
