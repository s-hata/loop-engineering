#!/usr/bin/env bats

load test_helper

setup_codex_stub() {
  mkdir -p "${FIXTURE_ROOT}/bin"
  git init --bare -q "${FIXTURE_ROOT}/remote.git"
  git -C "${FIXTURE_ROOT}" remote add origin "${FIXTURE_ROOT}/remote.git"
  git -C "${FIXTURE_ROOT}" push -q origin main

  cat >"${FIXTURE_ROOT}/bin/gh" <<'GH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${GH_ARGS_LOG}"

if [[ "${1:-}" == 'pr' && "${2:-}" == 'view' ]]; then
  if [[ -f "${GH_PR_FILE}" ]]; then
    printf '%s\n' "https://github.com/example/loop-engineering/pull/1"
    exit 0
  fi
  exit 1
fi

if [[ "${1:-}" == 'pr' && "${2:-}" == 'create' ]]; then
  body_file=''
  previous=''
  for argument in "$@"; do
    if [[ "${previous}" == '--body-file' ]]; then
      body_file="${argument}"
    fi
    previous="${argument}"
  done
  if [[ -n "${body_file}" ]]; then
    cp "${body_file}" "${GH_BODY_LOG}"
  fi
  if [[ "${GH_FAIL_CREATE_FIRST:-0}" == '1' && ! -f "${GH_FAIL_FILE}" ]]; then
    touch "${GH_FAIL_FILE}"
    exit 1
  fi
  touch "${GH_PR_FILE}"
  printf '%s\n' "https://github.com/example/loop-engineering/pull/1"
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 2
GH
  chmod +x "${FIXTURE_ROOT}/bin/gh"

  cat >"${FIXTURE_ROOT}/bin/codex" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${CODEX_ARGS_LOG}"
message_file=''
previous=''
for argument in "$@"; do
  if [[ "${previous}" == '--output-last-message' ]]; then
    message_file="${argument}"
  fi
  previous="${argument}"
done

if [[ -n "${message_file}" ]]; then
  cat >"${CODEX_STDIN_LOG}"
  verifier_count=0
  if [[ -f "${CODEX_VERDICT_COUNT}" ]]; then
    verifier_count="$(cat "${CODEX_VERDICT_COUNT}")"
  fi
  verifier_count=$((verifier_count + 1))
  printf '%s\n' "${verifier_count}" >"${CODEX_VERDICT_COUNT}"
  if [[ "${CODEX_FAIL_FIRST:-0}" == '1' && "${verifier_count}" -eq 1 ]]; then
    printf '%s\n' 'VERDICT: FAIL' 'FINDINGS:' '- [high] agent-change.txt:1 - review fixture failure' >"${message_file}"
  else
    printf '%s\n' 'VERDICT: PASS' 'FINDINGS:' '- none' >"${message_file}"
  fi
else
  printf '%s\n' 'implemented by codex stub' >"${PWD}/agent-change.txt"
fi
CODEX
  chmod +x "${FIXTURE_ROOT}/bin/codex"
  export CODEX_ARGS_LOG="${FIXTURE_ROOT}/codex.args"
  export CODEX_STDIN_LOG="${FIXTURE_ROOT}/codex.stdin"
  export CODEX_VERDICT_COUNT="${FIXTURE_ROOT}/codex.verdict-count"
  export GH_ARGS_LOG="${FIXTURE_ROOT}/gh.args"
  export GH_BODY_LOG="${FIXTURE_ROOT}/gh.body"
  export GH_PR_FILE="${FIXTURE_ROOT}/gh.pr-created"
  export GH_FAIL_FILE="${FIXTURE_ROOT}/gh.fail-create"
}

add_health_task() {
  mkdir -p "${FIXTURE_ROOT}/.loop/tasks"
  cat >"${FIXTURE_ROOT}/.loop/tasks/task-001-add-health-endpoint.md" <<'TASK'
---
title: Add health endpoint
base_branch: main
max_attempts: 5
test_command: test -f agent-change.txt
---
Add GET /health.
TASK

  "${FIXTURE_ROOT}/loop/loop.sh" add \
    "${FIXTURE_ROOT}/.loop/tasks/task-001-add-health-endpoint.md" >/dev/null
}

