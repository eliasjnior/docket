#!/usr/bin/env bash
# The two target boundaries SwiftPM cannot see (docs/03-architecture.md §3).
set -euo pipefail
macos="$(cd "$(dirname "$0")/.." && pwd)"
sources="$macos/Packages/DocketKit/Sources"
status=0

# code <dir>: Swift lines of <dir> without line comments, as file:line:text.
code() {
  [ -d "$1" ] || return 0
  grep -rn --include='*.swift' -v -E '^[[:space:]]*//' "$1" || true
}

pure_imports() { # pure_imports <target> <allowed module regex>
  local hits
  hits=$(code "$sources/$1" | grep -E ':[[:space:]]*(@testable[[:space:]]+)?import[[:space:]]' \
    | grep -v -E "import[[:space:]]+($2)[[:space:]]*\$" || true)
  if [ -n "$hits" ]; then
    echo "$1 may import only $2:"; echo "$hits"; status=1
  fi
}

pure_apis() { # pure_apis <target>
  local hits
  hits=$(code "$sources/$1" \
    | grep -E '\b(URLSession|FileManager|Process|UserDefaults)\b|Date\(\)|Date\.now|\.random\b' || true)
  if [ -n "$hits" ]; then
    echo "$1 performs no I/O and reads no clock or randomness (non-negotiable 3):"; echo "$hits"; status=1
  fi
}

pure_imports DocketCore 'Foundation'
pure_imports DocketActivity 'Foundation|DocketCore'
pure_apis DocketCore
pure_apis DocketActivity

hits=$(code "$macos/App/Sources" | grep -v "^$macos/App/Sources/Environment/" \
  | grep -E ':[[:space:]]*import[[:space:]]+(DocketGitHub|DocketNotify|DocketPersistence)\b' || true)
if [ -n "$hits" ]; then
  echo "only App/Sources/Environment/ may import an adapter:"; echo "$hits"; status=1
fi

exit $status
