#!/usr/bin/env bash
# ============================================================================
#  ppa_sweep.sh -- sweep the clock period to get the BF16 adder's
#                  area / power vs. frequency curve, then summarise.
#
#    source libs/env_synopsys.sh ; source libs/asap7.sh
#    ./ppa_sweep.sh                          # default period list
#    ./ppa_sweep.sh 800 600 500 400 300      # explicit periods (library unit)
#    JOBS=4 ./ppa_sweep.sh                   # 4 DC jobs in parallel
#    PARAM_PIPE=1 ./ppa_sweep.sh
# ============================================================================
set -e
cd "$(dirname "$0")"

TOP=${TOP:-bf16_adder}
PARAM_PIPE=${PARAM_PIPE:-2}
JOBS=${JOBS:-1}
TIME_UNIT=${TIME_UNIT:-ns}
SWEEP_TAG=${SWEEP_TAG:-sweep_${TOP}_p${PARAM_PIPE}}

if [ $# -gt 0 ]; then
    PERIODS=("$@")
elif [ "$TIME_UNIT" = "ps" ]; then
    PERIODS=(1000 700 500 400 300 250 200 170 150)
else
    PERIODS=(2.0 1.5 1.0 0.8 0.6 0.5 0.4 0.35 0.3)
fi

echo "=================================================="
echo " PPA sweep : TOP=$TOP PIPE=$PARAM_PIPE"
echo " periods   : ${PERIODS[*]} $TIME_UNIT"
echo " parallel  : $JOBS job(s)"
echo "=================================================="

run_one() {
    local p=$1
    echo ">>> starting period ${p} ${TIME_UNIT}"
    TOP="$TOP" PARAM_PIPE="$PARAM_PIPE" CLK_PERIOD="$p" \
        RUN_TAG="${SWEEP_TAG}/${TOP}_${p}${TIME_UNIT}" \
        OUT_DIR="./out/${SWEEP_TAG}/${TOP}_${p}${TIME_UNIT}" \
        ./run_syn.sh > "/tmp/dcsweep_bf16_${TOP}_${p}.log" 2>&1 \
        && echo ">>> done  period ${p} ${TIME_UNIT}" \
        || echo ">>> FAILED period ${p} ${TIME_UNIT}  (see /tmp/dcsweep_bf16_${TOP}_${p}.log)"
}
export -f run_one
export TOP PARAM_PIPE SWEEP_TAG TIME_UNIT

if [ "$JOBS" -gt 1 ] && command -v xargs >/dev/null 2>&1; then
    printf '%s\n' "${PERIODS[@]}" | xargs -P "$JOBS" -I{} bash -c 'run_one {}'
else
    for p in "${PERIODS[@]}"; do run_one "$p"; done
fi

echo
python3 collect_ppa.py "./out/${SWEEP_TAG}" | tee "./out/${SWEEP_TAG}/ppa_table.txt"
echo
echo "sweep results: ./out/${SWEEP_TAG}/ppa_table.txt  (+ ppa_table.csv)"
