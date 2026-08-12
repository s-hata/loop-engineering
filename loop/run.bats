#!/usr/bin/env bats

load test_helper

@test "run creates a worktree, invokes codex, and verifies it" {
  mkdir -p "${FIXTURE_ROOT}/.loop" "${FIXTURE_ROOT}/bin"
  printf '%s\n' 'implement the task' >"${FIXTURE_ROOT}/.loop/prompt.md"
  cat >"${FIXTURE_ROOT}/.loop/verify.sh" <<'VERIFY'
#!/usr/bin/env bash
set -euo pipefail
touch "${PWD}/verify-ran"
VERIFY
  chmod +x "${FIXTURE_ROOT}/.loop/verify.sh"
  cat >"${FIXTURE_ROOT}/bin/codex" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail
touch "${PWD}/codex-ran"
CODEX
  chmod +x "${FIXTURE_ROOT}/bin/codex"
  git -C "${FIXTURE_ROOT}" add .loop
  git -C "${FIXTURE_ROOT}" commit -qm "fixture runner files"

  run env "PATH=${FIXTURE_ROOT}/bin:${PATH}" "${FIXTURE_ROOT}/loop/run.sh"

  [ "${status}" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.loop/worktrees/task-001/codex-ran" ]
  [ -f "${FIXTURE_ROOT}/.loop/worktrees/task-001/verify-ran" ]
}
