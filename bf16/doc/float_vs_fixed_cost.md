# Where the area goes in a BF16 adder — and what a shared-exponent (BFP) FHT would cost

Companion to [fused_vs_two_adders.md](fused_vs_two_adders.md). That document
compares two *floating-point* structures. This one asks a different question:

> In a BF16 adder, how much of the silicon is actually arithmetic, and how much
> is the floating-point envelope around it (align / normalise / round)?

The answer decides whether a Fast Hadamard Transform should be built out of
BF16 adders at all, or out of a shared-exponent block-floating-point (BFP)
datapath with a bare integer adder at each butterfly.

Short version: **~87 % of a BF16 adder is not arithmetic.** The aligner side
costs ~3.6× the bare adder and the normalise/round side ~3.1×. Both of those
are exactly what a multi-stage BFP transform amortises away.

---

## 1. Measured — whole units, identical conditions

ASAP7 7 nm RVT, TT 0.7 V 25 °C. All four are **combinational** tops with the
same port shape (`a, b, sub → y`), synthesised at `CLK_PERIOD=2500`,
`IN_DELAY_F=0 OUT_DELAY_F=0`, `compile_ultra`. At a 2500 ps target every one of
them has hundreds of ps of slack, so DC is optimising for **area** — these are
area-minimised netlists, not minimum-delay ones.

| top | what it is | area µm² | leaf cells | longest path ps | levels |
|---|---|---|---|---|---|
| `bf16_add` | BF16 float add/sub | **44.615** | 640 | 2031.7 | 103 |
| `fxp_addsub16` | 16-bit signed int add/sub, wrapping | **7.698** | 75 | 479.7 | 20 |
| `fxp_addsub16_sat` | 16-bit signed int add/sub, saturating | 8.486 | 81 | 524.2 | 22 |
| `fxp_addsub23` | 23-bit signed int add/sub, wrapping | 11.854 | 138 | 668.1 | 32 |

Ratios, BF16 against the same-word-width integer unit:

| | ratio |
|---|---|
| area | **5.80×** |
| leaf cells | **8.53×** |
| longest path | **4.24×** |

And the 23-bit integer unit — wider than a BF16 word — is still **3.76×**
smaller than the BF16 adder.

The saturating variant costs **+10.2 % area / +9.3 % delay** over wrapping.
See §5 for why that number is worth having.

### Against the *best* float structure, not the naive one

The table above requires one result per unit, which excludes the fused
add-subtract unit (two results). Normalising per result brings it in. The two
corners are directly comparable — `bf16_add` measured as a combinational top
(`cmp_bf16_add`, 44.615 µm²) and as the core inside a registered wrapper
(`bf16_adder_ref_2500ps`, 44.586 µm²) agree to **0.07 %**:

| structure | results | core µm² | **µm² per result** | vs. fixed point |
|---|---|---|---|---|
| `bf16_add` | 1 | 44.615 | 44.62 | 5.80× |
| `bf16_addsub_2x` | 2 | 90.425 | 45.21 | 5.87× |
| **`bf16_addsub_fused`** | 2 | **53.450** | **26.73** | **3.47×** |
| `fxp_addsub16` | 1 | 7.698 | 7.70 | 1× |

This is the number that matters for the FHT question: even against the
best floating-point structure in this repo — the fused unit, already 30 %
smaller than two adders — **a fixed-point add/sub is still 3.5× smaller per
result.** The fused unit closes part of the gap by sharing the aligner and half
the normaliser between its two outputs; it cannot close the rest, because the
remaining align/normalise/round logic is inherent to the format.

(Delay is not comparable across these rows: 2313 ps for the fused unit is a
registered path including flops, against 2032 ps of pure combinational logic
for `bf16_add`.)

> **Do not quote the power or energy columns for these four runs.** They are
> combinational blocks driven by DC's default 0.25 toggle estimate against a
> virtual clock, which is why `fxp_addsub16` comes out *higher* power than
> `bf16_add` in `syn/out/ppa_table.csv`. That is an artifact. Only area and
> delay are comparable across these rows. Real power needs a measured SAIF,
> which only the registered wrapper runs have.

---

## 2. Measured — `bf16_add` split in half

`rtl/probe/bf16_probe_a.v` and `rtl/probe/bf16_probe_b.v` are `bf16_add` cut at
the adder output, code copied verbatim so the logic is representative:

| probe | contents | ports |
|---|---|---|
| A | unpack, magnitude sort/swap, **align**, sticky tree, **add/sub** | `a,b,sub → sum[11:0], sticky, E_l, s_l, s_s` |
| B | LZC, left shift, round, pack, flags | `sum,sticky,E_l,s_l,s_s → y, of,uf,nx` |

