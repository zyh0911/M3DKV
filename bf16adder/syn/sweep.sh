#!/usr/bin/env bash
# ============================================================================
#  sweep.sh -- delay / area / power curve for the single-path BF16 adder
#
#    source libs/env_synopsys.sh
#    source libs/asap7.sh
#    ./sweep.sh
#
#  For every operating point the SAIF is REGENERATED at that operation period.
#  The toggle rates in a SAIF are absolute (toggles per ps of the recorded
#  window), so re-using one SAIF across periods would report the power of one
#  rate while claiming the throughput of another, and energy/op would be wrong.
# ============================================================================
set -e
cd "$(dirname "$0")"

HIER_PERIODS=${HIER_PERIODS:-"400 450 500 650 800 1000"}
FLAT_PERIODS=${FLAT_PERIODS:-"400 650 1000"}
MODE=${MODE:-near}
NOPS=${NOPS:-20000}
CSV=${CSV:-out/sweep_${MODE}.csv}

mkdir -p out
: > "$CSV"

run_point () {          # $1 = period, $2 = keep_hier
    local P=$1 KH=$2 tag
    tag=bf16_add_$([ "$KH" = 1 ] && echo hier || echo flat)_${P}ps

    echo "### SAIF @ ${P}ps (mode=$MODE)"
    MODE=$MODE NOPS=$NOPS PERIOD=$P ./gen_saif.sh > "out/saif_${MODE}_${P}.log" 2>&1

    echo "### DC   @ ${P}ps keep_hier=$KH"
    CLK_PERIOD=$P KEEP_HIER=$KH \
        SAIF_FILE=$PWD/sim/bf16_add_${MODE}.saif \
        ./run_syn.sh > "out/dc_${tag}.log" 2>&1 || {
            echo "!!! failed: $tag (see out/dc_${tag}.log)"; return 0; }

    local csvf="out/$tag/reports/ppa.csv"
    if [ -s "$CSV" ]; then tail -1 "$csvf" >> "$CSV"; else cat "$csvf" >> "$CSV"; fi
    grep -E "achieved delay|total cell area|TOTAL power|energy / add" \
        "out/$tag/reports/ppa_summary.rpt" | sed "s/^/    /"
}

for p in $HIER_PERIODS; do run_point "$p" 1; done
for p in $FLAT_PERIODS; do run_point "$p" 0; done

echo
echo ">>> sweep CSV: $CSV"
