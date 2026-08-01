#!/usr/bin/env bash
# ============================================================================
#  gen_saif.sh -- switching activity for the single-path BF16 adder
#
#    source libs/env_synopsys.sh
#    ./gen_saif.sh                  # mode=near   (default)
#    MODE=uniform ./gen_saif.sh
#
#  Then:  SAIF_FILE=$PWD/sim/bf16_add_near.saif ./run_syn.sh
#
#  Without a SAIF, syn_dc.tcl falls back to a 0.25 toggle-rate estimate and
#  labels the summary "estimated".
# ============================================================================
set -e
cd "$(dirname "$0")"

SIM=${SIM:-iverilog}
SIMDIR=${SIMDIR:-./sim}
NOPS=${NOPS:-20000}
MODE=${MODE:-near}
PERIOD=${PERIOD:-650}

RTL="../src/adder.sv"
TB="tb_power.v"
INST="tb_power/dut"
TAG="bf16_add_${MODE}"

mkdir -p "$SIMDIR"

echo ">>> simulating: mode=$MODE nops=$NOPS period=${PERIOD}ps"
case "$SIM" in
  iverilog)
      ${IVERILOG:-iverilog} -g2012 -o "$SIMDIR/$TAG.vvp" -s tb_power $RTL $TB
      ( cd "$SIMDIR" && ${VVP:-vvp} "$TAG.vvp" \
            +mode=$MODE +nops=$NOPS +period=$PERIOD )
      ;;
  vcs)
      vcs -full64 -sverilog -notice +v2k -o "$SIMDIR/simv_$TAG" -top tb_power \
          $RTL $TB -l "$SIMDIR/vcs_compile_$TAG.log"
      ( cd "$SIMDIR" && "./simv_$TAG" +mode=$MODE +nops=$NOPS +period=$PERIOD \
            -l "vcs_run_$TAG.log" )
      ;;
  *)  echo "ERROR: unknown SIM='$SIM'"; exit 1 ;;
esac

VCD="$SIMDIR/bf16_add.vcd"
SAIF="$SIMDIR/$TAG.saif"

[ -s "$VCD" ] || { echo "ERROR: $VCD not produced"; exit 1; }
echo ">>> VCD: $VCD  ($(du -h "$VCD" | cut -f1))"

command -v vcd2saif >/dev/null 2>&1 || {
    echo "ERROR: vcd2saif not in PATH - source libs/env_synopsys.sh"; exit 1; }

vcd2saif -input "$VCD" -output "$SAIF" -instance "$INST"
mv -f "$VCD" "$SIMDIR/$TAG.vcd"

echo
echo ">>> SAIF written: $SAIF"
echo ">>> now run:  SAIF_FILE=\$PWD/${SAIF#./} ./run_syn.sh"
