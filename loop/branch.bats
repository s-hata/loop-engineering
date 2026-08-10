#!/usr/bin/env bats

load test_helper

@test "branch name uses the task definition identifier and slug" {
  # shellcheck disable=SC1091
  source "${FIXTURE_ROOT}/loop/branch.sh"

  run task_branch_name \
    1 \
    ".loop/tasks/task-001-frontend-app-setup.md" \
    "frontend app setup"

  [ "${status}" -eq 0 ]
  [ "${output}" = "agent/001/frontend-app-setup" ]
}

@test "branch name falls back to a slugified task title" {
  # shellcheck disable=SC1091
  source "${FIXTURE_ROOT}/loop/branch.sh"

  run task_branch_name 1 ".loop/tasks/task-1.md" "Add health endpoint"

  [ "${status}" -eq 0 ]
  [ "${output}" = "agent/001/add-health-endpoint" ]
}