Synthesised at `CLK_PERIOD=200` — an unreachable target, so these are
**delay-pushed** netlists with inflated area. Use the *ratio*, not the absolute
µm², and do not mix these numbers with §1.

| | area µm² | cells | path ps | levels | share |
|---|---|---|---|---|---|
| probe A (front, incl. the adder) | 47.093 | 589 | 327.2 | 25 | **59.6 %** |
| probe B (back) | 31.886 | 402 | 295.0 | 25 | **40.4 %** |
| A + B | 78.979 | 991 | — | — | |

Sanity check that the cut is complete: whole `bf16_add` pushed to the same
region (`sweep_bf16_add_comb`, 400–500 ps targets) lands at 78.7–80.2 µm² /
1069–1108 cells. The probes sum to 78.98 µm² / 991 cells — area matches, cell
count is ~7 % low, which is expected: `probe_b`'s header notes it omits the
NaN/Inf special-case mux.

---

## 3. Derived breakdown

Estimating the bare adder inside `bf16_add`: its datapath is 12 bits wide, and
`fxp_addsub16` gives 7.698 µm² for 16 bits → 0.481 µm²/bit → **≈ 5.8 µm² for
12 bits**, i.e. **13.0 %** of the 44.615 µm² unit. (Slightly optimistic: the
real one also subtracts the sticky bit on the effective-subtract path.)

Applying the §2 split ratio to the §1 area — **an approximation, since the
split was measured at a different optimisation corner**:

| block | share of `bf16_add` | µm² | vs. the bare adder |
|---|---|---|---|
| unpack + compare/swap + **align** + sticky | ~46.6 % | ~20.8 | **~3.6×** |
| bare 12-bit add/sub | ~13.0 % | ~5.8 | 1× |
| LZC + left shift + **round** + pack + flags | ~40.4 % | ~18.0 | **~3.1×** |

So yes — the aligner side is several times more expensive than the adder. But
the normalise/round side is nearly as expensive, and that turns out to matter
just as much (§4).

**Unmeasured:** the aligner *alone* is not isolated — probe A bundles it with
unpack, compare/swap and the sticky tree. The 3.6× is a subtraction, not a
measurement. A `probe_align` top would pin it down; see §6.

---

## 4. Projection — 16-point FHT, float tree vs. BFP

A 16-point radix-2 Hadamard transform is 4 stages × 8 butterflies = **32
butterflies = 64 add/sub operations**.

**Float baseline:** 32 × `bf16_addsub_fused` core. Measured core area 53.450
µm² per fused butterfly (from `bf16_addsub_unit_fused_2500ps`, same corner as
§1) → **1710 µm²**.

**BFP:** align all 16 inputs once against the block-max exponent, run 4 stages
of bare integer add/sub at a constant datapath width W, then optionally pack
back to BF16.

### W is not a free parameter

The width budget decomposes as

```
W  =  1 (sign)  +  8 (BF16 significand)  +  D  +  G

  D = headroom below the significand -- how far a smaller element can be
      shifted down and still be represented
  G = growth headroom, 0..4 for a 16-point transform
      (G = 0 is legal if the shared exponent is bumped by 1 per stage, which
       is free in hardware and is the right scaling for a norm-preserving
       transform, at ~0.5 bit/stage of average precision)
```

Bit layout for W = 16, G = 4, D = 3 — the block maximum's significand sits in
bits [10:3], and an element `k` exponents below it is shifted right by `k`:

```
 bit  15 │ 14 13 12 11 │ 10  9  8  7  6  5  4  3 │  2  1  0
    sign │   G = 4     │  significand of the max │  D = 3
```

D therefore sets **two** thresholds, not one:

| | threshold | at W=16, G=4 |
|---|---|---|
| kept at full 8-bit precision | `k ≤ D`, i.e. within `2^-D` of the max | 8× |
| degrades gracefully, `8-(k-D)` bits | `D < k ≤ D+7` | 8× … 1024× |
| truncates to zero | `k > D+7`, i.e. below `2^-(D+7)` | 1024× |

**D is set by the data, and it is the uncomfortable part of this design.** A
Hadamard rotation is applied precisely *because* the input has outliers — but
the alignment happens *before* the transform, on the un-rotated data, where
those outliers are still present. So the in-block dynamic range that must be
retained is the pre-rotation one, and how much that is, is an empirical
question (§6.3) — not something to assert from the width alone.

