#!/usr/bin/env bats

load test_helper

@test "gate returns success and records the command" {
  local logfile="${FIXTURE_ROOT}/gate.log"
  mkdir -p "${FIXTURE_ROOT}/worktree"

  run bash -c \
    'source "$1/gate.sh"; run_gate "$2" "printf success" "$3"' \
    _ "${FIXTURE_ROOT}/loop" "${FIXTURE_ROOT}/worktree" "${logfile}"

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "success"
  assert_file_contains "${logfile}" "exit_code=0"
}

@test "gate propagates a failed command status" {
  local logfile="${FIXTURE_ROOT}/gate.log"
  mkdir -p "${FIXTURE_ROOT}/worktree"

  run bash -c \
    'source "$1/gate.sh"; run_gate "$2" "exit 7" "$3"' \
    _ "${FIXTURE_ROOT}/loop" "${FIXTURE_ROOT}/worktree" "${logfile}"

  [ "${status}" -eq 7 ]
  assert_file_contains "${logfile}" "exit_code=7"
}
