# Fused BF16 add-subtract unit vs. two independent adders

> Both structures compared here are floating-point. For the cost breakdown
> *inside* a BF16 adder — how much of it is arithmetic vs. align/normalise/round
> — and what a shared-exponent fixed-point (BFP) FHT would cost instead, see
> [float_vs_fixed_cost.md](float_vs_fixed_cost.md).

Both designs take two BF16 operands and produce **both** `a+b` and `a-b` every
cycle. They differ only in how the datapath is built:

| | RTL | what it is |
|---|---|---|
| baseline | `rtl/bf16_addsub_2x.v` | two `bf16_add` instances, one wired `sub=0`, one `sub=1` |
| fused | `rtl/bf16_addsub_fused.v` | one shared front end, one dedicated magnitude-adder and one dedicated magnitude-subtracter |

`rtl/bf16_addsub_unit.v` wraps either core in the *same* register stage
(`FUSED=1/0`, `PIPE=2`), so a DC run of one against the other differs only in
the core.

---

## 1. Why fusing works

The whole design rests on one structural fact:

> For a fixed pair of operands, **exactly one** of `{a+b, a-b}` is an effective
> addition of magnitudes and the other is an effective subtraction — never two
> additions, never two subtractions.

With `L` the larger-magnitude operand and `S` the smaller:

| | `a + b` | `a - b` |
|---|---|---|
| `sign(a) == sign(b)` | \|L\| + \|S\| | \|L\| − \|S\| |
| `sign(a) != sign(b)` | \|L\| − \|S\| | \|L\| + \|S\| |

So instead of two *general* adders — each of which must be able to do either
operation, and therefore carries the hardware for both — the fused unit builds
one adder and one subtracter and swaps them onto the two outputs with a mux
driven by `sign(a) == sign(b)`.

Two second-order consequences make the saving bigger than "share the front end":

- **The add path cannot need a left shift.** A magnitude sum never loses
  leading bits, so normalisation is at most a 1-bit *right* shift. No
  leading-zero counter, no left shifter — where a general adder needs both.
- **The subtract path cannot carry out.** `|L| − |S| ≤ |L|`, so there is no
  right-shift path at all, only the LZ count and left shifter.

### What is shared and what is not

| block | baseline | fused |
|---|---|---|
| unpack / classify | ×2 | **×1** |
| magnitude compare + swap network | ×2 | **×1** |
| exponent difference | ×2 | **×1** |
| variable right shifter (aligner) | ×2 | **×1** |
| sticky OR-tree | ×2 | **×1** |
| add / subtract | ×2 general (add **and** sub) | 1 adder + 1 subtracter |
| leading-zero count + left shifter | ×2 | **×1** (subtract path only) |
| 1-bit right-shift normaliser | ×2 | **×1** (add path only) |
| rounder | ×2 | ×2 |
| exponent adjust + packer | ×2 | ×2 |
| output routing muxes | — | added |

The magnitude sort is shared because it depends on `|a|` and `|b|` only —
flipping `b`'s sign for the subtraction does not change which operand is
larger. That is what lets the single aligner serve both results.

---

## 2. Correctness

Both cores are bit-identical on every vector checked — results *and* all four
IEEE status flags:

```
make sim-as        PASS -- 1213272 checks, 0 mismatches
make oracle-as     PASS -- 50000 vectors, 0 result mismatches, 0 flag mismatches
```

`tb/tb_bf16_addsub.v` drives both cores in lockstep and checks three things per
vector: `y_sum` against the 64-bit reference model, `y_diff` against it, and
fused ≡ baseline bit-for-bit including flags. Coverage is the same as for the
plain adder: 13 directed specials, the 432-operand cross product (373 k
checks), 400 k random pairs (half with correlated exponents), and 20 k vectors
through both pipelined wrappers. `make oracle-as` re-checks 50 000 of the
fused unit's own outputs against exact rational arithmetic in Python.

Since the baseline is built from `bf16_add`, which is itself verified against
the reference model and the exact oracle, "identical to the baseline" is a
strong statement.

---

## 3. PPA at 400 MHz

ASAP7 7 nm RVT, TT 0.7 V 25 °C. `CLK_PERIOD = 2500 ps`, `compile_ultra`,
hierarchy preserved. Power from a **measured** SAIF — both variants driven with
the identical 20 000-vector stimulus (same seed, same sequence).

