#!/usr/bin/env bash

set -euo pipefail

# Constants --------------------------------------------------------------------------------
ROOT="$(git rev-parse --show-toplevel)"
STATE_DIR="${ROOT}/.loop"
DB="${STATE_DIR}/state.db"
TASK_DIR="${STATE_DIR}/tasks"

# Pre-Process ------------------------------------------------------------------------------
mkdir -p "${STATE_DIR}/logs"
mkdir -p "${STATE_DIR}/worktrees"
mkdir -p "${TASK_DIR}"
TASK_DIR="$(cd "${TASK_DIR}" && pwd -P)"

# Functions --------------------------------------------------------------------------------
db_init() {
  sqlite3 "${DB}" <"${ROOT}/loop/init.sql"

  # Keep databases created before task definitions moved to files usable.
  if ! sqlite3 "${DB}" "SELECT definition_path FROM tasks LIMIT 0;" >/dev/null 2>&1; then
    sqlite3 "${DB}" "ALTER TABLE tasks ADD COLUMN definition_path TEXT;"
  fi
}

db_exec() {
  sqlite3 "${DB}" "${1}"
}

sql_escape() {
  printf "%s" "${1}" | sed "s/'/''/g"
}

task_definition_path() {
  local input="${1}"
  local absolute

  absolute="$(cd "$(dirname "${input}")" && pwd -P)/$(basename "${input}")"

  if [[ ! -f "${absolute}" ]]; then
    echo "Task definition not found: ${input}" >&2
    return 1
  fi

  case "${absolute}" in
    "${TASK_DIR}"/*)
      printf '.loop/tasks/%s\n' "${absolute#"${TASK_DIR}"/}"
      ;;
    *)
      echo "Task definition must be under ${TASK_DIR}: ${input}" >&2
      return 1
      ;;
  esac
}

task_definition_file() {
  local path="${1}"

  case "${path}" in
    .loop/tasks/*)
      printf '%s/%s\n' "${ROOT}" "${path}"
      ;;
    *)
      echo "Invalid task definition path: ${path}" >&2
      return 1
      ;;
  esac
}

task_definition_field() {
  local file="${1}"
  local field="${2}"

  awk -v field="${field}" '
    NR == 1 && $0 == "---" { frontmatter = 1; next }
    frontmatter && $0 == "---" { exit }
    frontmatter && index($0, field ":") == 1 {
      value = substr($0, length(field) + 2)
      sub(/^[[:space:]]*/, "", value)
      print value
      exit
    }
  ' "${file}"
}

task_definition_body() {
  local file="${1}"

  awk '
    NR == 1 && $0 == "---" { frontmatter = 1; next }
    frontmatter && $0 == "---" { body = 1; next }
    body { print }
  ' "${file}"
}

task_add_file() {
  local input="${1}"
  local definition_path
  local definition_file
  local title
  local content
  local test_command
  local base_branch
  local max_attempts

  definition_path="$(task_definition_path "${input}")"
  definition_file="$(task_definition_file "${definition_path}")"
  title="$(task_definition_field "${definition_file}" title)"
  content="$(task_definition_body "${definition_file}")"
  test_command="$(task_definition_field "${definition_file}" test_command)"
  base_branch="$(task_definition_field "${definition_file}" base_branch)"
  max_attempts="$(task_definition_field "${definition_file}" max_attempts)"

  [[ -n "${title}" ]] || {
    echo "Task definition is missing frontmatter field: title" >&2
    return 1
  }
  [[ -n "${content}" ]] || {
    echo "Task definition has no body: ${definition_file}" >&2
    return 1
  }

  base_branch="${base_branch:-main}"
  max_attempts="${max_attempts:-5}"
  test_command="${test_command:-}"

  if [[ ! "${max_attempts}" =~ ^[1-9][0-9]*$ ]]; then
    echo "max_attempts must be a positive integer: ${max_attempts}" >&2
    return 1
  fi

  definition_path="$(sql_escape "${definition_path}")"
  title="$(sql_escape "${title}")"
  content="$(sql_escape "${content}")"
  test_command="$(sql_escape "${test_command}")"
  base_branch="$(sql_escape "${base_branch}")"

  if sqlite3 "${DB}" "SELECT 1 FROM pragma_table_info('tasks') WHERE name = 'prompt';" | grep -q 1; then
    # Legacy schema compatibility. New task definitions never read these copies.
    sqlite3 "${DB}" <<SQL
INSERT INTO tasks (
  title,
  prompt,
  test_command,
  base_branch,
  max_attempts,
  definition_path
) VALUES (
  '${title}',
  '${content}',
  '${test_command}',
  '${base_branch}',
  '${max_attempts}',
  '${definition_path}'
);
SQL
  else
    sqlite3 "${DB}" <<SQL
INSERT INTO tasks (definition_path)
VALUES ('${definition_path}');
SQL
  fi

  sqlite3 "${DB}" "SELECT last_insert_rowid();"
}

