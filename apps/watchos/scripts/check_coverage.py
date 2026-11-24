#!/usr/bin/env python3
"""Line-coverage gate for the watch app's host-tested logic files.

Reads the llvm-cov JSON export produced by `swift test --enable-code-coverage`
(path from `swift test --show-codecov-path`) and fails when any gated file, or
their total, is below the threshold.

Usage: check_coverage.py <codecov.json> <min_percent> <file suffix>...
"""

import json
import sys


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2

    report_path, minimum = sys.argv[1], float(sys.argv[2])
    suffixes = sys.argv[3:]

    with open(report_path, encoding="utf-8") as handle:
        files = [f for d in json.load(handle)["data"] for f in d["files"]]

    failed = False
    total_covered = total_count = 0
    for suffix in suffixes:
        matches = [f for f in files if f["filename"].endswith(suffix)]
        if not matches:
            print(f"MISSING  {suffix}: no coverage data", file=sys.stderr)
            failed = True
            continue
        lines = matches[0]["summary"]["lines"]
        covered, count = lines["covered"], lines["count"]
        total_covered += covered
        total_count += count
        percent = 100.0 * covered / count if count else 100.0
        status = "OK  " if percent >= minimum else "FAIL"
        failed |= percent < minimum
        print(f"{status}  {percent:6.2f}%  ({covered}/{count})  {suffix}")

    total = 100.0 * total_covered / total_count if total_count else 0.0
    print(f"TOTAL   {total:6.2f}%  ({total_covered}/{total_count})  minimum {minimum:.2f}%")
    if total < minimum:
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