Area is a strong function of W. Measured: 7.698 µm² at W = 16 and 11.854 µm² at
W = 23 → ≈ 0.594 µm²/bit; the align layer is scaled linearly from the ~10 µm²
estimate at W = 16.

| W | D (G=4) | full prec. to | zero below | compute 64× | align 16× | **BFP out** | vs. float | + pack | vs. float |
|---|---|---|---|---|---|---|---|---|---|
| 16 | 3 | 8× | 1 024× | 493 | 160 | **653** | **2.6×** | 941 | 1.8× |
| 20 | 7 | 128× | 16 384× | 645 | 200 | **845** | **2.0×** | 1133 | 1.5× |
| 23 | 10 | 1 024× | 131 072× | 759 | 230 | **989** | **1.7×** | 1277 | 1.3× |

(`fxp_addsub23` exists in `rtl/probe/fxp_addsub.v` for exactly this row. Its
header claims 23 is "the width the FHT butterfly network actually carries", but
**no derivation for that number is recorded anywhere** — the decomposition
above is a reconstruction, and 23 corresponds to D = 10 under it. Treat 23 as a
plausible operating point, not an established requirement, until §6.3 fixes W
from measured accuracy.)

Taking W = 16 as the headline:

| | area | vs. float tree |
|---|---|---|
| float fused tree | 1710 | 1.0× |
| BFP, output stays BFP/MX | ~653 | **2.6×** |
| BFP, output packed to BF16 | ~941 | **1.8×** |

Two things this projection says:

1. **The win is real but moderate — ~2.6×, not an order of magnitude.** The
   integer adders are cheap individually, but there are 64 of them and only 16
   aligners, so the compute layer (~493 µm²) dominates the BFP design, not the
   alignment.
2. **"Don't pack back to BF16" is worth 288 µm² — 44 % of the BFP design.**
   Keeping the output in shared-exponent form (MX-style: one E8M0 scale per
   block, which is what a downstream quantiser wants anyway) is not a
   footnote, it is a third of the total win. It has to be part of the design,
   not an assumption.

Conservative in the BFP design's favour, i.e. the real number is a bit better:
the FHT needs *hardwired* adders and subtractors, not `fxp_addsub16`'s
add/sub-with-select, which saves the XOR row and carry-in (~10 %) — call it
~595 µm² / 2.9×.

Against the BFP design: constant W = 16 loses ~0.5 bit/stage on average versus
growing the word to 20 bits; growing instead costs ~25 % more compute area.

**Single stage is a different story.** For one isolated butterfly stage BFP
*loses*: 2 aligners (~20) + add + sub (~11.6) + 2 packs (~36) ≈ 67 µm² against
the fused float unit's 53.45. The reason is exactly what §3 shows — the two
expensive blocks are align and normalise/round, and the fused design already
shares both, while a single-stage BFP duplicates them per element. **BFP only
wins when alignment and normalisation are amortised across all 4 stages.**

### What is *not* projected here

- **Delay.** The 479.7 ps for `fxp_addsub16` is from an area-optimised run that
  was never pushed — a 16-bit adder in this library will go far below that.
  The float side's floor is known (~578 ps for `bf16_add`, from
  `sweep_bf16_add_comb`), the integer side's is not. A delay sweep on
  `fxp_addsub16` is needed before claiming any speedup ratio.
- **Energy.** Needs a measured SAIF on real (rotated-activation) stimulus for
  both designs. Random BF16 vectors have a uniformly distributed 8-bit
  exponent, i.e. absurd dynamic range — they would make the float aligner look
  maximally busy and the BFP truncation look maximally bad. Both distortions.
- **Accuracy.** Not an area question, but it gates the whole idea: BFP is not
  bit-exact with a BF16 tree. See §6.
- **Carry-save.** With constant W and no rounding between stages, the 4 stages
  are one signed sum of 16 aligned integers per output — a CSA tree resolving
  in a single carry-propagate adder instead of 4. That would cut both the
  compute area and the delay again, and is not in the numbers above.

---

## 5. What "saturating" means, and why it was measured

`fxp_addsub16` (wrapping) is plain two's-complement:

```verilog
assign y = sub ? (a - b) : (a + b);      // 16 bits in, 16 bits out
```

If the true result does not fit in 16 bits, the carry out of the top bit is
simply discarded. `32767 + 1` becomes `-32768` — the result wraps around and
**the sign flips**. In a Hadamard butterfly network this is the worst possible
failure mode: a single overflow in stage 1 turns into a full-scale error that
the remaining stages then spread across every one of the 16 outputs.

