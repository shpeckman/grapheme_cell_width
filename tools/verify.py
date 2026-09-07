#!/usr/bin/env python3
# tools/verify.py
import sys
import unicodedata as ud

EXPLICIT_ZERO = [
    (0x200B, 0x200D),
    (0x2060, 0x2060),
    (0xFEFF, 0xFEFF),
    (0x1160, 0x11FF),
    (0xD7B0, 0xD7FF),
    (0x1F3FB, 0x1F3FF),
    (0xE0001, 0xE007F),
]

def expected(cp):
    ch = chr(cp)
    if ud.category(ch) in ("Mn", "Me"):
        return 0
    if any(first <= cp <= last for first, last in EXPLICIT_ZERO):
        return 0
    return 2 if ud.east_asian_width(ch) in ("W", "F") else 1

def into_ranges(cps):
    if not cps:
        return []
    ranges = []
    start = prev = cps[0]
    for cp in cps[1:]:
        if cp == prev + 1:
            prev = cp
        else:
            ranges.append((start, prev))
            start = prev = cp
    ranges.append((start, prev))
    return ranges

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "widths.tsv"
    mismatches = []
    checked = 0
    with open(path) as f:
        for line in f:
            cp_s, w_s = line.split()
            cp, got = int(cp_s), int(w_s)
            if got != expected(cp):
                mismatches.append((cp, got, expected(cp)))
            checked += 1

    print(f"unicodedata UCD version: {ud.unidata_version}")
    print(f"checked {checked} scalar values, {len(mismatches)} mismatches")

    if mismatches:
        print("\nmismatch ranges (cp range, shard width, python width):")
        by_kind = {}
        for cp, got, exp in mismatches:
            by_kind.setdefault((got, exp), []).append(cp)
        for (got, exp), cps in sorted(by_kind.items()):
            for first, last in into_ranges(cps):
                print(f"  U+{first:04X}..U+{last:04X}  shard={got}  python={exp}")

if __name__ == "__main__":
    main()