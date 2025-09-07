###############################################################################
# Copyright (c) 2013 Potential Ventures Ltd
# Copyright (c) 2013 SolarFlare Communications Inc
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of Potential Ventures Ltd,
#       SolarFlare Communications Inc nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL POTENTIAL VENTURES LTD BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
###############################################################################

SHELL := /bin/bash

ifeq ($(LOGGING),)

LOGGING=1

.PHONY: all
all:
	@echo "Redirecting Cocotb build & run logs to out_log.txt ..."
	$(MAKE) LOGGING=1 2>&1 | tee out_log.txt

else

SIM       = vcs
TOPLEVEL_LANG ?= verilog

PWD        = $(shell pwd)
export PYTHONPATH := $(PWD)/../model:$(PYTHONPATH)
VERILOG_SOURCES += $(PWD)/../hdl/softmax/softmax_block1.v
VERILOG_SOURCES += $(PWD)/../hdl/softmax/softmax_block2.v
VERILOG_SOURCES += $(PWD)/../hdl/softmax/softmax_block3.v
VERILOG_SOURCES += $(PWD)/../hdl/softmax/FpRoundMax.v
VERILOG_SOURCES += $(PWD)/../hdl/softmax/fp_adder_tree.v
VERILOG_SOURCES += $(PWD)/../hdl/self_attention_top.v
VERILOG_SOURCES += $(PWD)/../hdl/GEMV_shared_block1.v
VERILOG_SOURCES += $(PWD)/../hdl/GEMV_shared_block2.v
VERILOG_SOURCES += $(PWD)/../hdl/M3D_unshared_block1.v
VERILOG_SOURCES += $(PWD)/../hdl/M3D_unshared_block2.v
VERILOG_SOURCES += $(PWD)/../hdl/Input/cmIn_control.v
VERILOG_SOURCES += $(PWD)/../hdl/Input/mantissa_shift.v
VERILOG_SOURCES += $(PWD)/../hdl/Input/pre_align.v
VERILOG_SOURCES += $(PWD)/../hdl/Input/cmp_exp_shift.v
VERILOG_SOURCES += $(PWD)/../hdl/Input/q_cache_control.v
VERILOG_SOURCES += $(PWD)/../hdl/Input/weight_write_control.v
VERILOG_SOURCES += $(PWD)/../hdl/Input/cmp_tree.v
VERILOG_SOURCES += $(PWD)/../hdl/Output/write_controller.v
VERILOG_SOURCES += $(PWD)/../hdl/Output/center_buf.v
VERILOG_SOURCES += $(PWD)/../hdl/Output/sync_fifo.sv
VERILOG_SOURCES += $(PWD)/../hdl/Accumulation/leading_one_detect_com.v
VERILOG_SOURCES += $(PWD)/../hdl/Accumulation/accumulation_buf.v
VERILOG_SOURCES += $(PWD)/../hdl/Accumulation/Accumulation_top.v
VERILOG_SOURCES += $(PWD)/../hdl/Accumulation/bf16_combination.v
VERILOG_SOURCES += $(PWD)/../hdl/Accumulation/bit_serial_acc.v
VERILOG_SOURCES += $(PWD)/../hdl/Math/reciprocal.v
VERILOG_SOURCES += $(PWD)/../hdl/Math/exp.v	
VERILOG_SOURCES += $(PWD)/../hdl/Math/Xn_cal.v
VERILOG_SOURCES += $(PWD)/../hdl/Math/fp_add_single_cycle.v
VERILOG_SOURCES += $(PWD)/../hdl/Math/softmax_cmp_tree.v
VERILOG_SOURCES += $(PWD)/../hdl/Math/fp_mul_single_cycle.v
VERILOG_SOURCES += $(PWD)/../hdl/DRAM/DRAM_bank.v	
VERILOG_SOURCES += $(PWD)/../hdl/DRAM/DRAM_banks.v
VERILOG_SOURCES += $(PWD)/../hdl/DRAM/DRAM_macros.v

TOPLEVEL := self_attention_top
MODULE   := test_self_attention

ifeq ($(SIM),verilator)
    EXTRA_ARGS += --trace --trace-structs -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-UNSIGNED -Wno-UNOPTFLAT -Wno-CASEX
endif
ifeq ($(SIM),vcs)
    export COCOTB_RESOLVE_X=ZEROS
endif

include $(shell cocotb-config --makefiles)/Makefile.sim

endif
