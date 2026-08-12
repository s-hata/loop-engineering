#!/usr/bin/env bats

load test_helper

@test "loop without a command prints usage" {
  run "${FIXTURE_ROOT}/loop/loop.sh"

  [ "${status}" -eq 1 ]
  assert_contains "${output}" "Usage:"
}

@test "status shows a queued task" {
  "${FIXTURE_ROOT}/loop/loop.sh" add "Health endpoint" "Add GET /health" "npm test" >/dev/null

  run "${FIXTURE_ROOT}/loop/loop.sh" status

  [ "${status}" -eq 0 ]
  assert_contains "${output}" ".loop/tasks/task-1.md"
  assert_contains "${output}" "queued"
}
