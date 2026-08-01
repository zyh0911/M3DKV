# ============================================================================
#  setup.tcl -- configuration for the single-path BF16 adder (../src/adder.sv)
#
#  Every variable can be overridden from the environment:
#
#     source libs/env_synopsys.sh
#     source libs/asap7.sh
#     CLK_PERIOD=700 ./run_syn.sh
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
set LIB_PATH   [envdef LIB_PATH   "/path/to/your/std_cell/db"]
set TARGET_DB  [envdef TARGET_DB  "your_stdcell.db"]
set EXTRA_DB   [envdef EXTRA_DB   ""]
set SYMBOL_LIB [envdef SYMBOL_LIB ""]
set DONT_USE   [envdef DONT_USE   ""]

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
#  bf16_add is purely combinational: no clk port, constraints.tcl switches to
#  a virtual clock + set_max_delay automatically.
set TOP     [envdef TOP     "bf16_add"]
set RTL_DIR [envdef RTL_DIR "../src"]
set RTL_FILES [envdef RTL_FILES [list $RTL_DIR/adder.sv]]
set RTL_FORMAT [envdef RTL_FORMAT "sverilog"]

# "E=8,M=7" etc.  Empty keeps the RTL defaults (bfloat16) AND keeps the
# elaborated design named $TOP, which makes the reports easier to read.
set PARAMS [envdef PARAMS ""]

set OPS_PER_CYCLE [envdef OPS_PER_CYCLE 1]

# ----------------------------------------------------------------------------
#  The three units whose area / power share we want broken out.  Listed as
#  <instance-name-in-top> ; the design name is looked up from the instance so
#  uniquify renaming does not matter.
# ----------------------------------------------------------------------------
set UNIT_INSTS [envdef UNIT_INSTS [list \
    m_compare_and_select                 \
    m_add_sub_mantissa                   \
    m_normalize_rz                       \
]]

# ============================================================================
#  3. Constraints
# ============================================================================
set CLK_PERIOD  [envdef CLK_PERIOD 4.0]
set CLK_NAME    "clk"
set CLK_PORT    "clk"

set CLK_UNCERT  [envdef CLK_UNCERT  [expr {0.05 * $CLK_PERIOD}]]
set CLK_LATENCY [envdef CLK_LATENCY [expr {0.10 * $CLK_PERIOD}]]
set CLK_TRAN    [envdef CLK_TRAN    0.05]

# For a bare combinational block the whole period IS the arrival-time budget,
# so no IO reservation by default: "achieved period" is then the raw in->out
# delay of the adder under the given drive / load.
set IN_DELAY_F  [envdef IN_DELAY_F  0.0]
set OUT_DELAY_F [envdef OUT_DELAY_F 0.0]

set IN_TRAN     [envdef IN_TRAN     0.05]
set OUT_LOAD    [envdef OUT_LOAD    0.02]

set MAX_FANOUT  [envdef MAX_FANOUT  16]
set MAX_TRAN    [envdef MAX_TRAN    [expr {0.10 * $CLK_PERIOD}]]

set RST_FALSE_PATH [envdef RST_FALSE_PATH 1]

# ============================================================================
#  4. Flow options
# ============================================================================
set COMPILE_ULTRA [envdef COMPILE_ULTRA 1]
set GATE_CLOCK    [envdef GATE_CLOCK    0]
# KEEP_HIER=1 keeps compare_and_select / add_sub_mantissa / normalize_rz as
# real hierarchical cells, which is what makes the per-unit breakdown possible.
# KEEP_HIER=0 lets DC flatten across the boundaries -> better PPA, no breakdown.
set KEEP_HIER     [envdef KEEP_HIER     1]
set RETIME        [envdef RETIME        0]
set TOPO_MODE     [envdef TOPO_MODE     0]
set INCR_COMPILE  [envdef INCR_COMPILE  1]

set SAIF_FILE     [envdef SAIF_FILE     ""]
set SAIF_INSTANCE [envdef SAIF_INSTANCE "tb_power/dut"]

set RUN_TAG [envdef RUN_TAG "${TOP}_[expr {$KEEP_HIER ? {hier} : {flat}}]_${CLK_PERIOD}${TIME_UNIT}"]
set OUT_DIR [envdef OUT_DIR "./out/$RUN_TAG"]
set RPT_DIR "$OUT_DIR/reports"
set NET_DIR "$OUT_DIR/netlist"
set LOG_DIR "$OUT_DIR/logs"
