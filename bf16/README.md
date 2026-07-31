# BF16 adder — RTL, verification and Design Compiler PPA

A bfloat16 (BF16) adder/subtractor in Verilog-2001, a fused add-subtract unit
built on the same numerics, self-checking testbenches with two independent
reference models, and a Design Compiler flow that reports area / timing / power
with measured switching activity.

```
rtl/bf16_add.v            combinational adder core (the actual design)
rtl/bf16_adder.v          registered wrapper, PIPE = 0 / 1 / 2
rtl/bf16_addsub_fused.v   fused unit: a+b and a-b from one shared front end
rtl/bf16_addsub_2x.v      baseline for it: two independent bf16_add
rtl/bf16_addsub_unit.v    registered wrapper shared by both cores
rtl/probe/                analysis-only tops: bf16_add cut in half, fixed-point units
tb/tb_bf16_add.v          self-checking testbench (793k checks)
tb/tb_bf16_addsub.v       self-checking testbench for the fused unit (1.2M)
tb/bf16_ref_model.vh      64-bit reference model, shared by both testbenches
tb/bf16_ref.py            exact rational-arithmetic oracle (third opinion)
syn/                      Design Compiler flow (setup / constraints / sweep / SAIF)
doc/fused_vs_two_adders.md   fused vs. two adders: architecture + PPA at 400 MHz
doc/float_vs_fixed_cost.md   where the area goes in a BF16 adder; BFP-FHT projection
Makefile                  simulation targets
```

**Only 13 % of a BF16 adder is arithmetic.** A 16-bit integer add/sub is
**5.8× smaller and 4.2× shorter** than `bf16_add` under identical synthesis
conditions — and still **3.5× smaller per result** than the fused unit, which
is already the best floating-point structure here. The align side costs ~3.6×
the bare adder, the normalise/round side ~3.1×. That is the case for building
a Hadamard transform on a shared-exponent fixed-point datapath instead of
BF16 adders; how much of it survives depends on the datapath width, which is
still open. See [doc/float_vs_fixed_cost.md](doc/float_vs_fixed_cost.md).

**Fused add-subtract unit** — `a+b` and `a-b` in one block. At 400 MHz in
ASAP7 it is **30 % smaller and 26 % lower power** than two independent adders,
because exactly one of the two results is always an effective addition and the
other an effective subtraction, so the compare/swap network, the aligner and
the sticky tree are shared and each output path needs only half a normaliser.
Bit-identical to the two-adder baseline on 1.2 M vectors.
See [doc/fused_vs_two_adders.md](doc/fused_vs_two_adders.md).

## 1. The design

Format: `[15] sign | [14:7] exponent (bias 127) | [6:0] fraction` — the top
half of an IEEE-754 binary32, so 8 bits of significand (1 implicit + 7 stored).

Supported: normals, subnormals (gradual underflow), ±0, ±Inf, NaN,
round-to-nearest-ties-to-even, and the IEEE status flags
`nv` (invalid), `of` (overflow), `uf` (underflow), `nx` (inexact).
`sub = 1` computes `a - b`. NaN results are the canonical qNaN `0x7FC0`
(no payload propagation).

`uf` can never fire: every BF16 value is an integer multiple of the smallest
subnormal, so a sum of two of them is one too — a result in the subnormal
range is always exact. The logic is kept so the flag interface is complete.

Architecture — classic **single path**:

```
unpack ─ magnitude sort ─ align smaller operand (3 GRS bits + sticky)
       ─ add / subtract ─ normalise (1 right or N left, clamped at subnormal)
       ─ round to nearest even ─ pack
```

Two facts make 3 extra bits sufficient (both are argued in the header of
`rtl/bf16_add.v`):

- sticky can only be set when the alignment shift is ≥ 4, and then an
effective subtraction cancels no leading bits — so `sticky = 1` implies
the normalising left shift is 0;
- a left shift ≥ 2 requires an exponent difference ≤ 1, and then nothing was
shifted out at all.

