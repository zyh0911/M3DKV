# ============================================================================
#  syn_dc.tcl -- Synopsys Design Compiler synthesis + PPA extraction for the
#                BF16 adder.
#
#     dc_shell -f syn_dc.tcl | tee dc.log
#
#  Normally driven by ./run_syn.sh.  All configuration lives in setup.tcl;
#  timing/DRC constraints live in constraints.tcl.
# ============================================================================

source setup.tcl

file mkdir $OUT_DIR $RPT_DIR $NET_DIR $LOG_DIR "$OUT_DIR/work"

# ============================================================================
#  Libraries
# ============================================================================
set search_path [concat $search_path $LIB_PATH $RTL_DIR]

foreach db $TARGET_DB {
    if {![file exists [file join $LIB_PATH $db]] && ![file exists $db]} {
        puts "ERROR: target library not found: [file join $LIB_PATH $db]"
        puts "       Set LIB_PATH / TARGET_DB in setup.tcl or source a libs/*.sh."
        exit 1
    }
}
puts ">>> target library: $TARGET_DB"

set target_library    $TARGET_DB
set link_library      [concat "*" $TARGET_DB $EXTRA_DB dw_foundation.sldb]
set synthetic_library [list dw_foundation.sldb]
if {[string length $SYMBOL_LIB] > 0} { set symbol_library $SYMBOL_LIB }

define_design_lib WORK -path "$OUT_DIR/work"

catch { set_app_var verilogout_no_tri                 true  }
catch { set_app_var sh_enable_page_mode               false }
catch { set_app_var timing_report_unconstrained_paths true  }
catch { set_app_var bus_naming_style                  "%s\[%d\]" }
catch { set_app_var alib_library_analysis_path        $OUT_DIR }

# ============================================================================
#  Read + elaborate
# ============================================================================
puts "\n>>> analyze"
foreach f $RTL_FILES {
    if {![file exists $f]} { puts "ERROR: missing RTL file $f"; exit 1 }
    analyze -format verilog -lib WORK $f
}

puts "\n>>> elaborate $TOP (PIPE=$PARAM_PIPE, FUSED=$PARAM_FUSED)"
switch -- $TOP {
    bf16_adder {
        elaborate $TOP -library WORK -parameters "PIPE=$PARAM_PIPE"
    }
    bf16_addsub_unit {
        elaborate $TOP -library WORK \
            -parameters "FUSED=$PARAM_FUSED,PIPE=$PARAM_PIPE"
    }
    default {
        if {$PARAMS ne ""} {
            elaborate $TOP -library WORK -parameters "$PARAMS"
        } else {
            elaborate $TOP -library WORK
        }
    }
}

# elaborate with -parameters renames the design (bf16_adder -> bf16_adder_PIPE2),
# so keep the real name around instead of assuming $TOP.
if {[catch {current_design $TOP}]} {
    puts ">>> elaborated design is [get_object_name [current_design]]"
}
link
uniquify -force
set TOPD [get_object_name [current_design]]

foreach pat $DONT_USE {
    if {[catch {
        set c [get_lib_cells $pat -quiet]
        if {[sizeof_collection $c] > 0} {
            set_dont_use $c
            puts ">>> dont_use: $pat  ([sizeof_collection $c] cells)"
        } else {
            puts ">>> dont_use: $pat  (no match, skipped)"
        }
    } m]} { puts ">>> dont_use $pat failed: $m" }
}

redirect -file $RPT_DIR/check_design.rpt { catch { check_design } }

# ============================================================================
#  Constraints
# ============================================================================
source constraints.tcl

redirect -file $RPT_DIR/check_timing.rpt    { catch { check_timing } }
redirect -file $RPT_DIR/constraints_pre.rpt { catch { report_constraint -all_violators } }
write -format ddc -hierarchy -output $NET_DIR/${TOP}.elab.ddc

# ============================================================================
#  Compile
# ============================================================================
set compile_opts [list]
if {$GATE_CLOCK} { lappend compile_opts -gate_clock }
if {$RETIME}     { lappend compile_opts -retime }
if {$KEEP_HIER}  { lappend compile_opts -no_autoungroup }

