#!/usr/bin/env bash
# ============================================================================
#  run_fht.sh -- PPA for the 16-point FHT variants.
#
#    source libs/env_synopsys.sh
#    source libs/asap7.sh
#    ./run_fht.sh area          # area corner, all 5 variants
#    ./run_fht.sh delay <ps>    # one tight-period point, all 5 variants
#
#  Combinational tops -> constraints.tcl switches to a virtual clock and
#  set_max_delay automatically, so "achieved" is the transform's own
#  input-to-output delay.
# ============================================================================
set -e
cd "$(dirname "$0")"

MODE=${1:-area}
PER=${2:-4000}
SUF=${3:-}

RTL="../rtl/bf16_add.v ../rtl/bf16_addsub_fused.v ../rtl/bf16_addsub_2x.v \
../rtl/fht/fht16_bf16.v ../rtl/fht/fht16_bfp.v ../rtl/fht/bfp_to_bf16.v"

run () {  # run <tag> <top> <params>
    echo ">>> $1  (period $PER)"
    RTL_FILES="$RTL" TOP="$2" PARAMS="$3" RUN_TAG="$1" \
    CLK_PERIOD="$PER" IN_DELAY_F=0 OUT_DELAY_F=0 \
        ./run_syn.sh > "logs_$1.txt" 2>&1 &
}

mkdir -p out

if [ "$MODE" = "area" ]; then PER=4000; fi

run "fht16_float_fused$SUF" fht16_bf16 "FUSED=1"
run "fht16_float_2x$SUF"    fht16_bf16 "FUSED=0"
wait
run "fht16_bfp_w16$SUF"     fht16_bfp  "W=16,G=4,PACK=0"
run "fht16_bfp_w23$SUF"     fht16_bfp  "W=23,G=4,PACK=0"
run "fht16_bfp_w16_pack$SUF" fht16_bfp "W=16,G=4,PACK=1"
wait

python3 collect_ppa.py out
echo "done"
