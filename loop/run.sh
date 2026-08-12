#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"

TASK_ID="${TASK_ID:-task-001}"
BRANCH="loop/$TASK_ID"
WORKTREE="$ROOT/.loop/worktrees/$TASK_ID"

mkdir -p "$ROOT/.loop/worktrees"

if [[ ! -d "$WORKTREE" ]]; then
  git worktree add -b "$BRANCH" "$WORKTREE" HEAD
fi

cd "$WORKTREE"

codex exec \
  --sandbox workspace-write \
  "$(cat .loop/prompt.md)"

./.loop/verify.sh