@test "verifier failure returns to a repair attempt" {
  setup_codex_stub

  add_health_task

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "CODEX_VERDICT_COUNT=${CODEX_VERDICT_COUNT}" \
    CODEX_FAIL_FIRST=1 \
    "${FIXTURE_ROOT}/loop/loop.sh" run

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "VERIFIER FAILED"
  assert_contains "${output}" "TASK COMPLETE"

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT status || '|' || attempt FROM tasks WHERE id = 1;"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'completed|2' ]
}

@test "loop run completes a queued task end to end" {
  setup_codex_stub

  add_health_task

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "${FIXTURE_ROOT}/loop/loop.sh" run

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "TEST GATE PASSED"
  assert_contains "${output}" "VERIFIER PASSED"
  assert_contains "${output}" "TASK COMPLETE"
  assert_file_contains "${CODEX_ARGS_LOG}" "Add GET /health"
  assert_file_contains "${CODEX_ARGS_LOG}" "--sandbox read-only"
  assert_file_contains "${CODEX_STDIN_LOG}" "agent-change.txt"

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT status || '|' || attempt || '|' || branch FROM tasks WHERE id = 1;"

  [ "${status}" -eq 0 ]
  [ "${output}" = "completed|1|agent/001/add-health-endpoint" ]

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT pr_url FROM tasks WHERE id = 1;"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'https://github.com/example/loop-engineering/pull/1' ]
  assert_file_contains "${GH_ARGS_LOG}" "pr create"
  assert_file_contains "${GH_ARGS_LOG}" "--body-file"
  assert_file_contains "${GH_BODY_LOG}" "Add GET /health."
  assert_file_contains "${GH_BODY_LOG}" "Loop task: #1"
  assert_file_contains "${GH_BODY_LOG}" "Test gate: passed (\`test -f agent-change.txt\`)"
  assert_file_contains "${GH_BODY_LOG}" "Verifier Codex: passed"
  assert_file_contains "${GH_BODY_LOG}" 'Commit: `'
  run git -C "${FIXTURE_ROOT}" ls-remote --heads origin \
    "refs/heads/agent/001/add-health-endpoint"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT phase || '|' || status FROM attempts WHERE task_id = 1 ORDER BY id;"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'implement|running\ntest|running\nverify|running' ]
  [ -f "${FIXTURE_ROOT}/.loop/worktrees/task-1/agent-change.txt" ]
}

@test "resume publishes a committed task after pull request creation fails" {
  setup_codex_stub

  add_health_task

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "CODEX_VERDICT_COUNT=${CODEX_VERDICT_COUNT}" \
    GH_FAIL_CREATE_FIRST=1 \
    "${FIXTURE_ROOT}/loop/loop.sh" run

  [ "${status}" -eq 1 ]

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT status || '|' || (result_commit IS NOT NULL) FROM tasks WHERE id = 1;"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'testing|1' ]

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "CODEX_VERDICT_COUNT=${CODEX_VERDICT_COUNT}" \
    GH_FAIL_CREATE_FIRST=1 \
    make task-publish TASK_ID=1

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "PULL REQUEST: https://github.com/example/loop-engineering/pull/1"

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT status || '|' || attempt || '|' || pr_url FROM tasks WHERE id = 1;"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'completed|1|https://github.com/example/loop-engineering/pull/1' ]
}

@test "loop run exits cleanly when there are no queued tasks" {
  run "${FIXTURE_ROOT}/loop/loop.sh" run

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "No queued tasks."
}

@test "task-publish repairs a completed task without a pull request URL" {
  setup_codex_stub

  add_health_task

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "CODEX_VERDICT_COUNT=${CODEX_VERDICT_COUNT}" \
    "${FIXTURE_ROOT}/loop/loop.sh" run

  [ "${status}" -eq 0 ]
  sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "UPDATE tasks SET pr_url = '' WHERE id = 1;"
  rm -f "${GH_PR_FILE}"

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "CODEX_VERDICT_COUNT=${CODEX_VERDICT_COUNT}" \
    make task-publish TASK_ID=1

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "PULL REQUEST: https://github.com/example/loop-engineering/pull/1"
}

