#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"

TASK_IDENTIFIER="${TASK_IDENTIFIER:-001}"
TASK_SLUG="${TASK_SLUG:-frontend-app-setup}"
BRANCH="agent/${TASK_IDENTIFIER}/${TASK_SLUG}"
WORKTREE="$ROOT/.loop/worktrees/task-${TASK_IDENTIFIER}"

mkdir -p "$ROOT/.loop/worktrees"

if [[ ! -d "$WORKTREE" ]]; then
  git worktree add -b "$BRANCH" "$WORKTREE" HEAD
fi

cd "$WORKTREE"

codex exec \
  --sandbox workspace-write \
  "$(cat .loop/prompt.md)"

./.loop/verify.sh
