#!/usr/bin/env python3
"""
collect_ppa.py -- gather every reports/ppa.csv under a directory tree and print
a single PPA table (and write ppa_table.csv next to the root).

    ./collect_ppa.py out/sweep_bf16_adder_p2
    ./collect_ppa.py out                      # everything
"""
import csv
import os
import sys

# column key -> (header template, width, decimals; None = leave as-is)
# {t} is replaced by the library time unit, {a} by the area unit.
COLUMNS = [
    ("top",              "design",     12, None),
    ("pipe",             "PIPE",        6, None),
    ("period",           "Tclk[{t}]",  10, None),
    ("achieved",         "achv[{t}]",  10, 1),
    ("achieved_mhz",     "Fmax[MHz]",  10, 1),
    ("wns",              "WNS[{t}]",   10, 1),
    ("logic_levels",     "levels",      8, None),
    ("area_total",       "area[{a}]",  12, 2),
    ("area_core",        "core",       10, 2),
    ("area_seq",         "seq",         9, 2),
    ("registers",        "regs",        6, None),
    ("leaf_cells",       "cells",       7, None),
    ("p_dynamic_mW",     "Pdyn[mW]",   10, 4),
    ("p_leakage_mW",     "Pleak[mW]",  11, 5),
    ("p_total_mW",       "Ptot[mW]",   10, 4),
    ("throughput_Mops",  "Madd/s",     10, 1),
    ("energy_op_pJ",     "E/add[pJ]",  11, 4),
    ("saif",             "activity",   10, None),
]


def fmt(value, decimals):
    if decimals is None:
        return str(value)
    try:
        return f"{float(value):.{decimals}f}"
    except (TypeError, ValueError):
        return str(value)


def find_csvs(root):
    hits = []
    for dirpath, _dirs, files in os.walk(root):
        if "ppa.csv" in files:
            hits.append(os.path.join(dirpath, "ppa.csv"))
    return sorted(hits)


def load(path):
    with open(path, newline="") as fh:
        rows = list(csv.DictReader(fh))
    return rows[0] if rows else None


def sort_key(row):
    try:
        return (row.get("top", ""), row.get("pipe", ""),
                float(row.get("period", "inf")))
    except ValueError:
        return (row.get("top", ""), row.get("pipe", ""), float("inf"))


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "out"
    if not os.path.isdir(root):
        sys.exit(f"no such directory: {root}")

    csvs = find_csvs(root)
    if not csvs:
        sys.exit(f"no reports/ppa.csv found under {root} -- did synthesis run?")

    rows = [r for r in (load(p) for p in csvs) if r]
    rows.sort(key=sort_key)

    tu = rows[0].get("time_unit", "ns")
    au = rows[0].get("area_unit", "um2")
    header = "".join(f"{h.format(t=tu, a=au):>{w}} " for _k, h, w, _d in COLUMNS)
    rule = "-" * len(header)
    print(rule)
    print(f" BF16 adder PPA -- {len(rows)} run(s) under {root}")
    print(rule)
    print(header)
    print(rule)
    for r in rows:
        print("".join(f"{fmt(r.get(k, 'n/a'), d):>{w}} " for k, _h, w, d in COLUMNS))
    print(rule)

    bad = []
    for r in rows:
        try:
            if float(r.get("wns", "0")) < 0:
                bad.append(f"{r.get('top')}@{r.get('period')}{tu} "
                           f"(WNS {r.get('wns')} {tu})")
        except ValueError:
            pass
    if bad:
        print(" TIMING NOT MET: " + ", ".join(bad))
        print(" -> Fmax is the achieved column of the fastest run that DOES meet timing.")
        print(rule)

    out_csv = os.path.join(root, "ppa_table.csv")
    all_keys = sorted({k for r in rows for k in r})
    with open(out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=all_keys)
        w.writeheader()
        w.writerows(rows)
    print(f" wrote {out_csv}")


if __name__ == "__main__":
    main()
