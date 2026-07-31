#!/usr/bin/env bash
# ============================================================================
#  run_syn.sh -- single Design Compiler run for the BF16 adder
#
#    source libs/env_synopsys.sh          # dc_shell + licence
#    source libs/asap7.sh                 # technology (or your own libs/*.sh)
#    ./run_syn.sh                         # defaults from setup.tcl
#
#    CLK_PERIOD=300 ./run_syn.sh                  # override anything
#    TOP=bf16_add PARAM_PIPE=0 ./run_syn.sh       # bare combinational adder
#    SAIF_FILE=$PWD/sim/bf16_adder.saif ./run_syn.sh
#
#  Everything in setup.tcl can be overridden through the environment.
# ============================================================================
set -e
cd "$(dirname "$0")"

DC_SHELL=${DC_SHELL:-dc_shell}
TOP=${TOP:-bf16_adder}
PARAM_PIPE=${PARAM_PIPE:-2}
PARAM_FUSED=${PARAM_FUSED:-1}
CLK_PERIOD=${CLK_PERIOD:-4.0}
TIME_UNIT=${TIME_UNIT:-ns}
if [ "$TOP" = "bf16_addsub_unit" ]; then
    _variant=$([ "$PARAM_FUSED" = "1" ] && echo fused || echo 2x)
    RUN_TAG=${RUN_TAG:-${TOP}_${_variant}_${CLK_PERIOD}${TIME_UNIT}}
else
    RUN_TAG=${RUN_TAG:-${TOP}_p${PARAM_PIPE}_${CLK_PERIOD}${TIME_UNIT}}
fi
OUT_DIR=${OUT_DIR:-./out/$RUN_TAG}

export TOP PARAM_PIPE PARAM_FUSED CLK_PERIOD TIME_UNIT RUN_TAG OUT_DIR

if ! command -v "$DC_SHELL" >/dev/null 2>&1; then
    echo "ERROR: '$DC_SHELL' not found in PATH."
    echo "       source libs/env_synopsys.sh first, or set DC_SHELL=/path/to/dc_shell."
    exit 1
fi

mkdir -p "$OUT_DIR/logs"

DC_ARGS=()
if [ "${TOPO_MODE:-0}" = "1" ]; then
    DC_ARGS+=(-topographical_mode)
fi

echo "=================================================="
echo " DC run : TOP=$TOP PIPE=$PARAM_PIPE period=${CLK_PERIOD}${TIME_UNIT}"
echo "          out=$OUT_DIR"
echo "=================================================="

"$DC_SHELL" "${DC_ARGS[@]}" -f syn_dc.tcl \
    | tee "$OUT_DIR/logs/dc.log"

# dc_shell always exits 0; treat a missing summary as failure
if [ ! -f "$OUT_DIR/reports/ppa_summary.rpt" ]; then
    echo "ERROR: synthesis did not produce a PPA summary - see $OUT_DIR/logs/dc.log"
    exit 1
fi

echo
echo "=================================================="
cat "$OUT_DIR/reports/ppa_summary.rpt"
echo " full reports: $OUT_DIR/reports"
echo "=================================================="
