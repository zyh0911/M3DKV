# ===========================================================================
#  BF16 adder / fused add-subtract unit -- simulation makefile
#
#    make sim          self-checking testbench for bf16_add        (VCS)
#    make sim-as       self-checking testbench for the fused unit
#    make oracle       recheck the dumped vectors in exact Python
#    make oracle-as    same, for the fused unit's vectors
#    make gate         zero-delay sim of the mapped bf16_adder netlist
#    make saif         switching-activity workload for bf16_adder
#    make clean
#
#  VCS is the default because this machine has no Icarus; SIM=iverilog works
#  too if you have it.
# ===========================================================================
SIM      ?= vcs
BUILD    ?= build
RTL      := rtl/bf16_add.v rtl/bf16_adder.v
RTL_AS   := $(RTL) rtl/bf16_addsub_fused.v rtl/bf16_addsub_2x.v rtl/bf16_addsub_unit.v
TB       := tb/tb_bf16_add.v
TB_AS    := tb/tb_bf16_addsub.v
TOP      := tb_bf16_add
TOP_AS   := tb_bf16_addsub
INCDIR   := +incdir+tb
NRAND    ?= 200000
VECTORS  := $(BUILD)/vectors.txt
VEC_AS   := $(BUILD)/vectors_addsub.txt

# gate-level: the DC netlist + the ASAP7 RVT/TT simulation models
NETLIST  ?= syn/out/sweep_bf16_adder_p2/bf16_adder_650ps/netlist/bf16_adder.syn.v
A7VLOG   ?= /usr/local/tools/PDK/ASAP7/asap7libs_24/verilog
A7MODELS := $(A7VLOG)/asap7sc7p5t_24_SIMPLE_RVT_TT.v \
            $(A7VLOG)/asap7sc7p5t_24_INVBUF_RVT_TT.v \
            $(A7VLOG)/asap7sc7p5t_24_AO_RVT_TT.v     \
            $(A7VLOG)/asap7sc7p5t_24_OA_RVT_TT.v     \
            $(A7VLOG)/asap7sc7p5t_24_SEQ_RVT_TT.v

.PHONY: sim sim-as oracle oracle-as saif gate clean

ifeq ($(SIM),vcs)
$(BUILD)/simv: $(RTL) $(TB) tb/bf16_ref_model.vh | $(BUILD)
	vcs -full64 -sverilog -notice +v2k $(INCDIR) -o $@ -top $(TOP) $(RTL) $(TB) \
	    -l $(BUILD)/compile.log

$(BUILD)/simv_as: $(RTL_AS) $(TB_AS) tb/bf16_ref_model.vh | $(BUILD)
	vcs -full64 -sverilog -notice +v2k $(INCDIR) -o $@ -top $(TOP_AS) \
	    $(RTL_AS) $(TB_AS) -l $(BUILD)/compile_as.log

sim: $(BUILD)/simv
	cd $(BUILD) && ./simv +nrand=$(NRAND) +dump=vectors.txt -l sim.log

sim-as: $(BUILD)/simv_as
	cd $(BUILD) && ./simv_as +nrand=$(NRAND) +dump=vectors_addsub.txt -l sim_as.log

saif: $(BUILD)/simv
	cd $(BUILD) && ./simv +saif +nops=20000 -l saif.log
else
$(BUILD)/$(TOP).vvp: $(RTL) $(TB) tb/bf16_ref_model.vh | $(BUILD)
	iverilog -g2005 -Itb -o $@ -s $(TOP) $(RTL) $(TB)

$(BUILD)/$(TOP_AS).vvp: $(RTL_AS) $(TB_AS) tb/bf16_ref_model.vh | $(BUILD)
	iverilog -g2005 -Itb -o $@ -s $(TOP_AS) $(RTL_AS) $(TB_AS)

sim: $(BUILD)/$(TOP).vvp
	cd $(BUILD) && vvp $(TOP).vvp +nrand=$(NRAND) +dump=vectors.txt

sim-as: $(BUILD)/$(TOP_AS).vvp
	cd $(BUILD) && vvp $(TOP_AS).vvp +nrand=$(NRAND) +dump=vectors_addsub.txt

saif: $(BUILD)/$(TOP).vvp
	cd $(BUILD) && vvp $(TOP).vvp +saif +nops=20000
endif

oracle: $(VECTORS)
	python3 tb/bf16_ref.py $(VECTORS)

oracle-as: $(VEC_AS)
	python3 tb/bf16_ref.py $(VEC_AS)

# Zero-delay functional simulation of the mapped netlist.  Runs the full
# check suite (phases 1-4) against the gates that DC actually produced.
gate: $(NETLIST) | $(BUILD)
	vcs -full64 -sverilog -notice +v2k $(INCDIR) +define+GATE_SIM \
	    +nospecify +notimingcheck \
	    -o $(BUILD)/simv_gate -top $(TOP) $(A7MODELS) $(NETLIST) $(TB) \
	    -l $(BUILD)/gate_compile.log
	cd $(BUILD) && ./simv_gate +nrand=50000 -l gate_sim.log

$(BUILD):
	mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD) csrc *.daidir ucli.key vc_hdrs.h simv simv.daidir
