#!/usr/bin/env bash

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

echo "==> Codex: implement .loop/task.md"

codex exec \
  --sandbox workspace-write \
  "$(cat .loop/prompt.md)"

echo
echo "==> External verification"

./loop/verify.sh
