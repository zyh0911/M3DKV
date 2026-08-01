#!/usr/bin/env python3
"""
collect.py -- consolidate the DC runs under out/ into readable PPA tables.

    ./collect.py                 # every run found
    ./collect.py hier            # only runs whose tag contains "hier"
"""
import csv
import os
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")


def read_csv1(path):
    """single-data-row csv -> dict"""
    with open(path) as fh:
        rows = list(csv.DictReader(fh))
    return rows[0] if rows else None


def runs(filt=None):
    for tag in sorted(os.listdir(OUT)):
        d = os.path.join(OUT, tag, "reports")
        if not os.path.isdir(d):
            continue
        if filt and filt not in tag:
            continue
        ppa = os.path.join(d, "ppa.csv")
        if os.path.exists(ppa):
            yield tag, d, read_csv1(ppa)


def f(v, n=2):
    try:
        return "%.*f" % (n, float(v))
    except (TypeError, ValueError):
        return str(v)


def main():
    filt = sys.argv[1] if len(sys.argv) > 1 else None
    rows = list(runs(filt))
    if not rows:
        sys.exit("no runs found under %s" % OUT)

    hdr = ("run", "hier", "target", "achieved", "MHz", "area", "cells",
           "P_dyn", "P_leak", "P_tot", "E/op", "act")
    w = (34, 5, 7, 9, 8, 9, 6, 9, 9, 9, 8, 9)
    print("  ".join(h.rjust(x) for h, x in zip(hdr, w)))
    print("-" * (sum(w) + 2 * (len(w) - 1)))
    for tag, d, p in sorted(rows, key=lambda r: (r[2]["keep_hier"],
                                                 float(r[2]["period"]))):
        vals = (tag, p["keep_hier"], f(p["period"], 0), f(p["achieved"], 1),
                f(p["achieved_mhz"], 0), f(p["area_total"], 3),
                p["leaf_cells"], f(p["p_dynamic_mW"], 4),
                f(p["p_leakage_mW"], 6), f(p["p_total_mW"], 4),
                f(p["energy_op_pJ"], 4), p["saif"])
        print("  ".join(str(v).rjust(x) for v, x in zip(vals, w)))

    print("\narea um^2 (ASAP7 7nm, raw/16), power mW, energy pJ/add")

    # ---- per-unit breakdown for every run that kept the hierarchy ----------
    for tag, d, p in sorted(rows, key=lambda r: float(r[2]["period"])):
        bd = os.path.join(d, "breakdown.csv")
        if not os.path.exists(bd):
            continue
        with open(bd) as fh:
            brows = list(csv.DictReader(fh))
        if len(brows) < 2:
            continue
        tot = brows[-1]
        at, pt = float(tot["area"]), float(tot["p_total_mW"])
        print("\n%s   (%s ps, %s MHz, activity=%s)" %
              (tag, f(p["period"], 0), f(p["achieved_mhz"], 0), p["saif"]))
        print("  %-22s %9s %7s %10s %7s %7s" %
              ("unit", "area", "area%", "power", "power%", "cells"))
        print("  " + "-" * 64)
        sa = sp = 0.0
        for r in brows[:-1]:
            a, pw = float(r["area"]), float(r["p_total_mW"])
            sa += a
            sp += pw
            print("  %-22s %9.4f %6.1f%% %10.6f %6.1f%% %7s" %
                  (r["unit"], a, 100 * a / at, pw, 100 * pw / pt,
                   r["leaf_cells"]))
        print("  %-22s %9.4f %6.1f%% %10.6f %6.1f%%" %
              ("top-level glue", at - sa, 100 * (at - sa) / at,
               pt - sp, 100 * (pt - sp) / pt))
        print("  " + "-" * 64)
        print("  %-22s %9.4f %6s  %10.6f %6s %7s" %
              ("TOTAL", at, "100%", pt, "100%", tot["leaf_cells"]))


if __name__ == "__main__":
    main()
