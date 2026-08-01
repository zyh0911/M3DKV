#!/usr/bin/env python3
"""
bf16_ref.py -- third, fully independent oracle for the single-path BF16 adder.

Reads the vector file the testbench writes with +dump=<file> (one "a b sub y"
line per operation, all hex) and re-computes every result with exact rational
arithmetic (fractions.Fraction).  No floating point is used anywhere, so the
model cannot inherit a rounding bug from the host FPU, and nothing is shared
with the Verilog reference model beyond the format itself.

The DUT is not IEEE-754.  Its conventions, reproduced here:
  - no subnormals : e == 0 is +/-0 and the fraction field is ignored
  - no Inf / NaN  : an all-ones exponent is out of spec and never appears
  - round toward zero (truncation)
  - overflow clamps to the largest finite number instead of Inf
  - every zero result is +0

    ./bf16_ref.py build/vectors.txt
"""
import sys
from fractions import Fraction

BIAS = 127
FBITS = 7                      # stored fraction bits
EMAX = 254                     # largest legal exponent field
MAXFINITE = (EMAX << FBITS) | 0x7F


def decode(x):
    """-> exact Fraction; e == 0 is zero whatever the fraction field says"""
    s = (x >> 15) & 1
    e = (x >> 7) & 0xFF
    f = x & 0x7F
    if e == 0xFF:
        raise ValueError(f"{x:04x}: all-ones exponent is out of spec")
    if e == 0:
        return Fraction(0)
    v = Fraction(128 + f) * Fraction(2) ** (e - BIAS - FBITS)
    return -v if s else v


def encode(v):
    """quantise the exact Fraction v, round toward zero"""
    if v == 0:
        return 0                           # every zero result is +0
    sign = 1 if v < 0 else 0
    m = abs(v)

    # e = floor(log2(m))
    e = m.numerator.bit_length() - m.denominator.bit_length()
    while Fraction(2) ** e > m:
        e -= 1
    while Fraction(2) ** (e + 1) <= m:
        e += 1

    exp = e + BIAS
    if exp > EMAX:                         # overflow -> largest finite
        return (sign << 15) | MAXFINITE
    if exp < 1:                            # no subnormals -> flush to +0
        return 0

    # truncation can only lower the significand, so it can never push the
    # exponent up a binade the way rounding to nearest can
    n = (m / Fraction(2) ** (e - FBITS)).numerator // \
        (m / Fraction(2) ** (e - FBITS)).denominator
    return (sign << 15) | (exp << 7) | (n & 0x7F)


def bf16_add(a, b, sub):
    """-> result bits"""
    va = decode(a)
    vb = decode(b)
    if sub:
        vb = -vb
    return encode(va + vb)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    bad = 0
    n = 0
    with open(sys.argv[1]) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) < 4:
                continue
            a = int(parts[0], 16)
            b = int(parts[1], 16)
            sub = int(parts[2], 2)
            y = int(parts[3], 16)
            exp = bf16_add(a, b, sub)
            n += 1
            if y != exp:
                bad += 1
                if bad <= 20:
                    print(f"  MISMATCH a={a:04x} b={b:04x} sub={sub} "
                          f"rtl={y:04x} exact={exp:04x}")
    print(f"{'PASS' if not bad else 'FAIL'} -- {n} vectors, {bad} mismatches")
    sys.exit(0 if not bad else 1)


if __name__ == "__main__":
    main()
