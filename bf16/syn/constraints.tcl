# ============================================================================
#  constraints.tcl -- timing / DRC constraints for the BF16 adder.
#  Sourced by syn_dc.tcl after elaborate+link.  Uses variables from setup.tcl.
#
#  Works for both shapes of the design:
#    * with registers (PIPE >= 1, or any design that has a clk port)
#         -> real clock, input/output delays, reg-to-reg path is constrained
#    * purely combinational (bf16_add, or bf16_adder with PIPE=0)
#         -> virtual clock + set_max_delay across the whole block
# ============================================================================

set HAS_CLK [expr {[sizeof_collection [get_ports $CLK_PORT -quiet]] > 0}]

if {$HAS_CLK} {
    puts "\n>>> constraining $TOP at ${CLK_PERIOD} ${TIME_UNIT}"
    create_clock -name $CLK_NAME -period $CLK_PERIOD [get_ports $CLK_PORT]
    set_clock_latency     $CLK_LATENCY [get_clocks $CLK_NAME]
    set_clock_uncertainty $CLK_UNCERT  [get_clocks $CLK_NAME]
    set_clock_transition  $CLK_TRAN    [get_clocks $CLK_NAME]
    set_dont_touch_network             [get_clocks $CLK_NAME]
    set all_in_except_clk [remove_from_collection [all_inputs] [get_ports $CLK_PORT]]
} else {
    puts "\n>>> $TOP is combinational - virtual clock + max_delay ${CLK_PERIOD} ${TIME_UNIT}"
    create_clock -name $CLK_NAME -period $CLK_PERIOD
    set all_in_except_clk [all_inputs]
}

# ---------------------------------------------------------------------------
#  Reset : async, active low, ideal network
# ---------------------------------------------------------------------------
if {[sizeof_collection [get_ports rst_n -quiet]] > 0} {
    set_ideal_network [get_ports rst_n]
    if {$RST_FALSE_PATH} { set_false_path -from [get_ports rst_n] }
    set all_in_except_clk [remove_from_collection $all_in_except_clk [get_ports rst_n]]
}

# ---------------------------------------------------------------------------
#  IO timing
# ---------------------------------------------------------------------------
set_input_delay  -clock $CLK_NAME [expr {$IN_DELAY_F  * $CLK_PERIOD}] $all_in_except_clk
set_output_delay -clock $CLK_NAME [expr {$OUT_DELAY_F * $CLK_PERIOD}] [all_outputs]

if {!$HAS_CLK} {
    # Nothing is registered, so the only real requirement is that the whole
    # adder fits inside one period minus the IO budget.
    set_max_delay [expr {(1.0 - $IN_DELAY_F - $OUT_DELAY_F) * $CLK_PERIOD}] \
        -from $all_in_except_clk -to [all_outputs]
}

# ---------------------------------------------------------------------------
#  IO drive / load
# ---------------------------------------------------------------------------
if {[string length $DRIVE_CELL] > 0} {
    set_driving_cell -lib_cell $DRIVE_CELL -pin $DRIVE_PIN $all_in_except_clk
} else {
    puts ">>> DRIVE_CELL not set - using set_input_transition $IN_TRAN"
    set_input_transition $IN_TRAN $all_in_except_clk
}

if {[string length $LOAD_CELL] > 0} {
    set pin_cap [load_of [get_lib_pins */$LOAD_CELL/$LOAD_PIN]]
    set_load [expr {$LOAD_FANOUT * $pin_cap}] [all_outputs]
    puts ">>> output load = $LOAD_FANOUT x $LOAD_CELL/$LOAD_PIN"
} else {
    puts ">>> LOAD_CELL not set - using set_load $OUT_LOAD"
    set_load $OUT_LOAD [all_outputs]
}

# ---------------------------------------------------------------------------
#  Design rules + area goal
# ---------------------------------------------------------------------------
set_max_fanout     $MAX_FANOUT [current_design]
set_max_transition $MAX_TRAN   [current_design]
set_max_area       0

if {[string length $WIRE_LOAD] > 0 && !$TOPO_MODE} {
    set_wire_load_model -name $WIRE_LOAD
    set_wire_load_mode  top
}

# ---------------------------------------------------------------------------
#  Clock gating style.  There is little to gate in a 2-stage wrapper, but the
#  vld_in tag makes the operand registers gateable when traffic is bursty.
# ---------------------------------------------------------------------------
#  ASAP7 ships no integrated clock-gating cell, so probe the library first and
#  fall back to a discrete latch+AND gate instead of erroring out (PWR-191).
if {$GATE_CLOCK && $HAS_CLK} {
    set icg [get_lib_cells * -filter "clock_gating_integrated_cell != \"\"" -quiet]
    if {[sizeof_collection $icg] > 0} {
        puts ">>> clock gating: integrated cells ([sizeof_collection $icg] found)"
        set_clock_gating_style                \
            -sequential_cell latch            \
            -positive_edge_logic {integrated} \
            -control_point before             \
            -control_signal scan_enable       \
            -max_fanout 32                    \
            -minimum_bitwidth 4
    } else {
        puts ">>> clock gating: no integrated cell in this library - using discrete latch"
        set_clock_gating_style       \
            -sequential_cell latch   \
            -control_point before    \
            -control_signal scan_enable \
            -max_fanout 32           \
            -minimum_bitwidth 4
    }
}
