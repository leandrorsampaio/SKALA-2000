#!/usr/bin/env bash
#
# CPU of one process as a percentage of one core, from `ps -o time=` deltas: the way the
# reference was measured, so the numbers compare.
#
#   scripts/measure-cpu.sh <pid> [seconds=60] [warmup=10]
#
set -euo pipefail
PID="$1"; SECONDS_TO_SAMPLE="${2:-60}"; WARMUP="${3:-10}"

cputime() {
    # [[dd-]hh:]mm:ss.cc → seconds
    ps -o time= -p "$PID" | awk '{
        n = split($1, a, ":"); s = 0
        for (i = 1; i <= n; i++) { v = a[i]; if (index(v, "-")) { split(v, d, "-"); v = d[1] * 24 + d[2] } s = s * 60 + v }
        printf "%.3f", s }'
}

sleep "$WARMUP"
start=$(cputime)
t0=$(python3 -c 'import time; print(time.time())')
sleep "$SECONDS_TO_SAMPLE"
end=$(cputime)
t1=$(python3 -c 'import time; print(time.time())')
python3 -c "print(f'{100 * ($end - $start) / ($t1 - $t0):.2f}% of one core over {($t1 - $t0):.0f} s')"
