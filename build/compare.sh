#!/bin/bash
# usage: build/compare.sh OUT_DIR ADDRESS_FILE   (one address per line)
# Parses the file with the original and the optimized build and requires byte-identical output.
set -e
O="$1/bin"; T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
"$O/original/dump_outputs" "$2" > "$T/original.out"
"$O/optimized/dump_outputs" "$2" > "$T/optimized.out"
n=$(wc -l < "$T/original.out")
if cmp -s "$T/original.out" "$T/optimized.out" && [ "$n" -gt 0 ]; then echo "PASS: $n rows byte-identical (sha256 $(shasum -a 256 < "$T/original.out" | cut -c1-16))"
else echo "FAIL: outputs differ or empty"; exit 1; fi
