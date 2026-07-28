# ============================================================================
#  LightRot 2-step hierarchical FHT unit -- simulation makefile (Icarus Verilog)
#
#    make            run both testbenches
#    make core       run tb_fht_core only
#    make unit       run tb_fht_2step_unit only
#    make wave       run tb_fht_2step_unit with VCD dump
#    make clean
# ============================================================================

IVERILOG ?= iverilog
VVP      ?= vvp

RTL  = rtl/fht_core.v rtl/trf_16x8.v rtl/fht_2step_unit.v
BUILD = build

.PHONY: all core unit wave clean

all: core unit

$(BUILD):
	mkdir -p $(BUILD)

$(BUILD)/tb_fht_core.vvp: $(RTL) tb/tb_fht_core.v | $(BUILD)
	$(IVERILOG) -g2005 -Wall -o $@ -s tb_fht_core $(RTL) tb/tb_fht_core.v

$(BUILD)/tb_fht_2step_unit.vvp: $(RTL) tb/tb_fht_2step_unit.v | $(BUILD)
	$(IVERILOG) -g2005 -Wall -o $@ -s tb_fht_2step_unit $(RTL) tb/tb_fht_2step_unit.v

core: $(BUILD)/tb_fht_core.vvp
	$(VVP) $<

unit: $(BUILD)/tb_fht_2step_unit.vvp
	$(VVP) $<

wave: $(BUILD)/tb_fht_2step_unit.vvp
	$(VVP) $< +vcd

clean:
	rm -rf $(BUILD) *.vcd