puts "\n>>> compile  (ultra=$COMPILE_ULTRA  opts: $compile_opts)"
if {$COMPILE_ULTRA} {
    if {[catch {eval compile_ultra $compile_opts} msg]} {
        puts ">>> compile_ultra failed ($msg) -- falling back to plain compile"
        set COMPILE_ULTRA 0
    }
}
if {!$COMPILE_ULTRA} {
    set c2 [list -map_effort high -area_effort high]
    if {$GATE_CLOCK} { lappend c2 -gate_clock }
    if {$RETIME}     { lappend c2 -retime }
    eval compile $c2
}

if {$INCR_COMPILE} {
    puts "\n>>> incremental compile"
    if {$COMPILE_ULTRA} {
        set ci [list -incremental]
        if {$GATE_CLOCK} { lappend ci -gate_clock }
        catch { eval compile_ultra $ci }
    } else {
        catch { compile -incremental_mapping -map_effort high }
    }
}

# ============================================================================
#  Netlist outputs
# ============================================================================
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output $NET_DIR/${TOP}.syn.v
write -format ddc     -hierarchy -output $NET_DIR/${TOP}.syn.ddc
catch { write_sdf $NET_DIR/${TOP}.syn.sdf }
catch { write_sdc $NET_DIR/${TOP}.syn.sdc }

# ============================================================================
#  Switching activity for power
# ============================================================================
set saif_ok 0
if {[string length $SAIF_FILE] > 0 && [file exists $SAIF_FILE]} {
    puts "\n>>> read_saif $SAIF_FILE (instance $SAIF_INSTANCE)"
    catch { reset_switching_activity }
    if {[catch {read_saif -input $SAIF_FILE -instance_name $SAIF_INSTANCE \
                          -auto_map_names} msg]} {
        puts ">>> read_saif failed: $msg  -- falling back to default activity"
    } else {
        set saif_ok 1
        redirect -file $RPT_DIR/saif_annotation.rpt { catch { report_saif -hier -missing } }
    }
}
if {!$saif_ok} {
    puts "\n>>> no SAIF - using estimated activity (toggle_rate 0.25 on inputs)"
    catch {
        set_switching_activity -toggle_rate 0.25 -static_probability 0.5 \
            -base_clock [get_clocks $CLK_NAME] -type inputs
    }
}

# ============================================================================
#  Reports
# ============================================================================
puts "\n>>> reports -> $RPT_DIR"

proc rpt {file body} {
    global RPT_DIR
    redirect -file $RPT_DIR/$file { if {[catch {uplevel 1 $body} m]} { puts "SKIPPED: $m" } }
}

rpt area.rpt         { report_area }
rpt area_hier.rpt    { report_area -hierarchy -nosplit }
rpt qor.rpt          { report_qor }
rpt reference.rpt    { report_reference -hierarchy -nosplit }
rpt resources.rpt    { report_resources -hierarchy }
rpt constraints.rpt  { report_constraint -all_violators -nosplit }
rpt clock_gating.rpt { report_clock_gating -verbose }
rpt timing_max.rpt   { report_timing -delay_type max -max_paths 20 -nworst 5 \
                         -significant_digits 4 -transition_time -capacitance -nosplit }
rpt timing_min.rpt   { report_timing -delay_type min -max_paths 10 -nworst 3 \
                         -significant_digits 4 -nosplit }
rpt power.rpt        { report_power -analysis_effort high -nosplit }
rpt power_hier.rpt   { report_power -analysis_effort high -hierarchy -levels 3 -nosplit }
rpt power_groups.rpt { report_power -analysis_effort high \
                         -groups {clock_network register combinational sequential} -nosplit }

# ============================================================================
#  PPA summary
# ============================================================================
proc _grab {text pattern {dflt "n/a"}} {
    if {[regexp -line $pattern $text -> v]} { return $v }
    return $dflt
}
proc _to_mW {val unit} {
    array set s {W 1e3 mW 1.0 uW 1e-3 nW 1e-6 pW 1e-9 uW/MHz 1e-3}
    if {[info exists s($unit)]} { return [expr {$val * $s($unit)}] }
    return $val
}
set TU_SEC [expr {$TIME_UNIT eq "ps" ? 1e-12 : 1e-9}]
proc _mhz {period tu} { return [expr {1.0 / ($period * $tu) / 1e6}] }
proc _ascale {v div} {
    if {[string is double -strict $v]} { return [format %.3f [expr {$v / $div}]] }
    return $v
}