@test "resume keeps the worktree and continues a failed task" {
  setup_codex_stub

  mkdir -p "${FIXTURE_ROOT}/.loop/tasks"
  cat >"${FIXTURE_ROOT}/.loop/tasks/task-001-resume.md" <<'TASK'
---
title: Resume task
base_branch: main
max_attempts: 1
test_command: test -f resume-ready
---
Resume the existing implementation.
TASK

  "${FIXTURE_ROOT}/loop/loop.sh" add \
    "${FIXTURE_ROOT}/.loop/tasks/task-001-resume.md" >/dev/null

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "CODEX_VERDICT_COUNT=${CODEX_VERDICT_COUNT}" \
    "${FIXTURE_ROOT}/loop/loop.sh" run

  [ "${status}" -eq 1 ]

  sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "UPDATE tasks SET status = 'testing', last_error = NULL WHERE id = 1;"
  touch "${FIXTURE_ROOT}/.loop/worktrees/task-1/resume-ready"

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "CODEX_VERDICT_COUNT=${CODEX_VERDICT_COUNT}" \
    "${FIXTURE_ROOT}/loop/loop.sh" resume 1

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "TASK COMPLETE"

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT status || '|' || attempt || '|' || branch FROM tasks WHERE id = 1;"

  [ "${status}" -eq 0 ]
  [ "${output}" = "completed|2|agent/001/resume" ]
  [ -f "${FIXTURE_ROOT}/.loop/worktrees/task-1/resume-ready" ]

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT attempt || '|' || phase FROM attempts WHERE task_id = 1 ORDER BY id;"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'1|implement\n1|test\n2|test\n2|verify' ]
}

@test "resume stops at twice the configured attempt limit" {
  setup_codex_stub

  mkdir -p "${FIXTURE_ROOT}/.loop/tasks"
  cat >"${FIXTURE_ROOT}/.loop/tasks/task-001-resume-limit.md" <<'TASK'
---
title: Resume limit task
base_branch: main
max_attempts: 1
test_command: test -f never-created
---
Keep trying until the attempt limit is reached.
TASK

  "${FIXTURE_ROOT}/loop/loop.sh" add \
    "${FIXTURE_ROOT}/.loop/tasks/task-001-resume-limit.md" >/dev/null

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "${FIXTURE_ROOT}/loop/loop.sh" run

  [ "${status}" -eq 1 ]

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "${FIXTURE_ROOT}/loop/loop.sh" resume 1

  [ "${status}" -eq 1 ]

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "${FIXTURE_ROOT}/loop/loop.sh" resume 1

  [ "${status}" -eq 1 ]
  assert_contains "${output}" "Resume attempt limit reached: 2."

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT status || '|' || attempt FROM tasks WHERE id = 1;"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'failed|2' ]
}

@test "resume marks verifier failure as failed" {
  setup_codex_stub

  mkdir -p "${FIXTURE_ROOT}/.loop/tasks"
  cat >"${FIXTURE_ROOT}/.loop/tasks/task-001-resume-verifier.md" <<'TASK'
---
title: Resume verifier task
base_branch: main
max_attempts: 1
test_command: test -f resume-ready
---
Resume the verifier failure.
TASK

  "${FIXTURE_ROOT}/loop/loop.sh" add \
    "${FIXTURE_ROOT}/.loop/tasks/task-001-resume-verifier.md" >/dev/null

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "CODEX_VERDICT_COUNT=${CODEX_VERDICT_COUNT}" \
    "${FIXTURE_ROOT}/loop/loop.sh" run

  [ "${status}" -eq 1 ]

  touch "${FIXTURE_ROOT}/.loop/worktrees/task-1/resume-ready"

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "CODEX_ARGS_LOG=${CODEX_ARGS_LOG}" \
    "CODEX_STDIN_LOG=${CODEX_STDIN_LOG}" \
    "CODEX_VERDICT_COUNT=${CODEX_VERDICT_COUNT}" \
    CODEX_FAIL_FIRST=1 \
    "${FIXTURE_ROOT}/loop/loop.sh" resume 1

  [ "${status}" -eq 1 ]
  assert_contains "${output}" "VERIFIER FAILED"

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT status || '|' || attempt FROM tasks WHERE id = 1;"

  [ "${status}" -eq 0 ]
  [ "${output}" = 'failed|2' ]
}
