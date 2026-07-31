# ============================================================================
#  setup.tcl -- the ONE file you normally need to edit for the BF16 adder run.
#
#  Every variable can also be overridden from the environment, e.g.
#
#     setenv CLK_PERIOD 300 ; ./run_syn.sh                (tcsh)
#     CLK_PERIOD=300 PARAM_PIPE=2 ./run_syn.sh            (bash)
# ============================================================================

proc envdef {name default} {
    global env
    if {[info exists env($name)] && [string length $env($name)] > 0} {
        return $env($name)
    }
    return $default
}

# ============================================================================
#  1. Technology library
# ============================================================================
# Ready-made configs live in libs/ -- source one before running:
#     source libs/asap7.sh   (bash)
set LIB_PATH   [envdef LIB_PATH   "/path/to/your/std_cell/db"]
set TARGET_DB  [envdef TARGET_DB  "your_stdcell.db"]
set EXTRA_DB   [envdef EXTRA_DB   ""]
set SYMBOL_LIB [envdef SYMBOL_LIB ""]
set DONT_USE   [envdef DONT_USE   ""]

# TIME_UNIT    : library time unit -- "ns" or "ps".  CLK_PERIOD is in it.
# AREA_DIVISOR : ASAP7 is drawn at 4x linear scale -> divide raw area by 16.
set TIME_UNIT    [envdef TIME_UNIT    "ns"]
set AREA_DIVISOR [envdef AREA_DIVISOR 1.0]
set AREA_UNIT    [envdef AREA_UNIT    "um^2"]

set DRIVE_CELL  [envdef DRIVE_CELL  ""]
set DRIVE_PIN   [envdef DRIVE_PIN   "Z"]
set LOAD_CELL   [envdef LOAD_CELL   ""]
set LOAD_PIN    [envdef LOAD_PIN    "I"]
set LOAD_FANOUT [envdef LOAD_FANOUT 8]
set WIRE_LOAD   [envdef WIRE_LOAD   ""]

# ============================================================================
#  2. Design
# ============================================================================
#   bf16_adder       : registered adder wrapper
#   bf16_addsub_unit : registered add/subtract wrapper, PARAM_FUSED selects
#                      the fused core (1) or the two-adder baseline (0)
#   bf16_add         : the bare combinational adder (no clk port -- handled
#                      automatically, see constraints.tcl)
set TOP     [envdef TOP     "bf16_adder"]
set RTL_DIR [envdef RTL_DIR "../rtl"]
# Override RTL_FILES from the environment (space-separated paths) to synthesise
# something else with this flow, e.g. a stage probe.
set RTL_FILES [envdef RTL_FILES [list    \
    $RTL_DIR/bf16_add.v                  \
    $RTL_DIR/bf16_adder.v                \
    $RTL_DIR/bf16_addsub_fused.v         \
    $RTL_DIR/bf16_addsub_2x.v            \
    $RTL_DIR/bf16_addsub_unit.v          \
]]

# PIPE 0 = pure combinational, 1 = output registers, 2 = input+output
# registers (default: gives a clean reg-to-reg path around the adder).
set PARAM_PIPE  [envdef PARAM_PIPE  2]
# bf16_addsub_unit only: 1 = fused core, 0 = two independent bf16_add
set PARAM_FUSED [envdef PARAM_FUSED 1]
# Generic parameter override for any other top, e.g. PARAMS="W=16,PACK=0".
# Passed straight to elaborate -parameters when non-empty.
set PARAMS      [envdef PARAMS      ""]

# Results per cycle.  Both add/sub units emit a sum AND a difference every
# cycle, so energy is reported per result in both cases.
switch -- $TOP {
    bf16_addsub_unit { set _ops_default 2 }
    default          { set _ops_default 1 }
}
set OPS_PER_CYCLE [envdef OPS_PER_CYCLE $_ops_default]

# Sub-design whose area is broken out in the summary ("core" column).
switch -- $TOP {
    bf16_adder       { set _core_default "bf16_add" }
    bf16_addsub_unit { set _core_default \
                         [expr {$PARAM_FUSED ? "bf16_addsub_fused" : "bf16_addsub_2x"}] }
    default          { set _core_default $TOP }
}
set CORE_PATTERN [envdef CORE_PATTERN $_core_default]

# ============================================================================
#  3. Constraints
# ============================================================================
set CLK_PERIOD  [envdef CLK_PERIOD 4.0]
set CLK_NAME    "clk"
set CLK_PORT    "clk"

set CLK_UNCERT  [envdef CLK_UNCERT  [expr {0.05 * $CLK_PERIOD}]]
set CLK_LATENCY [envdef CLK_LATENCY [expr {0.10 * $CLK_PERIOD}]]
set CLK_TRAN    [envdef CLK_TRAN    0.05]

set IN_DELAY_F  [envdef IN_DELAY_F  0.30]
set OUT_DELAY_F [envdef OUT_DELAY_F 0.30]

set IN_TRAN     [envdef IN_TRAN     0.05]
set OUT_LOAD    [envdef OUT_LOAD    0.02]

set MAX_FANOUT  [envdef MAX_FANOUT  16]
set MAX_TRAN    [envdef MAX_TRAN    [expr {0.10 * $CLK_PERIOD}]]

set RST_FALSE_PATH [envdef RST_FALSE_PATH 1]

# ============================================================================
#  4. Flow options
# ============================================================================
set COMPILE_ULTRA [envdef COMPILE_ULTRA 1]
set GATE_CLOCK    [envdef GATE_CLOCK    1]
set KEEP_HIER     [envdef KEEP_HIER     1]
set RETIME        [envdef RETIME        0]
set TOPO_MODE     [envdef TOPO_MODE     0]
set INCR_COMPILE  [envdef INCR_COMPILE  1]

set SAIF_FILE [envdef SAIF_FILE ""]
switch -- $TOP {
    bf16_addsub_unit { set _saif_inst_default \
                         [expr {$PARAM_FUSED ? "tb_bf16_addsub/dut_u_fused"
                                             : "tb_bf16_addsub/dut_u_2x"}] }
    default          { set _saif_inst_default "tb_bf16_add/dut" }
}
set SAIF_INSTANCE [envdef SAIF_INSTANCE $_saif_inst_default]

switch -- $TOP {
    bf16_addsub_unit { set _tag_default \
        "${TOP}_[expr {$PARAM_FUSED ? {fused} : {2x}}]_${CLK_PERIOD}${TIME_UNIT}" }
    default          { set _tag_default "${TOP}_p${PARAM_PIPE}_${CLK_PERIOD}${TIME_UNIT}" }
}
set RUN_TAG [envdef RUN_TAG $_tag_default]
set OUT_DIR [envdef OUT_DIR "./out/$RUN_TAG"]
set RPT_DIR "$OUT_DIR/reports"
set NET_DIR "$OUT_DIR/netlist"
set LOG_DIR "$OUT_DIR/logs"
