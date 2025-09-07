# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0
import os, sys, math, logging
from pathlib import Path
from dataclasses import dataclass
from typing import Dict, Tuple

import numpy as np
import cocotb
from cocotb.runner   import get_runner
from cocotb.clock    import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.binary   import BinaryValue

# ------------ functions ------------------------------------------------
def decimal_to_bf16(x):
    if x == 0:
        return 0
    sign = 0 if x > 0 else 1
    x_abs = abs(x)
    m, e = math.frexp(x_abs)
    significand = m * 2
    exponent_real = e - 1
    biased_exponent = exponent_real + 127
    if biased_exponent >= 255:
        return (sign << 15) | (0b11111111 << 7)
    elif biased_exponent <= 0:
        return sign << 15
    frac = significand - 1.0
    scaled = frac * (2**7)
    mantissa = int(scaled)
    bf16 = (sign << 15) | (biased_exponent << 7) | (mantissa & 0x7F)
    return bf16

def bf16_to_decimal(bf16_int):
    sign = (bf16_int >> 15) & 0x01
    exponent = (bf16_int >> 7) & 0xFF
    mantissa = bf16_int & 0x7F
    if exponent == 0:
        return 0.0 if sign == 0 else -0.0
    elif exponent == 0xFF:
        return float('inf') if mantissa == 0 else float('nan')
    exponent_real = exponent - 127
    mantissa_fraction = 1 + mantissa / 128.0
    return (-1)**sign * mantissa_fraction * (2 ** exponent_real)

def compare_vector(actual, expected):
    actual   = np.asarray(actual).ravel()
    expected = np.asarray(expected).ravel()

    if actual.shape != expected.shape:
        raise AssertionError(
            f"Expected vector dim ({expected.shape[0]}) does not match "
            f"actual ({actual.shape[0]})"
        )

    abs_err = np.abs(actual - expected)
    max_err_abs = abs_err.max()
    max_err_rel = np.max(np.where(expected != 0, abs_err / np.abs(expected), abs_err))

    return float(max_err_abs), float(max_err_rel)

def pack_vector_to_row(input_data, row_capacity, element_bitwidth):
    assert len(input_data) <= row_capacity
    packed = 0
    for i in range(row_capacity):
        offset = i * element_bitwidth
        mask   = ((1 << element_bitwidth) - 1) << offset
        value  = int(input_data[i]) if i < len(input_data) else 0
        packed = (packed & ~mask) | ((value << offset) & mask)
    return packed

def unpack_row_to_vector(row_value: int, row_capacity: int, element_bitwidth: int):
    mask = (1 << element_bitwidth) - 1
    return [(row_value >> (idx * element_bitwidth)) & mask
            for idx in range(row_capacity)]

def row_to_float_vec(sig_val, row_cap, bitw):
    return np.array(
        [bf16_to_decimal(w) for w in unpack_row_to_vector(int(sig_val), row_cap, bitw)],
        dtype=np.float32
    )

def bitvec_to_float_array(bit_val, n_elem, bitw):
    mask = (1 << bitw) - 1
    return np.array(
        [bf16_to_decimal((int(bit_val) >> (i * bitw)) & mask) for i in range(n_elem)],
        dtype=np.float32
    )

