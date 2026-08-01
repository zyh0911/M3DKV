# ============================================================================
#  syn_dc.tcl -- Design Compiler synthesis + PPA for the single-path BF16 adder
#
#     dc_shell -f syn_dc.tcl | tee dc.log      (normally via ./run_syn.sh)
#
#  Beyond the usual total PPA this script breaks out the area and the power of
#  the three datapath units (compare_and_select / add_sub_mantissa /
#  normalize_rz), which only works when KEEP_HIER=1.
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
        puts "       source libs/asap7.sh (or your own libs/*.sh) first."
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
puts "\n>>> analyze (-format $RTL_FORMAT)"
foreach f $RTL_FILES {
    if {![file exists $f]} { puts "ERROR: missing RTL file $f"; exit 1 }
    analyze -format $RTL_FORMAT -lib WORK $f
}

puts "\n>>> elaborate $TOP"
if {$PARAMS ne ""} {
    elaborate $TOP -library WORK -parameters "$PARAMS"
} else {
    elaborate $TOP -library WORK
}
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

# ============================================================================
#  Compile
# ============================================================================
set compile_opts [list]
if {$GATE_CLOCK} { lappend compile_opts -gate_clock }
if {$RETIME}     { lappend compile_opts -retime }
if {$KEEP_HIER}  { lappend compile_opts -no_autoungroup }

puts "\n>>> compile  (ultra=$COMPILE_ULTRA  keep_hier=$KEEP_HIER  opts: $compile_opts)"
if {$COMPILE_ULTRA} {
    if {[catch {eval compile_ultra $compile_opts} msg]} {
        puts ">>> compile_ultra failed ($msg) -- falling back to plain compile"
        set COMPILE_ULTRA 0
    }
}
if {!$COMPILE_ULTRA} {
    set c2 [list -map_effort high -area_effort high]
    if {$RETIME} { lappend c2 -retime }
    eval compile $c2
}

if {$INCR_COMPILE} {
    puts "\n>>> incremental compile"
    if {$COMPILE_ULTRA} {
        set ci [list -incremental]
        if {$KEEP_HIER} { lappend ci -no_autoungroup }
        catch { eval compile_ultra $ci }
    } else {
        catch { compile -incremental_mapping -map_effort high }
    }
}

current_design $TOPD

# ============================================================================
#  Netlist outputs
# ============================================================================
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output $NET_DIR/${TOPD}.syn.v
write -format ddc     -hierarchy -output $NET_DIR/${TOPD}.syn.ddc
catch { write_sdf $NET_DIR/${TOPD}.syn.sdf }
catch { write_sdc $NET_DIR/${TOPD}.syn.sdc }

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
rpt timing_max.rpt   { report_timing -delay_type max -max_paths 20 -nworst 5 \
                         -significant_digits 4 -transition_time -capacitance -nosplit }
rpt power.rpt        { report_power -analysis_effort high -nosplit }
rpt power_hier.rpt   { report_power -analysis_effort high -hierarchy -levels 3 -nosplit }
rpt power_groups.rpt { report_power -analysis_effort high \
                         -groups {register combinational sequential} -nosplit }
rpt cell.rpt         { report_cell }

# ============================================================================
#  Helpers
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
    if {[string is double -strict $v]} { return [format %.4f [expr {$v / $div}]] }
    return $v
}

# ============================================================================
#  PPA summary -- totals
# ============================================================================
set ppa(00_top)       $TOPD
set ppa(01_keep_hier) $KEEP_HIER
set ppa(03_period)    $CLK_PERIOD
set ppa(04_freq_mhz)  [format %.2f [_mhz $CLK_PERIOD $TU_SEC]]
set ppa(05_saif)      [expr {$saif_ok ? "measured" : "estimated"}]
set ppa(06_time_unit) $TIME_UNIT
set ppa(07_area_unit) $AREA_UNIT

redirect -variable arpt { report_area }
set raw_total [_grab $arpt {Total cell area:\s+([0-9.e+-]+)}]
set ppa(08_area_raw)    $raw_total
set ppa(10_area_total)  [_ascale $raw_total $AREA_DIVISOR]
set ppa(11_area_comb)   [_ascale [_grab $arpt {Combinational area:\s+([0-9.e+-]+)}]    $AREA_DIVISOR]
set ppa(12_area_seq)    [_ascale [_grab $arpt {Noncombinational area:\s+([0-9.e+-]+)}] $AREA_DIVISOR]
set ppa(13_area_bufinv) [_ascale [_grab $arpt {Buf/Inv area:\s+([0-9.e+-]+)}]          $AREA_DIVISOR]
set ppa(14_leaf_cells)  [sizeof_collection [get_cells -hier -filter "is_hierarchical == false"]]
set ppa(15_registers)   [sizeof_collection [all_registers -cells]]

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

