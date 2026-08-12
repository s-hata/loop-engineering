#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/db.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/gate.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/verifier.sh"

ROOT="$(git rev-parse --show-toplevel)"

STATE_DIR="${ROOT}/.loop"
WORKTREE_ROOT="${STATE_DIR}/worktrees"
LOG_ROOT="${STATE_DIR}/logs"

usage() {
  cat <<EOF
Usage:

  loop/loop.sh init

  loop/loop.sh add \
    ".loop/tasks/task.md"

  loop/loop.sh add \
    "task title" \
    "task content" \
    "npm test"

  loop/loop.sh run

  loop/loop.sh status
EOF
}

make_worktree() {
  local task_id="${1}"
  local base_branch="${2}"

  local branch="agent/task-${task_id}"
  local worktree="${WORKTREE_ROOT}/task-${task_id}"

  mkdir -p "${WORKTREE_ROOT}"

  git fetch --all --prune

  if git show-ref \
    --verify \
    --quiet \
    "refs/heads/${branch}"; then
    echo "Branch already exists: ${branch}" >&2
    return 1
  fi

  if [[ -e "${worktree}" ]]; then
    echo "Wroktree already exists: ${worktree}" >&2
  fi

  git worktree add \
    -b "${branch}" \
    "${worktree}" \
    "${base_branch}"

  echo "${worktree}"
}

run_codex() {
  local worktree="${1}"
  local prompt="${2}"
  local logfile="${3}"

  (
    cd "${worktree}"

    codex exec \
      --sandbox workspace-write \
      --json \
      "${prompt}"
  ) 2>&1 | tee "${logfile}"
}

build_initial_prompt() {
  local task_content="${1}"
  local test_command="${2}"

  cat <<EOF
You are implementing one bounded engineering task.

TASK DEFINITION:
$task_content

AUTOMATED TEST COMMAND:
${test_command:-<none>}

Requirements:

1. Inspect the repository before making changes.
2. Implement only the requested task.
3. Keep the change minimal and focused.
4. Do not modify unrelated code.
5. Add or update tests when appropriate.
6. You may run tests while working.
7. Do not create git commits.
8. Do not create branches.
9. Do not modify files outside this worktree.
10. Leave the worktree containing your best implementation.

The external orchestrator will make the final pass/fail decision
by executing the test command independently.
EOF
}

build_repair_prompt() {
  local task_content="${1}"
  local test_command="${2}"
  local failure="${3}"

  cat <<EOF
You are repairing a failed implementation.

TASK DEFINITION:
$task_content

AUTOMATED TEST COMMAND:
${test_command:-<none>}

The external test gate failed.

FAILURE OUTPUT:
------------------------------
$failure
------------------------------

Instructions:

1. Inspect the existing implementation.
2. Determine the root cause of the failure.
3. Make the smallest correct fix.
4. Do not remove or weaken valid tests merely to make the gate pass.
5. Do not modify unrelated code.
6. Do not create git commits.
7. Leave the worktree with the repaired implementation.

The external orchestrator will return the test command.
EOF
}

