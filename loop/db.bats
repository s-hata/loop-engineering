#!/usr/bin/env bats

load test_helper

@test "init creates the task database schema" {
  run "${FIXTURE_ROOT}/loop/loop.sh" init

  [ "${status}" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.loop/state.db" ]

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('attempts', 'tasks') ORDER BY name;"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'attempts\ntasks' ]
}

@test "init keeps an existing legacy task database usable" {
  mkdir -p "${FIXTURE_ROOT}/.loop"
  sqlite3 "${FIXTURE_ROOT}/.loop/state.db" <<'SQL'
CREATE TABLE tasks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  prompt TEXT NOT NULL,
  base_branch TEXT NOT NULL DEFAULT 'main',
  branch TEXT,
  worktree TEXT,
  status TEXT NOT NULL DEFAULT 'queued',
  attempt INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  test_command TEXT NOT NULL,
  last_error TEXT,
  result_commit TEXT,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  started_at TEXT,
  finished_at TEXT,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id INTEGER NOT NULL,
  attempt INTEGER NOT NULL,
  phase TEXT NOT NULL,
  status TEXT NOT NULL,
  log_path TEXT,
  started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  finished_at TEXT
);
SQL

  run "${FIXTURE_ROOT}/loop/loop.sh" init

  [ "${status}" -eq 0 ]
  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT COUNT(*) FROM pragma_table_info('tasks') WHERE name = 'definition_path';"
  [ "${status}" -eq 0 ]
  [ "${output}" = '1' ]
}

@test "add persists a task and exports JSON" {
  run "${FIXTURE_ROOT}/loop/loop.sh" add \
    "O'Brien health endpoint" \
    'Add GET /health with {"status":"ok"}.' \
    "npm test"

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "Created task #"

  run jq -r '.[0] | [.definition_path, .status] | @tsv' \
    "${FIXTURE_ROOT}/.loop/state.json"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'.loop/tasks/task-1.md\tqueued' ]
  assert_file_contains \
    "${FIXTURE_ROOT}/.loop/tasks/task-1.md" \
    "title: O'Brien health endpoint"
  assert_file_contains \
    "${FIXTURE_ROOT}/.loop/tasks/task-1.md" \
    "Add GET /health with {\"status\":\"ok\"}."
}

@test "add accepts a task definition file under .loop/tasks" {
  mkdir -p "${FIXTURE_ROOT}/.loop/tasks"
  cat >"${FIXTURE_ROOT}/.loop/tasks/health.md" <<'TASK'
---
title: Health endpoint
base_branch: main
max_attempts: 3
test_command: test -f agent-change.txt
---
Implement the health endpoint.

## Acceptance criteria

- Return HTTP 200.
- Return a JSON response.
TASK

  run "${FIXTURE_ROOT}/loop/loop.sh" add \
    "${FIXTURE_ROOT}/.loop/tasks/health.md"

  [ "${status}" -eq 0 ]

  run sqlite3 "${FIXTURE_ROOT}/.loop/state.db" \
    "SELECT definition_path FROM tasks WHERE id = 1;"

  [ "${status}" -eq 0 ]
  [ "${output}" = '.loop/tasks/health.md' ]
  assert_file_contains \
    "${FIXTURE_ROOT}/.loop/tasks/health.md" \
    "max_attempts: 3"
}
