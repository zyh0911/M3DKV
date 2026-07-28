# 2-step Hierarchical FHT Unit (LightRot, Fig. 11)

Verilog reproduction of the **2-step hierarchical Fast Hadamard Transform unit**
described in Fig. 11 of

> J. Kim et al., *"LightRot: A Light-Weighted Rotation Scheme and Architecture
> for Accurate Low-Bit Large Language Model Inference,"*
> IEEE JETCAS, vol. 15, no. 2, pp. 231–243, June 2025.

---

## 1. What Fig. 11 says

**Fig. 11(a)** — a flat 1-step 128-way FHT needs **896 adders**. The paper
replaces it with two steps using a small unit:

| step | unit | repeats | adders |
|------|------|---------|--------|
| 1st  | 16-way FHT | ×8  | 64 |
| 2nd  |  8-way FHT | ×16 | 24 |

16 is chosen because it is the smallest power of two whose square (256) exceeds
the 128 group size.

**Fig. 11(b)** — a **16×8 Transposable Register File (TRF)** holds the 128
activations and supplies the two different access strides:

* 1st step: *row-by-row* access, **stride 1**, 16 elements → 16-way FHT → write back to the row
* 2nd step: *col-by-col* access, **stride 16**, 8 elements → 8-way FHT → write back to the column

The 8-way FHT is not a separate block: *"half of the 16-way FHT Unit is gated to
operate in 8-way mode."*

## 2. Why the 2 steps equal one 128-point rotation

The natural-order (Sylvester) Hadamard matrix factorises as a Kronecker product

```
H_128 = H_8  ⊗  H_16
```

because for `i = r·16 + c` and `j = s·16 + d`,
`popcount(i & j) = popcount(r & s) + popcount(c & d)`, hence
`H128[i][j] = H8[r][s] · H16[c][d]`.

With the TRF laid out as `idx = row·16 + col`:

```
step 1:  t[s][c] = Σ_d H16[c][d] · x[s][d]     (8 row transforms,  stride 1)
step 2:  y[r][c] = Σ_s H8 [r][s] · t[s][c]     (16 col transforms, stride 16)
```

which is exactly `y = H_128 · x`. This equivalence is proven exhaustively in the
testbench (T4: all 128 basis vectors).

## 3. Files

```
rtl/fht_core.v          8/16-way parallel FHT datapath (the shared butterfly network)
rtl/trf_16x8.v          Transposable Register File, 8 rows × 16 cols
rtl/fht_2step_unit.v    Top level: FSM + TRF + FHT core, 128-way rotation task
tb/tb_fht_core.v        Unit testbench for the FHT core
tb/tb_fht_2step_unit.v  Full testbench for the 2-step unit
Makefile                Icarus Verilog regression
```

### `fht_core.v`

One 16-lane, 4-stage radix-2 butterfly network. Stage order matches the crossing
pattern drawn in Fig. 11(b) (widest crossings first, decimation-in-frequency):

| stage | pairs index bit | butterfly distance | 8-way mode |
|-------|-----------------|--------------------|------------|
| 1 | bit[3] | 8 | **gated** |
| 2 | bit[2] | 4 | active |
| 3 | bit[1] | 2 | active |
| 4 | bit[0] | 1 | active |

Gating is done by operand isolation: with `mode16 = 0` the upper 8 input lanes
are forced to 0 and the stage-1 difference outputs are forced to 0, so lanes
8..15 hold a constant 0 through the whole network and never toggle. Stage 1
degenerates into a pass-through for lanes 0..7, leaving a true 8-point transform
on 3 stages × 4 butterflies × 2 = **24 active adders**. Testbench T6 probes every
internal stage node to confirm this.

### `trf_16x8.v`

128 registers with two combinational read ports (row: 16×stride-1, column:
8×stride-16) and matching synchronous write ports. Asynchronous read means a
read → transform → write-back completes in one cycle.

### `fht_2step_unit.v`

```
S_IDLE  →  S_LOAD (8)  →  S_STEP1 (8)  →  S_STEP2 (16)  →  S_OUT (8)  →  S_IDLE
```

* **LOAD** — 16 activations/beat from FP-MEM (in the full chip, through the Gathering Unit), 8 beats
* **STEP1** — one TRF row per cycle → `mode16 = 1` → write the row back
* **STEP2** — one TRF column per cycle → `mode16 = 0` → write the column back
* **OUT** — 16 rotated values/beat toward the Quantization Unit

41 cycles per 128-element rotation task (40 + the start cycle); the 24 compute
cycles match the ×8 / ×16 annotation in Fig. 11(a).

## 4. Numerics

Inputs are `DW`-bit signed fixed point (default 16). The internal and output
width is `W = DW + 7`, i.e. the full `log2(128) = 7` bits of growth, so the
transform is **bit-exact and cannot overflow** — verified in T5 with all-inputs
at `-2^(DW-1)`, which lands exactly on the most negative representable output.

The `1/sqrt(128)` normalisation is deliberately **not** applied, matching the
paper: the scale factor is folded into the downstream Quantization Unit.

## 5. Running

```sh
make          # both testbenches
make core     # tb_fht_core
make unit     # tb_fht_2step_unit
make wave     # + VCD dump
```

Requires Icarus Verilog (`iverilog` / `vvp`); override with `make IVERILOG=... VVP=...`.

### Regression status (Icarus Verilog 12.0)

```
tb_fht_core
  T1  16-way vs. golden H16 (500 random vectors)   pass
  T2   8-way vs. golden H8, upper half gated       pass
  T3  H16 columns are +/-1 and match golden        pass
  T4   H8 columns are +/-1 and match golden        pass
  T5  directed extremes / impulse                  pass
  T6  8-way mode: stage 1 + lanes 8..15 held at 0  pass

tb_fht_2step_unit
  T1  100 random 128-pt rotations vs. golden H128  pass
  T2  10 back-to-back tasks                        pass
  T3  stalled load stream (1..3 gap cycles)        pass
  T4  all 128 Hadamard columns are +/-1            pass
  T5  worst-case bit growth (W = DW+7)             pass
  T6  latency = 41 cycles
```

## 6. Scope

This reproduces the FHT Unit + TRF of Fig. 11 only. The surrounding blocks of
Fig. 10 — Gathering Unit (ODA reordering, Fig. 12), Quantization Unit, FP/INT
memories, pipelined rotation controller — are out of scope. The `din` port is
where the Gathering Unit's reordered stream would connect, and `dout` is where
the Quantization Unit would attach.

Fig. 11(c)'s area/energy numbers (12.55× FHT logic area vs. 128-way, 1.82×
energy vs. 16-way without TRF) are synthesis results and are not reproduced
here; they would require a 28 nm standard-cell flow.
