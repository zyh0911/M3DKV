#!/usr/bin/env python3
"""
bf16_ref.py -- third, fully independent oracle for the BF16 adder.

Reads the vector file the testbench writes with +dump=<file> (one
"a b sub y" line per operation, all hex) and re-computes every result with
exact rational arithmetic (fractions.Fraction) plus an explicit
round-to-nearest-even quantiser.  No floating point is used anywhere, so the
model cannot inherit a rounding bug from the host FPU.

    ./bf16_ref.py sim/vectors.txt
"""
import sys
from fractions import Fraction

QNAN = 0x7FC0
BIAS = 127
FBITS = 7                      # stored fraction bits
EMIN = 1 - BIAS - FBITS        # exponent of the smallest subnormal quantum


def decode(x):
    """-> ('nan',) | ('inf', sign) | ('num', Fraction)"""
    s = (x >> 15) & 1
    e = (x >> 7) & 0xFF
    f = x & 0x7F
    if e == 0xFF:
        return ('nan',) if f else ('inf', s)
    if e == 0:
        v = Fraction(f) * Fraction(2) ** EMIN
    else:
        v = Fraction(128 + f) * Fraction(2) ** (e - BIAS - FBITS)
    return ('num', -v if s else v)


def round_half_even(n):
    """nearest integer to the Fraction n, ties to even"""
    fl = n.numerator // n.denominator
    rem = n - fl
    if rem > Fraction(1, 2):
        return fl + 1
    if rem < Fraction(1, 2):
        return fl
    return fl if fl % 2 == 0 else fl + 1


def encode(v, zero_sign):
    """quantise the exact Fraction v to a BF16 bit pattern (RNE)"""
    if v == 0:
        return zero_sign << 15
    sign = 1 if v < 0 else 0
    m = abs(v)

    # e = floor(log2(m))
    e = m.numerator.bit_length() - m.denominator.bit_length()
    while Fraction(2) ** e > m:
        e -= 1
    while Fraction(2) ** (e + 1) <= m:
        e += 1

    if e + BIAS < 1:                       # subnormal quantum
        q = Fraction(2) ** EMIN
    else:
        q = Fraction(2) ** (e - FBITS)

    n = round_half_even(m / q)

    if e + BIAS < 1:
        if n < 128:                        # stayed subnormal
            return (sign << 15) | n
        return (sign << 15) | (1 << 7)     # rounded up to the min normal
    exp = e + BIAS
    if n == 1 << (FBITS + 1):              # 0xFF -> 0x100
        n >>= 1
        exp += 1
    if exp > 254:
        return (sign << 15) | 0x7F80       # overflow -> Inf
    return (sign << 15) | (exp << 7) | (n & 0x7F)


def is_snan(x):
    return ((x >> 7) & 0xFF) == 0xFF and (x & 0x7F) != 0 and not (x >> 6) & 1


def bf16_add(a, b, sub):
    """-> (result bits, (nv, of, uf, nx))"""
    da = decode(a)
    db = decode(b)
    if db[0] == 'inf':
        db = ('inf', db[1] ^ sub)
    elif db[0] == 'num':
        db = ('num', -db[1] if sub else db[1])

    nv = is_snan(a) or is_snan(b)

    if da[0] == 'nan' or db[0] == 'nan':
        return QNAN, (nv, 0, 0, 0)
    if da[0] == 'inf' and db[0] == 'inf':
        if da[1] != db[1]:
            return QNAN, (1, 0, 0, 0)          # Inf - Inf is invalid
        return (da[1] << 15) | 0x7F80, (nv, 0, 0, 0)
    if da[0] == 'inf':
        return (da[1] << 15) | 0x7F80, (nv, 0, 0, 0)
    if db[0] == 'inf':
        return (db[1] << 15) | 0x7F80, (nv, 0, 0, 0)

    s = da[1] + db[1]
    # sign of an exact zero: -0 only when both addends are -0
    sa_neg = (a >> 15) & 1
    sb_neg = ((b >> 15) & 1) ^ sub
    zero_sign = 1 if (sa_neg and sb_neg) else 0
    bits = encode(s, zero_sign)

    if s == 0:                                  # exact cancellation: no flags
        return bits, (nv, 0, 0, 0)
    if (bits & 0x7FFF) == 0x7F80:               # rounded up to Inf
        return bits, (nv, 1, 0, 1)
    got = decode(bits)[1]
    nx = 1 if got != s else 0
    # "tiny and inexact".  Every BF16 value is an integer multiple of the
    # smallest subnormal, so a sum can never land between two subnormals --
    # underflow is unreachable for addition.  Checked anyway.
    uf = 1 if (nx and ((bits >> 7) & 0xFF) == 0) else 0
    return bits, (nv, 0, uf, nx)


def is_nan(x):
    return ((x >> 7) & 0xFF) == 0xFF and (x & 0x7F) != 0


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    bad = 0
    bad_fl = 0
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
            exp, flags = bf16_add(a, b, sub)
            n += 1
            if not (is_nan(y) and is_nan(exp)) and y != exp:
                bad += 1
                if bad <= 20:
                    print(f"  MISMATCH a={a:04x} b={b:04x} sub={sub} "
                          f"rtl={y:04x} exact={exp:04x}")
            if len(parts) >= 5:
                got = tuple(int(c) for c in parts[4])
                want = tuple(int(bool(f)) for f in flags)
                if got != want:
                    bad_fl += 1
                    if bad_fl <= 20:
                        print(f"  FLAG MISMATCH a={a:04x} b={b:04x} sub={sub} "
                              f"rtl={''.join(map(str, got))} "
                              f"exact={''.join(map(str, want))} (nv of uf nx)")
    ok = not bad and not bad_fl
    print(f"{'PASS' if ok else 'FAIL'} -- {n} vectors, "
          f"{bad} result mismatches, {bad_fl} flag mismatches")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
