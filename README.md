# M3DKV

This repository contains the code and scripts for our ASP-DAC 2026 paper, *“M3DKV: Monolithic 3D Gain Cell Memory Enabled Efficient KV Cache & Processing”* 

## Overview

M3DKV is a near-memory-computing (NMC) accelerator that overcomes the memory bottleneck in Transformer-based LLM decoding by leveraging a monolithic 3D-stacked gain-cell DRAM. The design uses multiple high-density Back-End-of-Line (BEOL) gain-cell memory layers to buffer key-value (KV) pairs in-place and a Front-End-of-Line (FEOL) base layer to perform self-attention computation. This architecture efficiently caches and processes the keys and values on-chip, significantly increasing storage density and reducing external bandwidth needs. In our experiments, M3DKV achieved a memory density of 45.49 MB/mm² and a 97.03× speedup over a GPU implementation in the LLM decoding phase.

## Environment and Tools

### Hardwaref
| **Role**               | **Platforms in our evaluation**                               |
| ---------------------- | ------------------------------------------------------------ |
| **GPU benchmark**      | **NVIDIA GeForce RTX 3090 – 10 496 CUDA cores, 24 GB GDDR6X** |
| **CPU benchmark**      | **Intel Xeon Gold 6133 – 20 cores / 40 threads, 2.5 GHz base** |
| **Design simulations** | Workstation-class Linux PC with ≥ 32 GB RAM                  |

### **Software**
- **OS:** Linux (Ubuntu 20.04+, RHEL 8+, etc.)  
- **Python:** ≥ 3.11 `pip install -r requirements.txt`.  Add cocotb for RTL simulation and matplotlib (or seaborn) to plot Figure 6.
- **Verilog simulation:** Any standard Verilog simulator (e.g., Icarus Verilog, Verilator, ModelSim/Questa) compatible with Verilog/SystemVerilog. *cocotb* (Python testbench) is used for RTL verification.
- **Synthesis:** Synopsys Design Compiler J-2020.09 (only if you want to rebuild `dc_rpt/`)  
- **SPICE:** Cadence Spectre 21.x+ CLI 
- **GPU drivers / CUDA:** CUDA 12.2 (only if you intend to run the GPU benchmark)

## **Simulations**

### **RTL Simulation**

The `tb/` directory contains cocotb-based Python testbenches for verifying the RTL modules. To run the RTL tests:

1. Navigate to the `tb/` directory: `cd tb/`.

2. Build and simulate the top-level design. For example, with Icarus Verilog:

   ```bash
   make SIM=icarus TOPLEVEL_LANG=verilog
   ```

   Or use your simulator of choice by editing the `Makefile`.

   The cocotb tests (e.g., `test_self_attention.py`) will execute and check the functionality of the design. Test results will be printed to the console.

Make sure the RTL files in `rtl/` are correctly referenced by the testbench. The tests include checks that the gain-cell KV cache and attention logic produce correct outputs (within tolerance).

### **SPICE Simulation**

M3DKV’s BEOL gain-cell array is simulated using an IGZO 2T0C compact model that has been validated against silicon:

* Su *et al.* “Monolithic 3-D Integration of Counteractive Coupling IGZO/CNT Hybrid 2T0C DRAM and Analog RRAM-Based Computing-in-Memory,” IEEE Transactions on Electron Devices, 2024  
  ↳ Provides the physical parameters and retention characteristics we target in this work.

* Guo *et al.* “A New Surface-Potential and Physics-Based Compact Model for a-IGZO TFTs at Multinanoscale for High-Retention and Low-Power DRAM Application,” IEDM 2021  
  ↳ The authors released a Verilog-A implementation of their model.

> Note: Only the Verilog-A model from Guo *et al.* is publicly available. The Su *et al.* parameters are reproduced from the publication and calibrated to internal data; the raw model deck itself cannot redistributed here due to licence restrictions.

Spectre simulation results for the gain-cell macro are stored in `results/wave.csv` and are the direct input for Figure 5.

## **Data Plotting and Reproduction**

The `scripts/` directory contains Python scripts to reproduce key figures and comparisons from the paper:

- `plot_figure6.py`: Reproduces Figure 6 (Area-Performance Trade-offs in M3DKV with different configurations). It processes simulation data (e.g., from `results/dc_rpt`) and generates plots.
- `gpu_cpu_benchmark.py`: Measures the performance of self-attention operations on CPU vs GPU (used to evaluate the performance improvement of GPU/CPU).

## **Repository Structure**

The repository is organized as follows:

- `rtl/`: Verilog RTL source code for the M3DKV.
  - `DRAM/`: Contains behavioral models of gain-cell macros used for storage.
  - `Accumulation/`: Modules responsible for performing accumulation operations in GEMV (General Matrix-Vector Multiplication).
  - `Input/`: Modules dedicated to preprocessing floating-point data and controlling the dataflow during write operations.
  - `Output/`: Modules that handle post-processing of data before output.
  - `Math/`: Essential mathematical operation modules for self-attention, including exponentiation, reciprocal calculation, and floating-point multiplication and addition.
  - `softmax/`: Includes submodules implementing the softmax function as described in the paper, specifically the Arg_Max, Row_Reduce, and Norm_Exp modules (see Figure 4).
  - `GEMV_shared_block1/`: Instantiates the shared GEMV `pre_align` module (Figure 4), aligning floating-point numbers for accumulation during matrix multiplication.
  - `GEMV_shared_block2/`: Instantiates the shared GEMV `accumulation` module (Figure 4), performing internal accumulations in matrix multiplication.
  - `M3D_unshared_block1/`: Instantiates GEMV-specific modules that are not shared across operations, including Write Control, Compute Control, and Input Control modules (Figure 4).
  - `M3D_unshared_block2/`: Instantiates GEMV-specific Output Control modules (Figure 4) managing data flow post computation.
  - `self_attention_top/`: Top-level module integrating all submodules for executing the complete self-attention computation.

- `tb/`: cocotb-based testbench files and Makefile for RTL simulation. This includes Python test scripts that verify the hardware modules.
- `scripts/`: Python scripts for data analysis and plotting. These scripts reproduce the figures in the paper from raw simulation data.
- `results/`: Directory containing generated data files and example output figures. This can include sample CSV results and PNGs from the scripts.
  - `wave.csv`：Spectre simulation results for Figure 5.
  - `dc_rpt/`: Contains raw Design-Compiler log files for every design-space point used in Figure 6.
- `figures/`: Contains evaluation figures used in the paper (figure 5 and figure 6).
- Top-level files:
  - `README.md`: Project overview and instructions.
  - `requirements.txt`: Python dependencies.

## **Contact**

For questions or feedback, please open an issue on GitHub or contact the authors.