set ppa(00_top)       $TOP
set ppa(01_pipe)      $PARAM_PIPE
set ppa(02_fused)     [expr {$TOP eq "bf16_addsub_unit" ? $PARAM_FUSED : "-"}]
set ppa(03_period)    $CLK_PERIOD
set ppa(04_freq_mhz)  [format %.2f [_mhz $CLK_PERIOD $TU_SEC]]
set ppa(05_saif)      [expr {$saif_ok ? "measured" : "estimated"}]
set ppa(06_time_unit) $TIME_UNIT
set ppa(07_area_unit) $AREA_UNIT

# ---- area -----------------------------------------------------------------
redirect -variable arpt { report_area }
set raw_total [_grab $arpt {Total cell area:\s+([0-9.e+-]+)}]
set ppa(08_area_raw)    $raw_total
set ppa(10_area_total)  [_ascale $raw_total $AREA_DIVISOR]
set ppa(11_area_comb)   [_ascale [_grab $arpt {Combinational area:\s+([0-9.e+-]+)}]    $AREA_DIVISOR]
set ppa(12_area_seq)    [_ascale [_grab $arpt {Noncombinational area:\s+([0-9.e+-]+)}] $AREA_DIVISOR]
set ppa(13_area_bufinv) [_ascale [_grab $arpt {Buf/Inv area:\s+([0-9.e+-]+)}]          $AREA_DIVISOR]
set ppa(14_leaf_cells)  [sizeof_collection [get_cells -hier -filter "is_hierarchical == false"]]
set ppa(15_registers)   [sizeof_collection [all_registers -cells]]

# Area of the combinational adder alone (the interesting number).  A
# hierarchical cell has no usable "area" attribute in this DC version, so ask
# report_area inside the sub-design instead.  Falls back to the total when the
# hierarchy was flattened (KEEP_HIER=0).
set ppa(09_area_core) $ppa(10_area_total)
if {[catch {
    foreach d [get_object_name [get_designs "${CORE_PATTERN}*" -quiet]] {
        if {$d ne $TOPD} {
            current_design $d
            redirect -variable crpt { report_area }
            set ppa(09_area_core) \
                [_ascale [_grab $crpt {Total cell area:\s+([0-9.e+-]+)}] $AREA_DIVISOR]
            break
        }
    }
} m]} { puts ">>> core-area probe failed: $m" }
current_design $TOPD