`fxp_addsub16_sat` computes one bit wider and clamps instead:

```verilog
wire signed [16:0] ext = sub ? ({a[15],a} - {b[15],b}) : ({a[15],a} + {b[15],b});
assign y = (ext >  17'sd32767) ? 16'sh7FFF :     // clamp to +max
           (ext < -17'sd32768) ? 16'sh8000 :     // clamp to -min
           ext[15:0];
```

Overflow now costs you the excess magnitude and nothing more — the error is
bounded by the distance to the rail, and the sign is preserved. This is what
essentially every real fixed-point accelerator datapath does.

Cost: **+10.2 % area, +9.3 % delay** (8.486 vs 7.698 µm², 524 vs 480 ps).

It is measured because a BFP FHT has to choose one of three headroom policies,
and this prices two of them:

| policy | cost |
|---|---|
| grow the word 1 bit per stage (16 → 20) | wider adders in later stages, ~25 % more compute area, exact |
| constant width + saturation | +10.2 % on every adder, bounded error on overflow |
| constant width + bump the shared exponent per stage | free in hardware, costs ~0.5 bit of precision per stage |

The third is almost certainly the right answer for a Hadamard transform (the
norm is preserved, so a per-stage exponent bump is exactly the right scaling),
but the saturating number is what makes that a *measured* choice rather than an
assumed one.

---

## 6. Open items

1. **`probe_align`** — isolate the aligner from unpack/swap/sticky so the 3.6×
   in §3 is measured rather than subtracted. Also re-run probes A and B at
   `CLK_PERIOD=2500` so their split can be applied to §1 without a corner
   mismatch.
2. **Delay sweep on `fxp_addsub16`** — establish the integer side's floor so a
   speedup ratio can be stated.
3. **Accuracy study — this is the gate, and it is what fixes W.** The §4
   sensitivity table spans 2.6× down to 1.7× purely on the choice of W, and W
   is set by how much in-block dynamic range the data actually requires. Until
   that is measured on real pre-rotation activations, the headline ratio is
   undetermined. The projection is also worthless if BFP turns out *less*
   accurate than the float tree. The argument that it may be *more* accurate:
   a Hadamard transform mixes all 16 inputs, so per-element relative precision
   (what BF16's 8-bit exponent buys) is destroyed by the transform anyway —
   only precision relative to the block norm survives. Meanwhile BFP's
   intermediate adds are **exactly rounding-free**, where the float tree
   rounds 4 times. Plot output relative error vs. W, with the BF16 tree as a
   horizontal line. If W = 14–16 crosses it, the story closes.
   Must include the adversarial case: one large outlier + 15 tiny values, where
   the tiny ones truncate to zero (i.e. massive activations / attention sinks).
4. **NaN / Inf / subnormal policy** — BFP has none. Needs a stated policy
   (saturate + flag), not silence.
5. **Fair baseline** — the float side must be the 4-stage *fused* tree, not
   4 stages of `bf16_addsub_2x`.

---

## 7. Reproducing

`syn/out/` is gitignored, so the reports behind the tables above are not in the
repo — the numbers here are the record. To regenerate:

```bash
cd bf16/syn
source libs/env_synopsys.sh
source libs/asap7.sh

# §1 -- whole units, area corner
for T in fxp_addsub16 fxp_addsub16_sat fxp_addsub23; do
    RTL_FILES=../rtl/probe/fxp_addsub.v TOP=$T RUN_TAG=cmp_$T \
    CLK_PERIOD=2500 IN_DELAY_F=0 OUT_DELAY_F=0 ./run_syn.sh
done
TOP=bf16_add RUN_TAG=cmp_bf16_add \
    CLK_PERIOD=2500 IN_DELAY_F=0 OUT_DELAY_F=0 ./run_syn.sh

# §2 -- the split, delay corner
RTL_FILES=../rtl/probe/bf16_probe_a.v TOP=bf16_probe_a RUN_TAG=probe_a \
    CLK_PERIOD=200 IN_DELAY_F=0 OUT_DELAY_F=0 ./run_syn.sh
RTL_FILES=../rtl/probe/bf16_probe_b.v TOP=bf16_probe_b RUN_TAG=probe_b \
    CLK_PERIOD=200 IN_DELAY_F=0 OUT_DELAY_F=0 ./run_syn.sh

python3 collect_ppa.py out
```

The probe and fixed-point sources are analysis-only — they are not part of the
design and are not simulated by any testbench. They live in `rtl/probe/` for
that reason.