async def write_matrix(dut,weight, wr_sig, vld_sig, rdy_sig, MACRO_COLUMN, MACRO_ROW, BANK_COLUMN, BANK_ROW):
    vld_sig.value = 0
    await RisingEdge(dut.clk)
    vld_sig.value = 1

    macro_row_index = 0
    while macro_row_index < MACRO_ROW:
        col_index = 0
        while col_index < BANK_COLUMN:
            weight_list = []
            for j in range(int(BANK_ROW/MACRO_ROW)):
                for i in range(int(BANK_COLUMN/MACRO_COLUMN)):
                    weight_list.append(decimal_to_bf16(weight[int((macro_row_index * (BANK_ROW // MACRO_ROW)) + j)][int(col_index + i)]))
            assert len(weight_list) == int(BANK_COLUMN/MACRO_COLUMN) * int(BANK_ROW/MACRO_ROW)
            data_value = pack_vector_to_row(
                input_data       = weight_list,
                row_capacity     = int((BANK_COLUMN/MACRO_COLUMN) * (BANK_ROW/MACRO_ROW)),
                element_bitwidth = int(cocotb.top.FP_WIDTH)
            )
            wr_sig.value = data_value
            while True:
                await RisingEdge(dut.clk)
                if (rdy_sig.value.integer == 1):
                    break
            col_index += BANK_COLUMN/MACRO_COLUMN
        macro_row_index += 1
    vld_sig.value = 0


async def write_q(dut, q, wr_sig, vld_sig, rdy_sig, MACRO_COLUMN, BANK_COLUMN):
    vld_sig.value = 0
    await RisingEdge(dut.clk)
    dut.cme.value = 1
    await RisingEdge(dut.clk)
    col_index = 0
    while col_index < int(BANK_COLUMN):
        macro_chunk = []
        for i in range(int(BANK_COLUMN/MACRO_COLUMN)):
            macro_chunk.append(decimal_to_bf16(q[0][col_index + i]))

        data_value = pack_vector_to_row(
            input_data       = macro_chunk,
            row_capacity     = int(BANK_COLUMN/MACRO_COLUMN),
            element_bitwidth = 16
        )  
        vld_sig.value = 1
        wr_sig.value = data_value
        while True:
            await RisingEdge(dut.clk)
            if (rdy_sig.value.integer == 1):
                vld_sig.value = 0
                break

        col_index += int(BANK_COLUMN/MACRO_COLUMN)
    await RisingEdge(dut.clk)

async def collect_stream(
        dut, 
        data_sig, 
        vld_sig,     
        total_elems, 
        elems_per_word,
        bitw        
    ):
    buf = []
    while len(buf) < total_elems:
        while True:
            await RisingEdge(dut.clk)
            if (vld_sig.value.integer == 1):
                # dut._log.info(f"data_sig.value: {data_sig.value}")
                part = row_to_float_vec(data_sig.value, elems_per_word, bitw)
                buf.extend(part)
                break
    return np.asarray(buf[:total_elems], dtype=np.float32)

def attention_model(
                            q: np.ndarray,
                            k: np.ndarray,
                            v: np.ndarray
                        ) :
    """
    q: shape (1, d_model)
    k: shape (k_len, d_model) 
    v: shape (k_len, d_model) 
    para_col: number of columns per block(hardware parallelism)
    
    return:
    out: (1, d_model)
    traces: dict keyed by (col_start, col_end)
    """
    k_len, d_model = k.shape
    assert v.shape == (k_len, d_model)
    assert q.shape == (1, d_model)

    scores = np.dot(q, k.T)               # (1, k_len)
    global_max = scores.max() 
    scores_norm = scores - global_max
    pi = np.exp(scores_norm)         # (1, k_len)
    sum_pi = pi.sum()
    rcp = 1.0 / sum_pi

    attn = np.dot(pi, v)         # (1, d_model)
    out = attn * rcp
    return out,scores,scores_norm,pi,rcp,attn


async def attention_test(dut, q, k, v, para):
    golden_out, golden_scores, golden_scores_norm, golden_pi, golden_rcp, golden_attn = attention_model(q, k, v)

    cocotb.start_soon(Clock(dut.clk, 2, units="ns").start())
    dut.rst_n.value = 0 
    dut.cme.value = 0
    dut.we.value = 0
    dut.q_data_in.value = 0
    dut.q_data_in_vld.value = 0
    dut.k_data_wr.value = 0
    dut.k_data_wr_vld.value = 0
    dut.v_data_wr.value = 0
    dut.v_data_wr_vld.value = 0
    dut.o_out_rdy.value = 0
    await Timer(20, units="ns"); dut.rst_n.value = 1
    await RisingEdge(dut.clk)
    dut.we.value = 1
    await write_matrix(
        dut           = dut,
        weight        = k,
        wr_sig        = dut.k_data_wr,
        vld_sig       = dut.k_data_wr_vld,
        rdy_sig       = dut.k_data_wr_rdy,
        MACRO_COLUMN  = int(cocotb.top.K_MACRO_COLUMN),
        MACRO_ROW     = int(cocotb.top.K_MACRO_ROW),
        BANK_COLUMN   = int(cocotb.top.K_BANK_COLUMN),
        BANK_ROW      = int(cocotb.top.K_BANK_ROW)
    )

    await RisingEdge(dut.clk)
    dut.we.value = 0

    await RisingEdge(dut.clk)
    dut.we.value = 1

    await  write_matrix(
        dut           = dut,
        weight        = v.T,
        wr_sig        = dut.v_data_wr,
        vld_sig       = dut.v_data_wr_vld,
        rdy_sig       = dut.v_data_wr_rdy,
        MACRO_COLUMN  = int(cocotb.top.V_MACRO_COLUMN),
        MACRO_ROW     = int(cocotb.top.V_MACRO_ROW),
        BANK_COLUMN   = int(cocotb.top.V_BANK_COLUMN),
        BANK_ROW      = int(cocotb.top.V_BANK_ROW)
    )

    await RisingEdge(dut.clk)
    dut.we.value = 0

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    await write_q(
            dut           = dut,
            q             = q,
            wr_sig        = dut.q_data_in,
            vld_sig       = dut.q_data_in_vld,
            rdy_sig       = dut.q_data_in_rdy,
            MACRO_COLUMN  = int(cocotb.top.K_MACRO_COLUMN),
            BANK_COLUMN   = int(cocotb.top.K_BANK_COLUMN)
        )

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.o_out_rdy.value = 1
    while not int(dut.o_out_vld.value):
        await RisingEdge(dut.clk)
    out_float = row_to_float_vec(
        dut.o_out.value, int(dut.HIDDEN_DIM), int(dut.FP_WIDTH)
    )
    dut._log.info(f"[out]  {out_float}")
    dut._log.info(f"[golden_out]: {golden_out.squeeze()}")
    max_abs, max_rel = compare_vector(out_float, golden_out.squeeze())
    dut._log.info(f"[out]   max|abs|={max_abs:.3e}, max|rel|={max_rel:.3e}")
    assert max_abs < 0.1 or max_rel < 1e-1
    dut.log.info(f"out passed")


@cocotb.test()
async def basic_test(dut):
    for i in range(1):
        para = 32
        q_len = 1
        k_len = 1024
        hidden_size = 64
        rng = np.random.default_rng()    
        low, high = -0.1,0.1

        k = rng.uniform(low, high, size=(k_len, hidden_size))
        q = rng.uniform(low, high, size=(q_len, hidden_size))
        v = rng.uniform(low, high, size=(k_len, hidden_size))
        print(f"q: {q}")
        print(f"k: {k}")
        print(f"v: {v}")
        
        await attention_test(dut, q, k, v, para)

def test_self_attention_top_runner():
    proj_path = Path(__file__).resolve().parent.parent
    sys.path.append(str(proj_path / "model"))

    verilog_sources = [
        proj_path/"hdl"/"softmax"/"softmax_block3.v",
        proj_path/"hdl"/"softmax"/"softmax_block2.v",
        proj_path/"hdl"/"softmax"/"softmax_block1.v",
        proj_path/"hdl"/"softmax"/"FpRoundMax.v",
        proj_path/"hdl"/"softmax"/"fp_adder_tree.v",
        proj_path/"hdl"/"self_attention_top.v",
        proj_path/"hdl"/"M3D_unshared_block1.v",
        proj_path/"hdl"/"M3D_unshared_block2.v",
        proj_path/"hdl"/"GEMV_shared_block1.v",
        proj_path/"hdl"/"GEMV_shared_block2.v",
        proj_path/"hdl"/"Input"/"cmIn_control.v",
        proj_path/"hdl"/"Input"/"mantissa_shift.v",
        proj_path/"hdl"/"Input"/"pre_align.v",
        proj_path/"hdl"/"Input"/"cmp_exp_shift.v",
        proj_path/"hdl"/"Input"/"q_cache_control.v",
        proj_path/"hdl"/"Input"/"weight_write_control.v",
        proj_path/"hdl"/"Input"/"cmp_tree.v",
        proj_path/"hdl"/"Output"/"write_controller.v",
        proj_path/"hdl"/"Output"/"center_buf.v",
        proj_path/"hdl"/"Output"/"sync_fifo.sv",
        proj_path/"hdl"/"Accumulation"/"leading_one_detect_com.v",
        proj_path/"hdl"/"Accumulation"/"accumulation_buf.v",
        proj_path/"hdl"/"Accumulation"/"Accumulation_top.v",
        proj_path/"hdl"/"Accumulation"/"bf16_combination.v",
        proj_path/"hdl"/"Accumulation"/"adder_tree_reg.v",
        proj_path/"hdl"/"Accumulation"/"bit_serial_acc.v",
        proj_path/"hdl"/"Math"/"reciprocal.v",
        proj_path/"hdl"/"Math"/"exp.v",
        proj_path/"hdl"/"Math"/"Xn_cal.v",
        proj_path/"hdl"/"Math"/"fp_add_single_cycle.v",
        proj_path/"hdl"/"Math"/"fp_mul_single_cycle.v",
        proj_path/"hdl"/"DRAM"/"DRAM_bank.v",
        proj_path/"hdl"/"DRAM"/"DRAM_banks.v",
        proj_path/"hdl"/"DRAM"/"DRAM_macros.v"
    ]

    sys.path.append(str(proj_path/"tests"))

    runner = get_runner("icarus")
    runner.build(
        verilog_sources=verilog_sources,
        hdl_toplevel="self_attention_top",
        always=True,
    )
    runner.test(
        hdl_toplevel="self_attention_top",
        test_module="test_self_attention_top",
    )

if __name__ == "__main__":
    test_self_attention_top_runner()
