#!/usr/bin/env bash
# scripts/check-push.sh — run by lefthook's pre-push before scripts/ci.sh.
# stdin carries one line per ref: <local ref> <local sha> <remote ref> <remote sha>
set -euo pipefail
head=$(git rev-parse HEAD)
zero=0000000000000000000000000000000000000000

while read -r local_ref local_sha remote_ref _; do
  if [ "$remote_ref" = "refs/heads/main" ]; then
    echo "refusing to push to main: open a pull request (docs/06-engineering-practices.md §6)" >&2
    exit 1
  fi
  [ "$local_sha" = "$zero" ] && continue # deleting a remote branch
  if [ "$local_sha" != "$head" ]; then
    echo "refusing to push $local_ref: scripts/ci.sh checks HEAD, and $local_ref is not HEAD" >&2
    exit 1
  fi
done

if [ -n "$(git status --porcelain)" ]; then
  echo "refusing to push with uncommitted changes: scripts/ci.sh would check files" \
    "the push does not contain" >&2
  exit 1
fi
