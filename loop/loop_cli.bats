#!/usr/bin/env bats

load test_helper

@test "loop without a command prints usage" {
  run "${FIXTURE_ROOT}/loop/loop.sh"

  [ "${status}" -eq 1 ]
  assert_contains "${output}" "Usage:"
}

@test "status shows a queued task" {
  mkdir -p "${FIXTURE_ROOT}/.loop/tasks"
  cat >"${FIXTURE_ROOT}/.loop/tasks/task-001-health.md" <<'TASK'
---
title: Health endpoint
base_branch: main
max_attempts: 5
test_command: npm test
---
Add GET /health.
TASK

  "${FIXTURE_ROOT}/loop/loop.sh" add \
    "${FIXTURE_ROOT}/.loop/tasks/task-001-health.md" >/dev/null

  run "${FIXTURE_ROOT}/loop/loop.sh" status

  [ "${status}" -eq 0 ]
  assert_contains "${output}" ".loop/tasks/task-001-health.md"
  assert_contains "${output}" "queued"
}

@test "status shows a message when no tasks exist" {
  run "${FIXTURE_ROOT}/loop/loop.sh" status

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "No tasks found."
}