redirect -variable prpt { report_power -analysis_effort high }
foreach {key pat} {
    30_p_internal_mW  {Cell Internal Power\s+=\s+([0-9.e+-]+)\s+(\S+)}
    31_p_switch_mW    {Net Switching Power\s+=\s+([0-9.e+-]+)\s+(\S+)}
    32_p_dynamic_mW   {Total Dynamic Power\s+=\s+([0-9.e+-]+)\s+(\S+)}
    33_p_leakage_mW   {Cell Leakage Power\s+=\s+([0-9.e+-]+)\s+(\S+)}
} {
    if {[regexp -line $pat $prpt -> v u]} {
        set ppa($key) [format %.6f [_to_mW $v $u]]
    } else {
        set ppa($key) "n/a"
    }
}
if {$ppa(32_p_dynamic_mW) ne "n/a" && $ppa(33_p_leakage_mW) ne "n/a"} {
    set ppa(34_p_total_mW) [format %.6f \
        [expr {$ppa(32_p_dynamic_mW) + $ppa(33_p_leakage_mW)}]]
} else {
    set ppa(34_p_total_mW) "n/a"
}

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

# ============================================================================
#  Per-unit breakdown
#
#  Area  : current_design into each sub-design and report_area there.  Each
#          unit is instantiated exactly once, so the sub-design total IS the
#          instance area.  Works even though hierarchical cells carry no
#          usable "area" attribute in this DC version.
#  Power : report_power -hierarchy prints one line per instance; the four
#          power columns of that line are the instance's own + children.
# ============================================================================
set unit_names {}
set unit_area  {}
set unit_leaf  {}

foreach inst $UNIT_INSTS {
    current_design $TOPD
    set c [get_cells $inst -quiet]
    if {[sizeof_collection $c] == 0} {
        puts ">>> BREAKDOWN: instance '$inst' not found (flattened?) - skipped"
        continue
    }
    set dname [get_attribute $c ref_name]
    lappend unit_names $inst
    if {[catch {
        current_design $dname
        redirect -variable urpt { report_area }
        lappend unit_area [_ascale [_grab $urpt {Total cell area:\s+([0-9.e+-]+)}] $AREA_DIVISOR]
        lappend unit_leaf [sizeof_collection [get_cells -hier -filter "is_hierarchical == false"]]
    } m]} {
        puts ">>> BREAKDOWN: area probe of $inst ($dname) failed: $m"
        lappend unit_area "n/a"
        lappend unit_leaf "n/a"
    }
}
current_design $TOPD

# ---- power per instance from the hierarchical report -----------------------
# columns: <inst> (<design>)  switch  int  leak  total  %
redirect -variable phrpt { report_power -analysis_effort high -hierarchy -levels 2 -nosplit }

proc _unit_power {text inst} {
    # DC prints leak power in the library unit; the header tells us which.
    # Match the instance line and return {switch int leak total}.
    foreach line [split $text \n] {
        set line [string trim $line]
        if {[regexp "^${inst}\\s+\\(\[^)\]*\\)\\s+(.*)$" $line -> rest]} {
            set f [regexp -all -inline {[-0-9.e+]+} $rest]
            if {[llength $f] >= 4} { return [lrange $f 0 3] }
        }
    }
    return {n/a n/a n/a n/a}
}

# The hierarchical table does NOT use the units of the summary lines: its
# Switch/Int/Total columns are in the library's dynamic-power unit and the Leak
# column in the leakage unit, both stated in the report header.  Read them
# instead of assuming, otherwise the breakdown is off by orders of magnitude.
set p_unit_dyn  [_grab $phrpt {Dynamic Power Units\s+=\s+1(\S+)}  "mW"]
set p_unit_leak [_grab $phrpt {Leakage Power Units\s+=\s+1(\S+)}  "pW"]
puts ">>> hierarchical power units: dynamic=$p_unit_dyn leakage=$p_unit_leak"

set unit_pow {}
foreach inst $unit_names {
    set p [_unit_power $phrpt $inst]
    # normalise every column to mW so the table and the total share a unit
    set q {}
    foreach v [lrange $p 0 1] {
        lappend q [expr {[string is double -strict $v] ? [_to_mW $v $p_unit_dyn] : $v}]
    }
    set lk [lindex $p 2]
    lappend q [expr {[string is double -strict $lk] ? [_to_mW $lk $p_unit_leak] : $lk}]
    set tt [lindex $p 3]
    lappend q [expr {[string is double -strict $tt] ? [_to_mW $tt $p_unit_dyn] : $tt}]
    lappend unit_pow $q
}