process_task() {
  local task_id="${1}"

  local task_json

  task_json="$(task_get "${task_id}")"

  local title
  local prompt
  local test_command
  local base_branch
  local max_attempts
  local definition_path
  local definition_file

  title="$(jq -r '.[0].title' <<<"${task_json}")"
  prompt="$(jq -r '.[0].prompt' <<<"${task_json}")"
  test_command="$(jq -r '.[0].test_command' <<<"${task_json}")"
  base_branch="$(jq -r '.[0].base_branch' <<<"${task_json}")"
  max_attempts="$(jq -r '.[0].max_attempts' <<<"${task_json}")"
  definition_path="$(jq -r '.[0].definition_path // empty' <<<"${task_json}")"

  if [[ -n "${definition_path}" ]]; then
    definition_file="$(task_definition_file "${definition_path}")"
    if [[ ! -f "${definition_file}" ]]; then
      task_set_error \
        "${task_id}" \
        "Task definition not found: ${definition_file}"
      task_fail "${task_id}"
      export_json
      return 1
    fi

    title="$(task_definition_field "${definition_file}" title)"
    prompt="$(task_definition_body "${definition_file}")"
    test_command="$(task_definition_field "${definition_file}" test_command)"
    base_branch="$(task_definition_field "${definition_file}" base_branch)"
    max_attempts="$(task_definition_field "${definition_file}" max_attempts)"
    base_branch="${base_branch:-main}"
    max_attempts="${max_attempts:-5}"
  fi

  echo
  echo "=================================================="
  echo "TASK #${task_id}"
  echo "${title}"
  echo "=================================================="
  echo

  local branch="agent/task-${task_id}"
  local worktree="${WORKTREE_ROOT}/task-${task_id}"

  make_worktree \
    "${task_id}" \
    "${base_branch}"

  task_start \
    "${task_id}" \
    "${branch}" \
    "${worktree}"

  export_json

  local attempt=0
  local previous_failure=""

  while ((attempt < max_attempts)); do
    attempt=$((attempt + 1))

    task_increment_attempt "${task_id}"

    echo
    echo "=================================================="
    echo "Attempt ${attempt} / ${max_attempts}"
    echo "=================================================="
    echo

    local agent_log
    local test_log
    local verifier_log
    local verifier_message
    local agent_prompt
    local phase

    agent_log="${LOG_ROOT}/task-${task_id}-attempt-${attempt}-agent.jsonl"
    test_log="${LOG_ROOT}/task-${task_id}-attempt-${attempt}-test.log"
    verifier_log="${LOG_ROOT}/task-${task_id}-attempt-${attempt}-verifier.jsonl"
    verifier_message="${LOG_ROOT}/task-${task_id}-attempt-${attempt}-verifier.txt"

    if ((attempt == 1)); then
      phase="implement"

      agent_prompt="$(
        build_initial_prompt \
          "${prompt}" \
          "${test_command}"
      )"
    else
      phase="repair"

      failure="$(
        build_repair_prompt \
          "${prompt}" \
          "${test_command}" \
          "${previous_failure}"
      )"

      task_update_status \
        "${task_id}" \
        "repairing"
    fi

    attempt_add \
      "${task_id}" \
      "${attempt}" \
      "${phase}" \
      "running" \
      "${agent_log}"

    # CODEX
    run_codex \
      "${worktree}" \
      "${agent_prompt}" \
      "${agent_log}"

    # TEST
    task_update_status \
      "${task_id}" \
      "testing"

    export_json

    attempt_add \
      "${task_id}" \
      "${attempt}" \
      "test" \
      "running" \
      "${test_log}"

    if run_gate \
      "${worktree}" \
      "${test_command}" \
      "${test_log}"; then
      echo
      echo "TEST GATE PASSED"
      echo

      # VERIFIER
      task_update_status \
        "${task_id}" \
        "testing"

      export_json

      attempt_add \
        "${task_id}" \
        "${attempt}" \
        "verify" \
        "running" \
        "${verifier_log}"

      if run_verifier \
        "${worktree}" \
        "${base_branch}" \
        "${prompt}" \
        "${test_command}" \
        "${verifier_log}" \
        "${verifier_message}"; then
        echo
        echo "VERIFIER PASSED"
        echo
      else
        local verifier_status=$?
        local verifier_failure

        verifier_failure="$(cat "${verifier_message}" 2>/dev/null || true)"
        if [[ -z "${verifier_failure}" ]]; then
          verifier_failure="Verifier execution failed (status ${verifier_status})."
        fi

        task_set_error \
          "${task_id}" \
          "${verifier_failure}"
        previous_failure="${verifier_failure}"
        task_update_status \
          "${task_id}" \
          "repairing"
        export_json

        echo
        echo "VERIFIER FAILED"
        echo "${verifier_failure}"
        echo
        continue
      fi

      # COMMIT OUTSIDE CODEX
      (
        cd "${worktree}"

        git add -A

        if git diff \
          --cached \
          --quiet; then
          echo "No changes produced."
          task_set_error \
            "${task_id}" \
            "Test passed but no repository changes were produced."

          task_fail "${task_id}"
          export_json

          return 1
        fi

        git commit \
          -m "agent: task ${task_id} - ${title}"

        local commit
        commit="$(git rev-parse HEAD)"

        task_complete \
          "${task_id}" \
          "${commit}"
      )

      export_json

      echo
      echo "TASK COMPLETE"
      echo "branch: ${branch}"
      echo "worktree: ${worktree}"
      echo

      return 0
    fi

    # FAILURE
    local error_tail

    error_tail="$(
      tail -n 100 "${test_log}"
    )"

    task_set_error \
      "${task_id}" \
      "${error_tail}"

    previous_failure="${error_tail}"

    export_json
  done

  # CIRCUIT BREAKER
  task_fail "${task_id}"
  export_json

  echo
  echo "TASK FAILED"
  echo "Maximum attempt reached: ${max_attempts}"
  echo

  return 1
}

run_next() {
  local next_json

  next_json="$(task_next)"

  if [[ "${next_json}" == "[]" ]]; then
    echo "No queued tasks."
    return 0
  fi

  local task_id
  task_id="$(jq -r '.[0].id' <<<"${next_json}")"
  process_task "${task_id}"
}

status() {
  sqlite3 \
    -header \
    -column \
    "${DB}" \
    "
    SELECT
      id,
      status,
      attempt,
      definition_path,
      branch
    FROM tasks
    ORDER BY id;
    "
}

main() {
  local command="${1:-}"

  case "${command}" in
    init)
      db_init
      export_json

      echo "Initialized:"
      echo "${DB}"
      ;;

    add)
      if (($# == 2)); then
        db_init
        local id
        id="$(task_add_file "${2}")"
        export_json
        echo "Created task #${id}"
      elif (($# >= 4)); then
        db_init
        local definition_file
        local id
        definition_file="$(
          task_create_definition \
            "${2}" \
            "${3}" \
            "${4}" \
            "${5:-main}"
        )"
        id="$(task_add_file "${definition_file}")"
        export_json
        echo "Created task #${id}"
      else
        usage
        exit 1
      fi
      ;;

    run)
      db_init
      run_next
      ;;

    status)
      db_init
      status
      ;;

    *)
      usage
      exit 1
      ;;

  esac
}

main "$@"