| | two adders | **fused** | delta |
|---|---|---|---|
| total cell area | 121.71 µm² | **84.74 µm²** | **−30.4 %** |
| core area (excl. registers) | 90.43 µm² | **53.45 µm²** | **−40.9 %** |
| leaf cells | 1442 | **954** | −33.8 % |
| registers | 74 | 74 | — |
| total power | 0.1435 mW | **0.1066 mW** | **−25.7 %** |
| ├ internal | 0.0743 mW | 0.0623 mW | −16.2 % |
| └ switching | 0.0692 mW | 0.0441 mW | −36.3 % |
| energy / result | 0.1794 pJ | **0.1333 pJ** | −25.7 % |
| throughput | 800 Mresult/s | 800 Mresult/s | — |
| WNS @ 2500 ps | +375.9 ps | +186.5 ps | both meet |
| longest path | 2124 ps | 2313 ps | +8.9 % |
| levels of logic | 101 | 108 | +7 |

Scaled against a single `bf16_adder` synthesised in the same conditions
(67.84 µm² total, 44.59 µm² core, 0.0867 mW, 1 result/cycle):

| | core area vs. one adder | results / cycle |
|---|---|---|
| one `bf16_add` | 1.00× | 1 |
| two adders | 2.03× | 2 |
| **fused** | **1.20×** | **2** |

Two adders cost almost exactly twice one adder, as expected. The fused unit
buys the second result for **20 % more area**, not 100 %.

### Can the tool find this by itself?

The baseline keeps its two adders in separate hierarchies, so DC cannot merge
them. Re-running both with `KEEP_HIER=0` lets `compile_ultra` ungroup
everything and share whatever common logic it can find:

| | two adders, flat | fused, flat |
|---|---|---|
| total cell area | 106.61 µm² | **82.03 µm²** (−23.1 %) |
| leaf cells | 1193 | 917 |
| total power | 0.1278 mW | **0.1045 mW** (−18.2 %) |
| energy / result | 0.1598 pJ | **0.1306 pJ** |

Ungrouping recovers part of the gap — DC does find ~12 % of redundancy on its
own (121.7 → 106.6 µm²) — but it cannot restructure the two general adders into
an adder plus a subtracter. **The remaining 23 % is architectural**, and it is
the part that only the RTL can express.

Note the fused design barely benefits from ungrouping (84.7 → 82.0 µm²): there
is little redundancy left to find, which is the point.

---

## 4. Caveats

- **"Longest path" is not Fmax.** At a 2500 ps target both designs have
  hundreds of ps of slack, so `compile_ultra` optimises for area and stops
  improving timing. The 2124 / 2313 ps numbers are the longest paths in
  *area-minimised* netlists, not the minimum periods these designs can reach.
  The +8.9 % is consistent with the fused unit's extra output-routing muxes,
  but a frequency sweep would be needed to state Fmax for either. At 400 MHz
  the question does not arise — both have >7 % … 15 % margin.
- Pre-CTS hold WNS is −95.5 ps in **every** run including the single adder;
  that is an artifact of an ideal clock network at a relaxed period with no
  hold fixing, and it is identical across the comparison.
- ASAP7 is a predictive PDK and the shipped `.db` is the TT corner, so absolute
  numbers are typical-case. The *ratios* between the two designs are measured
  under identical conditions and are the meaningful result here.
- Areas are pre-layout cell areas with no wire-load model. The fused unit's
  advantage would likely grow slightly after P&R (fewer cells, less
  interconnect), but that is not measured here.

---

## 5. Reproducing

```bash
cd bf16
source syn/libs/env_synopsys.sh

make sim-as && make oracle-as          # verify the fused unit

cd syn
source libs/asap7.sh
DUT=bf16_addsub_fused ./gen_saif.sh    # measured activity, both variants
DUT=bf16_addsub_2x    ./gen_saif.sh

export CLK_PERIOD=2500                 # 400 MHz, ASAP7 time unit is ps
TOP=bf16_addsub_unit PARAM_FUSED=1 \
    SAIF_FILE=$PWD/sim/bf16_addsub_fused.saif ./run_syn.sh
TOP=bf16_addsub_unit PARAM_FUSED=0 \
    SAIF_FILE=$PWD/sim/bf16_addsub_2x.saif    ./run_syn.sh

# add KEEP_HIER=0 to either line for the ungrouped experiment
python3 collect_ppa.py out
```

Reports for the runs quoted above:

```
syn/out/bf16_addsub_unit_fused_2500ps/reports/
syn/out/bf16_addsub_unit_2x_2500ps/reports/
syn/out/addsub_fused_flat_2500ps/reports/
syn/out/addsub_2x_flat_2500ps/reports/
syn/out/bf16_adder_ref_2500ps/reports/
```
