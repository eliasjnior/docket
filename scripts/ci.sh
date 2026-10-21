#!/usr/bin/env bash
# Every check Docket has. Run by lefthook's pre-push, and by hand as `pnpm run ci`.
# CI_FAST=1 omits the xcodebuild build of the app.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

macos=apps/macos
kit=$macos/Packages/DocketKit

failed=()
run() { # run <name> <command...>
  local name="$1"; shift
  printf '\n\033[1m── %s\033[0m\n' "$name"
  if "$@"; then
    printf '\033[32m   ok\033[0m\n'
  else
    printf '\033[31m   FAILED\033[0m\n'
    failed+=("$name")
    return 1
  fi
}
skip() { printf '\n\033[1m── %s\033[0m\n\033[33m   skipped — %s\033[0m\n' "$1" "$2"; }

swift_format_lint() {
  local paths=() p
  for p in App scripts Packages/DocketKit/Sources Packages/DocketKit/Tests \
    Packages/DocketKit/Package.swift; do
    [ -e "$macos/$p" ] && paths+=("$p")
  done
  (cd "$macos" && swift format lint --strict --recursive "${paths[@]}")
}
swiftlint_lint() { (cd "$macos" && swiftlint lint --strict --quiet); }

# The branch's own commits: everything since it left origin/main. No fetch, so a push stays offline.
base=""
if git rev-parse --verify --quiet origin/main >/dev/null; then
  base=$(git merge-base origin/main HEAD)
fi

run "biome" pnpm exec biome ci .

if [ -z "$(git ls-files -- '*.swift')" ]; then
  skip "swift-format" "no Swift sources yet"
  skip "swiftlint" "no Swift sources yet"
else
  run "swift-format" swift_format_lint
  run "swiftlint" swiftlint_lint
fi

if [ -x "$macos/scripts/check-imports.sh" ]; then
  run "target boundaries" "$macos/scripts/check-imports.sh"
else
  skip "target boundaries" "$macos/scripts/check-imports.sh does not exist yet"
fi

if [ -n "${CI_FAST:-}" ]; then
  skip "app build" "CI_FAST=1"
elif [ ! -f "$macos/project.yml" ]; then
  skip "app build" "no $macos/project.yml yet"
else
  run "app build" make -C "$macos" build
fi

if [ ! -f "$kit/Package.swift" ]; then
  skip "kit tests" "no $kit/Package.swift yet"
  skip "coverage" "no kit yet"
elif run "kit tests" swift test --package-path "$kit" --enable-code-coverage; then
  if [ -x "$macos/scripts/check-coverage.sh" ]; then
    run "coverage" "$macos/scripts/check-coverage.sh"
  else
    skip "coverage" "$macos/scripts/check-coverage.sh does not exist yet"
  fi
else
  skip "coverage" "kit tests failed, so there is no profile to read"
fi

if [ -z "$base" ]; then
  skip "commit messages" "no origin/main yet"
  skip "secrets in commits" "no origin/main yet"
else
  run "commit messages" pnpm exec commitlint --from "$base" --to HEAD --verbose
  run "secrets in commits" gitleaks git --log-opts="$base..HEAD" --redact --no-banner .
fi

if [ ${#failed[@]} -gt 0 ]; then
  printf '\n\033[31m%d job(s) failed: %s\033[0m\n' "${#failed[@]}" "${failed[*]}"
  exit 1
fi
printf '\n\033[32mall checks passed\033[0m\n'