For an effective subtraction the borrow caused by the discarded tail is
modelled exactly by subtracting the sticky bit (`al_l - al_s - sticky`); the
remaining residue stays in (0,1) ulp of the S position, so S stays 1. That is
what makes the result correctly rounded rather than "almost always right".

`bf16_adder` is a thin wrapper: `PIPE=2` (default) registers both inputs and
outputs, so the critical path DC sees is a clean reg-to-reg path containing
exactly the adder. `PIPE=1` registers only the outputs, `PIPE=0` is pure
combinational (the constraint file switches to a virtual clock + `set_max_delay`
automatically). The datapath is fully pipelined — one add per cycle, no
back pressure.

## 2. Simulation

```bash
source syn/libs/env_synopsys.sh     # puts vcs / dc_shell / vcd2saif on PATH
make sim                            # VCS  (SIM=iverilog also works)
make oracle                         # re-check the dumped vectors in Python
make sim-as && make oracle-as       # same, for the fused add-subtract unit
```

The testbench runs four phases:


| phase | what                                                                                                                                                                         |
| ----- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1     | 32 directed vectors with hand-written expectations — NaN, ±Inf, Inf−Inf, ±0 sign rules, subnormal↔normal boundary, overflow, the three tie cases, and nine status-flag cases |
| 2     | cross product of 432 interesting operands × {add, sub} = 373 248 checks                                                                                                      |
| 3     | 400 000 random pairs — half uniform, half with correlated exponents (the case that actually exercises alignment and cancellation)                                            |
| 4     | 20 000 vectors through `bf16_adder` PIPE=2, checking the pipeline and `vld_out`                                                                                              |


Phases 2–4 compare against a reference model written in a deliberately
different style: it aligns into a 64-bit field with **48** guard bits and an
explicit sticky, so a shared trick in the 12-bit datapath cannot hide a bug.

