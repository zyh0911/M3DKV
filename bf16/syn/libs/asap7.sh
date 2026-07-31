# ============================================================================
#  libs/asap7.sh -- ASAP7 7nm predictive PDK, RVT / typical corner
#
#     source libs/asap7.sh
#     ./run_syn.sh
#
#  Two things about ASAP7 that this file takes care of:
#
#   1. time_unit is 1 ps (not ns).  CLK_PERIOD is therefore in picoseconds --
#      4000 ps = 4.0 ns = the paper's 250 MHz.  Capacitance is fF.
#
#   2. ASAP7 is DRAWN AT 4x LINEAR SCALE, so every area in the .db is 16x the
#      true silicon area.  AREA_DIVISOR=16 makes the summary report real 7nm
#      um^2; the raw DC number is still printed next to it.
#
#  Note the corner is TT/0.7V/25C (that is what ships as .db).  A worst-case
#  SS corner would be the correct sign-off library -- these numbers are
#  typical-case and therefore optimistic.
# ============================================================================

export LIB_PATH=/usr/local/tools/PDK/ASAP7/asap7libs_24/db

export TARGET_DB="asap7sc7p5t_22b_SIMPLE_RVT_TT_170906.db \
asap7sc7p5t_22b_INVBUF_RVT_TT_170906.db \
asap7sc7p5t_22b_AO_RVT_TT_170906.db \
asap7sc7p5t_22b_OA_RVT_TT_170906.db \
asap7sc7p5t_22b_SEQ_RVT_TT_170906.db"

export TIME_UNIT=ps
export AREA_DIVISOR=16.0
export AREA_UNIT="um^2(7nm)"

# 4000 ps = 4.0 ns = 250 MHz, the paper's operating point
export CLK_PERIOD=${CLK_PERIOD:-4000}

export DRIVE_CELL=BUFx4_ASAP7_75t_R
export DRIVE_PIN=Y
export LOAD_CELL=INVx1_ASAP7_75t_R
export LOAD_PIN=A
export LOAD_FANOUT=8

# No DFT in this project -> keep the scan flops out.  The "f"/HB variants are
# hold-fixing and fast-but-leaky cells that DC should not pick for datapath.
export DONT_USE="*/SDF* */HB?xp67* */*x1p*"

# ps-unit DRC numbers
export IN_TRAN=10
export MAX_TRAN=${MAX_TRAN:-80}
export MAX_FANOUT=16
export CLK_TRAN=10