# ---- timing ---------------------------------------------------------------
set paths [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
if {[sizeof_collection $paths] > 0} {
    set ppa(20_wns) [format %.4f [get_attribute [index_collection $paths 0] slack]]
} else {
    set ppa(20_wns) "n/a"
}
redirect -variable qrpt { report_qor }
set ppa(21_tns)          [_grab $qrpt {Total Negative Slack:\s+(-?[0-9.e+-]+)}]
set ppa(22_violating)    [_grab $qrpt {No\. of Violating Paths:\s+([0-9.e+-]+)}]
set ppa(23_hold_wns)     [_grab $qrpt {Worst Hold Violation:\s+(-?[0-9.e+-]+)}]
set ppa(24_logic_levels) [_grab $qrpt {Levels of Logic:\s+([0-9.e+-]+)}]

if {$ppa(20_wns) ne "n/a"} {
    set achv [expr {$CLK_PERIOD - $ppa(20_wns)}]
    set ppa(25_achieved)     [format %.4f $achv]
    set ppa(26_achieved_mhz) [format %.2f [_mhz $achv $TU_SEC]]
} else {
    set ppa(25_achieved)     "n/a"
    set ppa(26_achieved_mhz) "n/a"
}

# ---- power ----------------------------------------------------------------
redirect -variable prpt { report_power -analysis_effort high }
foreach {key pat} {
    30_p_internal_mW  {Cell Internal Power\s+=\s+([0-9.e+-]+)\s+(\S+)}
    31_p_switch_mW    {Net Switching Power\s+=\s+([0-9.e+-]+)\s+(\S+)}
    32_p_dynamic_mW   {Total Dynamic Power\s+=\s+([0-9.e+-]+)\s+(\S+)}
    33_p_leakage_mW   {Cell Leakage Power\s+=\s+([0-9.e+-]+)\s+(\S+)}
} {
    if {[regexp -line $pat $prpt -> v u]} {
        set ppa($key) [format %.4f [_to_mW $v $u]]
    } else {
        set ppa($key) "n/a"
    }
}
if {$ppa(32_p_dynamic_mW) ne "n/a" && $ppa(33_p_leakage_mW) ne "n/a"} {
    set ppa(34_p_total_mW) [format %.4f \
        [expr {$ppa(32_p_dynamic_mW) + $ppa(33_p_leakage_mW)}]]
} else {
    set ppa(34_p_total_mW) "n/a"
}

# ---- throughput / energy --------------------------------------------------
# Fully pipelined: OPS_PER_CYCLE results every clock.
set ppa(17_ops_cyc) $OPS_PER_CYCLE
if {$ppa(34_p_total_mW) ne "n/a"} {
    set t_cyc [expr {$CLK_PERIOD * $TU_SEC}]
    set ppa(40_throughput_Mops) [format %.1f [expr {$OPS_PER_CYCLE / $t_cyc / 1e6}]]
    set ppa(41_energy_op_pJ)    [format %.4f \
        [expr {$ppa(34_p_total_mW) * 1e-3 * $t_cyc / $OPS_PER_CYCLE * 1e12}]]
} else {
    set ppa(40_throughput_Mops) "n/a"
    set ppa(41_energy_op_pJ)    "n/a"
}

# ---- print + save ---------------------------------------------------------
set f "  %-26s : %s"
set out "============================================================\n"
switch -- $TOP {
    bf16_adder       { set _hdr "(PIPE=$PARAM_PIPE)" }
    bf16_addsub_unit { set _hdr "([expr {$PARAM_FUSED ? {FUSED} : {2x bf16_add}}],\
PIPE=$PARAM_PIPE)" }
    default          { set _hdr "(combinational)" }
}
append out " PPA SUMMARY -- $TOP  $_hdr\n"
append out "============================================================\n"
append out [format $f "target period"   "$ppa(03_period) $TIME_UNIT ($ppa(04_freq_mhz) MHz)"]\n
append out [format $f "achieved period" "$ppa(25_achieved) $TIME_UNIT ($ppa(26_achieved_mhz) MHz)"]\n
append out [format $f "setup WNS / TNS" "$ppa(20_wns) / $ppa(21_tns) $TIME_UNIT"]\n
append out [format $f "violating paths" "$ppa(22_violating)"]\n
append out [format $f "hold WNS"        "$ppa(23_hold_wns) $TIME_UNIT"]\n
append out [format $f "levels of logic" "$ppa(24_logic_levels)"]\n
append out "------------------------------------------------------------\n"
append out [format $f "total cell area" "$ppa(10_area_total) $AREA_UNIT"]\n
append out [format $f "  $CORE_PATTERN" "$ppa(09_area_core) $AREA_UNIT"]\n
append out [format $f "  combinational" "$ppa(11_area_comb) $AREA_UNIT"]\n
append out [format $f "  sequential"    "$ppa(12_area_seq) $AREA_UNIT"]\n
append out [format $f "  buf/inv"       "$ppa(13_area_bufinv) $AREA_UNIT"]\n
if {$AREA_DIVISOR != 1.0} {
append out [format $f "  (raw DC area)" "$ppa(08_area_raw) lib-units / $AREA_DIVISOR"]\n
}
append out [format $f "leaf cells"      "$ppa(14_leaf_cells)"]\n
append out [format $f "registers"       "$ppa(15_registers)"]\n
append out "------------------------------------------------------------\n"
append out [format $f "activity source" "$ppa(05_saif)"]\n
append out [format $f "internal power"  "$ppa(30_p_internal_mW) mW"]\n
append out [format $f "switching power" "$ppa(31_p_switch_mW) mW"]\n
append out [format $f "dynamic power"   "$ppa(32_p_dynamic_mW) mW"]\n
append out [format $f "leakage power"   "$ppa(33_p_leakage_mW) mW"]\n
append out [format $f "TOTAL power"     "$ppa(34_p_total_mW) mW"]\n
append out "------------------------------------------------------------\n"
append out [format $f "throughput"      "$ppa(40_throughput_Mops) Madd/s"]\n
append out [format $f "energy / add"    "$ppa(41_energy_op_pJ) pJ"]\n
append out "============================================================\n"

puts "\n$out"

set fh [open $RPT_DIR/ppa_summary.rpt w]; puts $fh $out; close $fh

set keys [lsort [array names ppa]]
set hdr {}; set val {}
foreach k $keys {
    lappend hdr [string range $k 3 end]
    lappend val $ppa($k)
}
set fh [open $RPT_DIR/ppa.csv w]
puts $fh [join $hdr ","]
puts $fh [join $val ","]
close $fh

puts ">>> done.  reports: $RPT_DIR   netlist: $NET_DIR"
exit 0