`make oracle` is a third, fully independent check: `tb/bf16_ref.py` recomputes
50 000 of the vectors with `fractions.Fraction` (exact rational arithmetic) and
an explicit round-to-nearest-even quantiser — no floating point anywhere, so it
cannot inherit a rounding bug from the host FPU. It also checks all four status
flags, which it can derive exactly (`nx` is simply "the rounded value differs
from the exact sum").

```bash
make gate       # zero-delay simulation of the DC netlist + ASAP7 cell models
```

`make gate` re-runs the whole suite against the mapped netlist (`+define+GATE_SIM`
binds `bf16_add_0` / `bf16_adder_PIPE2` from `syn/out/.../*.syn.v` instead of the
RTL), so the thing that was actually synthesised is verified, not just its
source. Point it at another run with `make gate NETLIST=path/to/x.syn.v`.

Current status:

```
 PASS -- 793279 checks, 0 mismatches                              (make sim)
 PASS -- 50000 vectors, 0 result mismatches, 0 flag mismatches    (make oracle)
 PASS -- 493270 checks, 0 mismatches                              (make gate)
```

## 3. Synthesis

```bash
cd syn
source libs/env_synopsys.sh      # dc_shell + licence server
source libs/asap7.sh             # ASAP7 7nm RVT, TT 0.7V 25C  (time unit = ps)

./gen_saif.sh                    # 20k random adds -> sim/bf16_adder.saif
SAIF_FILE=$PWD/sim/bf16_adder.saif CLK_PERIOD=650 ./run_syn.sh

SAIF_FILE=$PWD/sim/bf16_adder.saif JOBS=8 \
    ./ppa_sweep.sh 1000 900 800 700 650 620 600 580     # PPA curve
```

Everything is configured from `syn/setup.tcl`, and every variable in it can be
overridden from the environment (`TOP`, `PARAM_PIPE`, `CLK_PERIOD`,
`COMPILE_ULTRA`, `SAIF_FILE`, …). `syn/constraints.tcl` holds the timing/DRC
constraints and adapts itself to a combinational top; `syn/syn_dc.tcl` runs the
compile and writes the reports.

Outputs land in `syn/out/<tag>/`: `reports/ppa_summary.rpt` (human),
`reports/ppa.csv` (machine), plus the usual area / timing / power / QoR reports
and the mapped netlist, SDF and SDC.

### Measured PPA — ASAP7 7nm RVT, TT 0.7 V 25 °C, `bf16_adder` PIPE=2

Power uses a **measured** SAIF from 20 000 back-to-back random adds (half with
correlated exponents), not DC's default toggle assumption.

```
 Tclk[ps]  achv[ps]  Fmax[MHz]   WNS[ps]  area[um^2]   core   Ptot[mW]  E/add[pJ]
     1000     998.9     1001.1       1.1       73.53   50.27    0.1065     0.1065
      900     899.6     1111.7       0.4       75.99   52.74    0.1140     0.1026
      800     799.6     1250.6       0.4       79.74   56.45    0.1229     0.0983
      700     699.9     1428.7       0.1       90.94   67.64    0.1459     0.1021
      650     650.0     1538.5       0.0       99.95   76.66    0.1634     0.1062
      620     663.0     1508.2     -43.0      104.25   80.88    0.1775     0.1101
      600     657.5     1520.9     -57.5      102.73   79.37    0.1774     0.1064
      580     640.0     1562.5     -60.0      106.56   83.24    0.1896     0.1100
```

- **Fmax ≈ 1.54 GHz** (650 ps) — the last period that closes. Below 650 ps DC
cannot recover the path; the 580–620 ps rows are shown to make the wall
visible, they are *not* valid operating points.
- **Area** 99.9 µm² at Fmax, 73.5 µm² relaxed; the adder core itself is
76.7 / 50.3 µm², the rest is the 55-flop wrapper (20.8 µm²).
- **Energy** ≈ 0.10 pJ per add, flat across the curve — the extra cells DC
buys at high frequency roughly cancel the shorter cycle.
- ~46–58 levels of logic: this is a single-path adder, so align-shift → add →
normalise-shift → round is one long serial chain. A two-path (far/close)
architecture with a leading-zero anticipator is the standard way to shorten
it, at a significant area cost.

Caveats for anyone quoting these numbers: ASAP7 is a *predictive* PDK and the
`.db` that ships is the **TT** corner, so these are typical-case (optimistic
vs. an SS sign-off corner). Areas are pre-layout cell areas with no wire load
model; the raw DC area is divided by 16 because ASAP7 is drawn at 4× linear
scale. The pre-CTS hold WNS is slightly negative (≈ −10 ps), which is normal
before clock-tree synthesis and is fixed during P&R.

ASAP7 has no integrated clock-gating cell, so `constraints.tcl` probes the
library and falls back to a discrete latch-based gate. With only 55 flops
there is nothing to gain there anyway.

### The bare combinational core

```bash
TOP=bf16_add IN_DELAY_F=0 OUT_DELAY_F=0 SWEEP_TAG=sweep_bf16_add_comb \
    JOBS=6 ./ppa_sweep.sh 650 600 550 500 450 400
```

`constraints.tcl` notices there is no `clk` port and switches to a virtual
clock plus `set_max_delay`, so what comes back is the adder's own
input-to-output delay:

```
 Tclk[ps]  achv[ps]   WNS[ps]  levels  area[um^2]
      650     649.9       0.1      41       65.28
      600     599.9       0.1      48       77.39
      550     578.4     -28.4      47       80.13
      500     584.3     -84.3      48       80.16
      450     582.4    -132.4      48       80.88
      400     585.9    -185.9      51       78.67
```

**≈ 600 ps of pure combinational delay**, and DC cannot go below ~578 ps no
matter how much area it is allowed. That is the consistency check on the
wrapper numbers above: 600 ps of logic + clk→Q + setup + 32.5 ps of clock
uncertainty lands exactly on the 650 ps the PIPE=2 design closes at.

Power in this table is DC's 0.25-toggle-rate guess against a virtual clock on
a block with no registers — ignore it; only the wrapper runs have a real SAIF.