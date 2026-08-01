#!/usr/bin/env bash
# ============================================================================
#  run_syn.sh -- one Design Compiler run for the single-path BF16 adder
#
#    source libs/env_synopsys.sh
#    source libs/asap7.sh
#    ./run_syn.sh                                  # hier-preserved, breakdown
#    KEEP_HIER=0 ./run_syn.sh                      # flattened, best PPA
#    CLK_PERIOD=700 ./run_syn.sh
#    SAIF_FILE=$PWD/sim/bf16_add_near.saif ./run_syn.sh
# ============================================================================
set -e
cd "$(dirname "$0")"

DC_SHELL=${DC_SHELL:-dc_shell}
TOP=${TOP:-bf16_add}
CLK_PERIOD=${CLK_PERIOD:-4000}
TIME_UNIT=${TIME_UNIT:-ps}
KEEP_HIER=${KEEP_HIER:-1}
_h=$([ "$KEEP_HIER" = "1" ] && echo hier || echo flat)
RUN_TAG=${RUN_TAG:-${TOP}_${_h}_${CLK_PERIOD}${TIME_UNIT}}
OUT_DIR=${OUT_DIR:-./out/$RUN_TAG}

export TOP CLK_PERIOD TIME_UNIT KEEP_HIER RUN_TAG OUT_DIR

if ! command -v "$DC_SHELL" >/dev/null 2>&1; then
    echo "ERROR: '$DC_SHELL' not found. source libs/env_synopsys.sh first."
    exit 1
fi

mkdir -p "$OUT_DIR/logs"

DC_ARGS=()
[ "${TOPO_MODE:-0}" = "1" ] && DC_ARGS+=(-topographical_mode)

echo "=================================================="
echo " DC run : TOP=$TOP period=${CLK_PERIOD}${TIME_UNIT} keep_hier=$KEEP_HIER"
echo "          saif=${SAIF_FILE:-<none>}"
echo "          out=$OUT_DIR"
echo "=================================================="

"$DC_SHELL" "${DC_ARGS[@]}" -f syn_dc.tcl | tee "$OUT_DIR/logs/dc.log"

if [ ! -f "$OUT_DIR/reports/ppa_summary.rpt" ]; then
    echo "ERROR: no PPA summary produced - see $OUT_DIR/logs/dc.log"
    exit 1
fi

echo
cat "$OUT_DIR/reports/ppa_summary.rpt"
echo " full reports: $OUT_DIR/reports"
