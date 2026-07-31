#!/usr/bin/env bash
# ============================================================================
#  sweep_fht.sh -- area corner + delay floor for the 16-point FHT variants.
#
#    source libs/env_synopsys.sh && source libs/asap7.sh && ./sweep_fht.sh
#
#  Area corner: a period every variant meets with slack, so DC is optimising
#  area for all of them and the comparison is not contaminated by timing
#  effort.  Delay points: pushed down until DC stops improving, which is the
#  variant's own input-to-output floor.
# ============================================================================
set -e
cd "$(dirname "$0")"

RTL="../rtl/bf16_add.v ../rtl/bf16_addsub_fused.v ../rtl/bf16_addsub_2x.v \
../rtl/fht/fht16_bf16.v ../rtl/fht/fht16_bfp.v ../rtl/fht/bfp_to_bf16.v"

run () {  # run <tag> <top> <params> <period>
    RTL_FILES="$RTL" TOP="$2" PARAMS="$3" RUN_TAG="$1" \
    CLK_PERIOD="$4" IN_DELAY_F=0 OUT_DELAY_F=0 \
        ./run_syn.sh > "logs_$1.txt" 2>&1 &
}

FL_F="fht16_bf16 FUSED=1"
FL_2="fht16_bf16 FUSED=0"
BP16="fht16_bfp W=16,G=4,PACK=0"
BP23="fht16_bfp W=23,G=4,PACK=0"
BP16P="fht16_bfp W=16,G=4,PACK=1"

echo "=== area corner: 8000 ps (everything has slack) ==="
run area8k_float_fused $FL_F  8000
run area8k_float_2x    $FL_2  8000
wait
run area8k_bfp_w16     $BP16  8000
run area8k_bfp_w23     $BP23  8000
run area8k_bfp_w16_pack $BP16P 8000
wait

echo "=== delay floor: float trees ==="
for p in 3200 2800 2500; do
    run dly_float_fused_$p $FL_F $p
    run dly_float_2x_$p    $FL_2 $p
    wait
done

echo "=== delay floor: BFP ==="
for p in 1600 1200 900; do
    run dly_bfp_w16_$p $BP16 $p
    run dly_bfp_w23_$p $BP23 $p
    run dly_bfp_w16_pack_$p $BP16P $p
    wait
done

python3 collect_ppa.py out
echo "done"
