#!/usr/bin/env bash
# ============================================================================
#  gen_saif.sh -- switching activity for realistic BF16 adder power numbers
#
#  Runs tb_bf16_add with +saif (20k back-to-back random adds through
#  bf16_adder, DUT subtree only, reset excluded), then converts the VCD to
#  SAIF with Synopsys vcd2saif.
#
#    source libs/env_synopsys.sh
#    ./gen_saif.sh                  # VCS (default on this machine)
#    SIM=iverilog ./gen_saif.sh
#
#  Then feed it to synthesis:
#    SAIF_FILE=$PWD/sim/bf16_adder.saif ./run_syn.sh
#
#  Without a SAIF, syn_dc.tcl falls back to a 0.25 toggle-rate estimate and
#  labels the summary "estimated".
# ============================================================================
set -e
cd "$(dirname "$0")"

SIM=${SIM:-vcs}
SIMDIR=${SIMDIR:-./sim}
NOPS=${NOPS:-20000}

#  DUT selects the workload:
#    bf16_adder         -- the plain adder            (tb_bf16_add)
#    bf16_addsub_fused  -- fused add/subtract unit    (tb_bf16_addsub)
#    bf16_addsub_2x     -- two-adder baseline         (tb_bf16_addsub)
DUT=${DUT:-bf16_adder}

RTL_COMMON="../rtl/bf16_add.v ../rtl/bf16_adder.v"
RTL_AS="$RTL_COMMON ../rtl/bf16_addsub_fused.v ../rtl/bf16_addsub_2x.v \
../rtl/bf16_addsub_unit.v"

case "$DUT" in
  bf16_adder)
      RTL="$RTL_COMMON"; TB="../tb/tb_bf16_add.v"; TOP_TB=tb_bf16_add
      RUNARGS="+saif +nops=$NOPS"; INST="${TOP_TB}/dut" ;;
  bf16_addsub_fused)
      RTL="$RTL_AS"; TB="../tb/tb_bf16_addsub.v"; TOP_TB=tb_bf16_addsub
      RUNARGS="+saif +dut=fused +nops=$NOPS"; INST="${TOP_TB}/dut_u_fused" ;;
  bf16_addsub_2x)
      RTL="$RTL_AS"; TB="../tb/tb_bf16_addsub.v"; TOP_TB=tb_bf16_addsub
      RUNARGS="+saif +dut=2x +nops=$NOPS"; INST="${TOP_TB}/dut_u_2x" ;;
  *)
      echo "ERROR: unknown DUT='$DUT'"; exit 1 ;;
esac
DUT_PATH=${DUT_PATH:-$INST}

mkdir -p "$SIMDIR"

echo ">>> simulating $DUT with $SIM ($RUNARGS)"
case "$SIM" in
  vcs)
      vcs -full64 -sverilog -notice +v2k +incdir+../tb \
          -o "$SIMDIR/simv_$DUT" -top $TOP_TB $RTL $TB \
          -l "$SIMDIR/vcs_compile_$DUT.log"
      ( cd "$SIMDIR" && "./simv_$DUT" $RUNARGS -l "vcs_run_$DUT.log" )
      ;;
  iverilog)
      ${IVERILOG:-iverilog} -g2005 -I../tb -o "$SIMDIR/$DUT.vvp" -s $TOP_TB $RTL $TB
      ( cd "$SIMDIR" && ${VVP:-vvp} "$DUT.vvp" $RUNARGS )
      ;;
  *)
      echo "ERROR: unknown SIM='$SIM' (expected vcs or iverilog)"; exit 1 ;;
esac

VCD="$SIMDIR/$DUT.vcd"
SAIF="$SIMDIR/$DUT.saif"

if [ ! -s "$VCD" ]; then
    echo "ERROR: $VCD was not produced"
    exit 1
fi
echo ">>> VCD: $VCD  ($(du -h "$VCD" | cut -f1))"

if ! command -v vcd2saif >/dev/null 2>&1; then
    cat <<EOF

WARNING: 'vcd2saif' not found in PATH.
         It ships with Design Compiler -- source libs/env_synopsys.sh and
         re-run, or convert the VCD yourself:

             vcd2saif -input $VCD -output $SAIF -instance $DUT_PATH

EOF
    exit 0
fi

echo ">>> vcd2saif -instance $DUT_PATH"
vcd2saif -input "$VCD" -output "$SAIF" -instance "$DUT_PATH"

echo
echo ">>> SAIF written: $SAIF"
echo ">>> now run:  SAIF_FILE=\$PWD/${SAIF#./} ./run_syn.sh"
