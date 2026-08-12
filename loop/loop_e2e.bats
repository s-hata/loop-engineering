#!/usr/bin/env bats

load test_helper

setup_codex_stub() {
  mkdir -p "${FIXTURE_ROOT}/bin"
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
}

@test "verifier failure returns to a repair attempt" {
  setup_codex_stub

  "${FIXTURE_ROOT}/loop/loop.sh" add \
    "Add health endpoint" \
    "Add GET /health" \
    "test -f agent-change.txt" >/dev/null

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

  "${FIXTURE_ROOT}/loop/loop.sh" add \
    "Add health endpoint" \
    "Add GET /health" \
    "test -f agent-change.txt" >/dev/null

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
  [ "${output}" = "completed|1|agent/task-1" ]

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT phase || '|' || status FROM attempts WHERE task_id = 1 ORDER BY id;"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'implement|running\ntest|running\nverify|running' ]
  [ -f "${FIXTURE_ROOT}/.loop/worktrees/task-1/agent-change.txt" ]
}

@test "loop run exits cleanly when there are no queued tasks" {
  run "${FIXTURE_ROOT}/loop/loop.sh" run

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "No queued tasks."
}
