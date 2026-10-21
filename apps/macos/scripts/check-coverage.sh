#!/usr/bin/env bash
# Enforces NFR-09 over the profile `swift test --enable-code-coverage` just wrote.
set -euo pipefail
# A decimal comma from the locale would break the comparison below.
export LC_ALL=C
kit="$(cd "$(dirname "$0")/../Packages/DocketKit" && pwd)"
bin="$(swift build --package-path "$kit" --show-bin-path)"
profile="$bin/codecov/default.profdata"

# SwiftPM builds one bundle per test target; llvm-cov reads them all as one report.
objects=()
for bundle in "$bin"/*Tests.xctest; do
  name=$(basename "$bundle" .xctest)
  [ ${#objects[@]} -gt 0 ] && objects+=(-object)
  objects+=("$bundle/Contents/MacOS/$name")
done
if [ ${#objects[@]} -eq 0 ]; then
  echo "no test bundles in $bin"; exit 1
fi

# percent <path>: line coverage of the sources under <path>, from llvm-cov's TOTAL row
# (column 8 is lines, column 9 missed lines).
percent() {
  xcrun llvm-cov report "${objects[@]}" -instr-profile "$profile" "$1" \
    | awk '$1 == "TOTAL" && $8 > 0 { printf "%.2f", ($8 - $9) * 100 / $8 }'
}

status=0
check() { # check <label> <path> <minimum>
  local got; got=$(percent "$2")
  if [ -z "$got" ]; then
    echo "$1: no coverage data for $2"; status=1
  elif awk -v g="$got" -v m="$3" 'BEGIN { exit !(g < m) }'; then
    echo "$1: $got% lines, below $3%"; status=1
  else
    echo "$1: $got% lines (minimum $3%)"
  fi
}

check "DocketActivity" "$kit/Sources/DocketActivity" 90
check "DocketKit" "$kit/Sources" 75
exit $status