# ============================================================================
#  Print + save
# ============================================================================
set f "  %-26s : %s"
set out "============================================================\n"
append out " PPA SUMMARY -- $TOPD (combinational, keep_hier=$KEEP_HIER)\n"
append out "============================================================\n"
append out [format $f "target period"   "$ppa(03_period) $TIME_UNIT ($ppa(04_freq_mhz) MHz)"]\n
append out [format $f "achieved delay"  "$ppa(25_achieved) $TIME_UNIT ($ppa(26_achieved_mhz) MHz)"]\n
append out [format $f "setup WNS / TNS" "$ppa(20_wns) / $ppa(21_tns) $TIME_UNIT"]\n
append out [format $f "violating paths" "$ppa(22_violating)"]\n
append out [format $f "levels of logic" "$ppa(24_logic_levels)"]\n
append out "------------------------------------------------------------\n"
append out [format $f "total cell area" "$ppa(10_area_total) $AREA_UNIT"]\n
append out [format $f "  combinational" "$ppa(11_area_comb) $AREA_UNIT"]\n
append out [format $f "  sequential"    "$ppa(12_area_seq) $AREA_UNIT"]\n
append out [format $f "  buf/inv"       "$ppa(13_area_bufinv) $AREA_UNIT"]\n
if {$AREA_DIVISOR != 1.0} {
append out [format $f "  (raw DC area)" "$ppa(08_area_raw) lib-units / $AREA_DIVISOR"]\n
}
append out [format $f "leaf cells"      "$ppa(14_leaf_cells)"]\n
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

# ---- breakdown table -------------------------------------------------------
if {[llength $unit_names] > 0} {
    append out "\n"
    append out "============================================================\n"
    append out " PER-UNIT BREAKDOWN  (area $AREA_UNIT, power mW)\n"
    append out "============================================================\n"
    append out [format "  %-22s %10s %7s %10s %7s %7s\n" \
                   unit area area% power power% cells]
    append out "  ----------------------------------------------------------\n"

    set at $ppa(10_area_total)
    set pt $ppa(34_p_total_mW)
    set sum_a 0.0
    set sum_p 0.0
    foreach n $unit_names a $unit_area p $unit_pow c $unit_leaf {
        set ptot [lindex $p 3]
        if {[string is double -strict $ptot]} { set ptot [format %.6f $ptot] }
        set ap "n/a"
        set pp "n/a"
        if {[string is double -strict $a] && [string is double -strict $at] && $at > 0} {
            set ap [format "%.1f%%" [expr {100.0 * $a / $at}]]
            set sum_a [expr {$sum_a + $a}]
        }
        if {[string is double -strict $ptot] && [string is double -strict $pt] && $pt > 0} {
            set pp [format "%.1f%%" [expr {100.0 * $ptot / $pt}]]
            set sum_p [expr {$sum_p + $ptot}]
        }
        append out [format "  %-22s %10s %7s %10s %7s %7s\n" $n $a $ap $ptot $pp $c]
    }
    append out "  ----------------------------------------------------------\n"
    set ao "n/a"
    set po "n/a"
    if {[string is double -strict $at]} { set ao [format "%.4f" [expr {$at - $sum_a}]] }
    if {[string is double -strict $pt]} { set po [format "%.6f" [expr {$pt - $sum_p}]] }
    append out [format "  %-22s %10s %7s %10s %7s\n" "top-level glue" $ao \
        [expr {[string is double -strict $at] && $at > 0 ? [format "%.1f%%" [expr {100.0*($at-$sum_a)/$at}]] : "n/a"}] \
        $po \
        [expr {[string is double -strict $pt] && $pt > 0 ? [format "%.1f%%" [expr {100.0*($pt-$sum_p)/$pt}]] : "n/a"}]]
    append out [format "  %-22s %10s %7s %10s %7s %7s\n" TOTAL $at "100%" $pt "100%" $ppa(14_leaf_cells)]
    append out "============================================================\n"
} else {
    append out "\n  (no per-unit breakdown: hierarchy was flattened)\n"
}

puts "\n$out"

set fh [open $RPT_DIR/ppa_summary.rpt w]; puts $fh $out; close $fh

# ---- machine readable ------------------------------------------------------
set keys [lsort [array names ppa]]
set hdr {}; set val {}
foreach k $keys { lappend hdr [string range $k 3 end]; lappend val $ppa($k) }
set fh [open $RPT_DIR/ppa.csv w]
puts $fh [join $hdr ","]
puts $fh [join $val ","]
close $fh

set fh [open $RPT_DIR/breakdown.csv w]
puts $fh "unit,area,area_unit,area_pct,p_switch_mW,p_internal_mW,p_leak_mW,p_total_mW,power_unit,leaf_cells"
foreach n $unit_names a $unit_area p $unit_pow c $unit_leaf {
    set ap ""
    if {[string is double -strict $a] && [string is double -strict $ppa(10_area_total)]} {
        set ap [format "%.2f" [expr {100.0 * $a / $ppa(10_area_total)}]]
    }
    puts $fh "$n,$a,$AREA_UNIT,$ap,[join $p ,],mW,$c"
}
puts $fh "TOTAL,$ppa(10_area_total),$AREA_UNIT,100.00,$ppa(31_p_switch_mW),$ppa(30_p_internal_mW),$ppa(33_p_leakage_mW),$ppa(34_p_total_mW),mW,$ppa(14_leaf_cells)"
close $fh

puts ">>> done.  reports: $RPT_DIR   netlist: $NET_DIR"
exit 0