task_create_definition() {
  local title="${1}"
  local content="${2}"
  local test_command="${3}"
  local base_branch="${4:-main}"
  local next_id
  local file

  next_id="$(sqlite3 "${DB}" "SELECT COALESCE(MAX(id), 0) + 1 FROM tasks;")"
  file="${TASK_DIR}/task-${next_id}.md"

  cat >"${file}" <<EOF
---
title: ${title}
base_branch: ${base_branch}
max_attempts: 5
test_command: ${test_command}
---
${content}
EOF

  printf '%s\n' "${file}"
}

task_add() {
  local title="${1}"
  local content="${2}"
  local test_command="${3}"
  local base_branch="${4:-main}"
  local definition_file

  definition_file="$(task_create_definition "${title}" "${content}" "${test_command}" "${base_branch}")"
  task_add_file "${definition_file}"
}

task_next() {
  local result

  result="$(
    sqlite3 -json "${DB}" <<SQL
SELECT *
FROM tasks
WHERE status = 'queued'
ORDER BY id
LIMIT 1;
SQL
  )"

  if [[ -n "${result}" ]]; then
    printf '%s\n' "${result}"
  else
    printf '[]\n'
  fi
}

task_get() {
  local id="${1}"

  sqlite3 -json "${DB}" "
    SELECT *
      FROM tasks
      WHERE id = ${id}
      LIMIT 1;
  "
}

task_update_status() {
  local id="${1}"
  local status="${2}"

  sqlite3 "${DB}" "
    UPDATE tasks
    SET
      status = '${status}',
      updated_at = CURRENT_TIMESTAMP
    WHERE id = $id;
  "
}

task_start() {
  local id="${1}"
  local branch="${2}"
  local worktree="${3}"

  branch="$(sql_escape "${branch}")"
  worktree="$(sql_escape "${worktree}")"

  sqlite3 "${DB}" "
    UPDATE tasks
    SET
      status = 'running',
      branch = '${branch}',
      worktree = '${worktree}',
      started_at = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = $id;
  "
}

task_increment_attempt() {
  local id="${1}"

  sqlite3 "${DB}" "
    UPDATE tasks
    SET
      attempt = attempt + 1,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = $id;
  "
}

task_set_error() {
  local id="${1}"
  local error="${2}"

  error="$(sql_escape "${error}")"

  sqlite3 "${DB}" "
    UPDATE tasks
    SET
      last_error = '$error',
      updated_at = CURRENT_TIMESTAMP
    WHERE id = $id;
  "
}

task_complete() {
  local id="${1}"
  local commit="${2}"

  sqlite3 "${DB}" "
    UPDATE tasks
    SET
      status = 'completed',
      result_commit = '$commit',
      finished_at = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = $id;
  "
}

task_fail() {
  local id="${1}"

  sqlite3 "${DB}" "
    UPDATE tasks
    SET
      status = 'failed',
      finished_at = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = $id;
  "
}

attempt_add() {
  local task_id="${1}"
  local attempt="${2}"
  local phase="${3}"
  local status="${4}"
  local log="${5}"

  log="$(sql_escape "${log}")"

  sqlite3 "${DB}" <<SQL
INSERT INTO attempts (
  task_id,
  attempt,
  phase,
  status,
  log_path
) VALUES (
  '$task_id',
  '$attempt',
  '$phase',
  '$status',
  '$log'
);
SQL
}

export_json() {
  mkdir -p "${STATE_DIR}"

  sqlite3 --json "${DB}" "
    SELECT
      id,
      definition_path,
      branch,
      worktree,
      status,
      attempt,
      last_error,
      result_commit,
      created_at,
      started_at,
      finished_at,
      updated_at
    FROM tasks
    ORDER BY id;
  " | jq '.' >"${STATE_DIR}/state.json"
}
