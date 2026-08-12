#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/db.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/branch.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/gate.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/verifier.sh"

ROOT="$(git rev-parse --show-toplevel)"

STATE_DIR="${ROOT}/.loop"
WORKTREE_ROOT="${STATE_DIR}/worktrees"
LOG_ROOT="${STATE_DIR}/logs"
RUN_LOCK="${STATE_DIR}/run.lock"

release_run_lock() {
  if [[ -f "${RUN_LOCK}/pid" ]] && [[ "$(cat "${RUN_LOCK}/pid")" == "$$" ]]; then
    rm -f "${RUN_LOCK}/pid"
    rmdir "${RUN_LOCK}" 2>/dev/null || true
  fi
}

acquire_run_lock() {
  mkdir -p "${STATE_DIR}"

  if mkdir "${RUN_LOCK}" 2>/dev/null; then
    printf '%s\n' "$$" >"${RUN_LOCK}/pid"
    trap release_run_lock EXIT
    return 0
  fi

  local owner
  owner="$(cat "${RUN_LOCK}/pid" 2>/dev/null || true)"
  if [[ "${owner}" =~ ^[0-9]+$ ]] && kill -0 "${owner}" 2>/dev/null; then
    echo "Another Loop execution is already running (pid ${owner})." >&2
    return 1
  fi

  rm -f "${RUN_LOCK}/pid"
  rmdir "${RUN_LOCK}" 2>/dev/null || true

  if ! mkdir "${RUN_LOCK}" 2>/dev/null; then
    echo "Unable to acquire Loop execution lock: ${RUN_LOCK}" >&2
    return 1
  fi

  printf '%s\n' "$$" >"${RUN_LOCK}/pid"
  trap release_run_lock EXIT
}

usage() {
  cat <<EOF
Usage:

  loop/loop.sh init

  loop/loop.sh add \
    ".loop/tasks/task.md"

  loop/loop.sh run

  loop/loop.sh resume \
    "task-id"

  loop/loop.sh publish \
    "task-id"

  loop/loop.sh status
EOF
}

make_worktree() {
  local task_id="${1}"
  local base_branch="${2}"
  local branch="${3}"
  local reuse="${4:-0}"

  local worktree="${WORKTREE_ROOT}/task-${task_id}"

  mkdir -p "${WORKTREE_ROOT}"

  git fetch --all --prune

  if [[ "${reuse}" == "1" ]]; then
    if [[ -d "${worktree}" ]]; then
      local current_branch
      current_branch="$(git -C "${worktree}" branch --show-current)"
      if [[ "${current_branch}" != "${branch}" ]]; then
        echo "Worktree branch mismatch: expected ${branch}, found ${current_branch}" >&2
        return 1
      fi
      printf '%s\n' "${worktree}"
      return 0
    fi

    if git show-ref \
      --verify \
      --quiet \
      "refs/heads/${branch}"; then
      git worktree add \
        "${worktree}" \
        "${branch}"
      printf '%s\n' "${worktree}"
      return 0
    fi

    echo "Cannot resume: branch not found: ${branch}" >&2
    return 1
  fi

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

build_pr_body() {
  local worktree="${1}"
  local task_id="${2}"
  local title="${3}"
  local commit="${4}"
  local task_content="${5}"
  local test_command="${6}"

  local template="${worktree}/.github/PULL_REQUEST_TEMPLATE.md"
  local body
  local summary
  local changes
  local test_status
  local verifier_status
  local manual_verification
  local risk
  local reviewer_notes

  if [[ -f "${template}" ]]; then
    body="$(<"${template}")"
  else
    body=$'## Summary\n\n<!-- PR_SUMMARY -->\n\n## Related task\n\n- Loop task: <!-- PR_TASK_ID -->\n\n## Changes\n\n<!-- PR_CHANGES -->\n\n## Verification\n\n- Test gate: <!-- PR_TEST_STATUS --> (`<!-- PR_TEST_COMMAND -->`)\n- Verifier Codex: <!-- PR_VERIFIER_STATUS -->\n\n## Risk and rollback\n\n<!-- PR_RISK -->\n\n## Reviewer notes\n\n<!-- PR_REVIEWER_NOTES -->\n\n## Checklist\n\n- [ ] Acceptance criteria are satisfied\n- [ ] Tests were added or updated where appropriate\n- [ ] Verification results are recorded above\n- [ ] Unrelated changes are not included\n- [ ] Documentation impact was considered'
  fi

  summary="${task_content:-${title}}"
  changes="Implemented the requested changes for Loop task #${task_id}."
  test_status="passed"
  verifier_status="passed"
  test_command="${test_command:-not configured}"
  manual_verification="not performed"
  risk="No additional risks were identified by the automated verification."
  reviewer_notes="Please review the acceptance criteria and the changed files."

  body="${body//<!-- PR_SUMMARY -->/${summary}}"
  body="${body//<!-- PR_TASK_ID -->/#${task_id}}"
  body="${body//<!-- PR_RELATED_ISSUE -->/not specified}"
  body="${body//<!-- PR_CHANGES -->/${changes}}"
  body="${body//<!-- PR_TEST_STATUS -->/${test_status}}"
  body="${body//<!-- PR_TEST_COMMAND -->/${test_command}}"
  body="${body//<!-- PR_VERIFIER_STATUS -->/${verifier_status}}"
  body="${body//<!-- PR_MANUAL_VERIFICATION -->/${manual_verification}}"
  body="${body//<!-- PR_RISK -->/${risk}}"
  body="${body//<!-- PR_REVIEWER_NOTES -->/${reviewer_notes}}"

  printf '%s\n\nCommit: %s%s%s\n' "${body}" '`' "${commit}" '`'
}

publish_task() {
  local worktree="${1}"
  local branch="${2}"
  local base_branch="${3}"
  local title="${4}"
  local task_id="${5}"
  local commit="${6}"
  local task_content="${7}"
  local test_command="${8}"
  local log_file="${9}"

  local pr_url
  local body_file

  : >"${log_file}"

  (
    cd "${worktree}"

    if ! git push \
      --set-upstream \
      origin \
      "${branch}" \
      >>"${log_file}" \
      2>&1; then
      return 1
    fi

    if pr_url="$(gh pr view \
      "${branch}" \
      --json url \
      --jq '.url' \
      2>>"${log_file}")" && [[ -n "${pr_url}" ]]; then
      printf '%s\n' "${pr_url}"
      return 0
    fi

    body_file="$(mktemp "${TMPDIR:-/tmp}/loop-pr-body.XXXXXX")"
    build_pr_body \
      "${worktree}" \
      "${task_id}" \
      "${title}" \
      "${commit}" \
      "${task_content}" \
      "${test_command}" >"${body_file}"

    if ! pr_url="$(gh pr create \
      --base "${base_branch}" \
      --head "${branch}" \
      --title "${title}" \
      --body-file "${body_file}" \
      2>>"${log_file}")"; then
      rm -f -- "${body_file}"
      return 1
    fi

    rm -f -- "${body_file}"

    if [[ -z "${pr_url}" ]]; then
      echo "gh pr create returned no pull request URL." >>"${log_file}"
      return 1
    fi

    printf '%s\n' "${pr_url}"
  )
}

publish_committed_task() {
  local task_id="${1}"
  local attempt="${2}"
  local worktree="${3}"
  local base_branch="${4}"
  local title="${5}"
  local commit="${6}"
  local task_content="${7}"
  local test_command="${8}"

  local branch
  local publish_log
  local pr_url
  local publish_error

  branch="$(git -C "${worktree}" branch --show-current)"
  publish_log="${LOG_ROOT}/task-${task_id}-attempt-${attempt}-publish.log"

  if ! pr_url="$(publish_task \
    "${worktree}" \
    "${branch}" \
    "${base_branch}" \
    "${title}" \
    "${task_id}" \
    "${commit}" \
    "${task_content}" \
    "${test_command}" \
    "${publish_log}")"; then
    publish_error="$(cat "${publish_log}" 2>/dev/null || true)"
    if [[ -z "${publish_error}" ]]; then
      publish_error="Unknown push or pull request creation error."
    fi

    task_set_error \
      "${task_id}" \
      "Failed to publish branch ${branch}: ${publish_error}"
    export_json
    echo "Failed to publish branch ${branch}: ${publish_error}" >&2
    return 1
  fi

  task_complete \
    "${task_id}" \
    "${commit}" \
    "${pr_url}"

  echo "PUBLISHED: ${branch}"
  echo "PULL REQUEST: ${pr_url}"
}

commit_task() {
  local task_id="${1}"
  local worktree="${2}"
  local title="${3}"
  local base_branch="${4}"
  local attempt="${5}"
  local task_content="${6}"
  local test_command="${7}"

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
    task_set_result_commit "${task_id}" "${commit}"
    export_json

    publish_committed_task \
      "${task_id}" \
      "${attempt}" \
      "${worktree}" \
      "${base_branch}" \
      "${title}" \
      "${commit}" \
      "${task_content}" \
      "${test_command}"
  )
}

run_verifier_phase() {
  local task_id="${1}"
  local attempt="${2}"
  local worktree="${3}"
  local base_branch="${4}"
  local prompt="${5}"
  local test_command="${6}"
  local verifier_log="${LOG_ROOT}/task-${task_id}-attempt-${attempt}-verifier.jsonl"
  local verifier_message="${LOG_ROOT}/task-${task_id}-attempt-${attempt}-verifier.txt"

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
    return 0
  fi

  local verifier_status=$?
  local verifier_failure

  verifier_failure="$(cat "${verifier_message}" 2>/dev/null || true)"
  if [[ -z "${verifier_failure}" ]]; then
    verifier_failure="Verifier execution failed (status ${verifier_status})."
  fi

  task_set_error \
    "${task_id}" \
    "${verifier_failure}"
  task_update_status \
    "${task_id}" \
    "repairing"
  export_json

  echo
  echo "VERIFIER FAILED"
  echo "${verifier_failure}"
  echo
  return 1
}

run_gate_and_verify() {
  local task_id="${1}"
  local attempt="${2}"
  local worktree="${3}"
  local base_branch="${4}"
  local prompt="${5}"
  local test_command="${6}"
  local test_log="${LOG_ROOT}/task-${task_id}-attempt-${attempt}-test.log"

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

  if ! run_gate \
    "${worktree}" \
    "${test_command}" \
    "${test_log}"; then
    local error_tail
    error_tail="$(tail -n 100 "${test_log}")"

    task_set_error \
      "${task_id}" \
      "${error_tail}"
    export_json
    return 1
  fi

  echo
  echo "TEST GATE PASSED"
  echo

  if ! run_verifier_phase \
    "${task_id}" \
    "${attempt}" \
    "${worktree}" \
    "${base_branch}" \
    "${prompt}" \
    "${test_command}"; then
    return 1
  fi

  return 0
}

resume_task_phase() {
  local task_id="${1}"
  local attempt="${2}"
  local phase="${3}"
  local worktree="${4}"
  local base_branch="${5}"
  local title="${6}"
  local prompt="${7}"
  local test_command="${8}"
  local last_error="${9}"
  local resume_max_attempts="${10}"

  if ((attempt >= resume_max_attempts)); then
    task_set_error \
      "${task_id}" \
      "Resume attempt limit reached: ${resume_max_attempts}."
    task_fail "${task_id}"
    echo "Resume attempt limit reached: ${resume_max_attempts}." >&2
    return 1
  fi

  local resume_attempt=$((attempt + 1))

  local existing_commit
  existing_commit="$(task_result_commit "${task_id}")"
  if [[ -n "${existing_commit}" ]]; then
    task_increment_attempt "${task_id}"
    publish_committed_task \
      "${task_id}" \
      "${resume_attempt}" \
      "${worktree}" \
      "${base_branch}" \
      "${title}" \
      "${existing_commit}" \
      "${prompt}" \
      "${test_command}"
    return $?
  fi

  if [[ "${phase}" == "test" && -z "${last_error}" ]]; then
    task_increment_attempt "${task_id}"
    run_gate_and_verify \
      "${task_id}" \
      "${resume_attempt}" \
      "${worktree}" \
      "${base_branch}" \
      "${prompt}" \
      "${test_command}" || return 1
    commit_task \
      "${task_id}" \
      "${worktree}" \
      "${title}" \
      "${base_branch}" \
      "${resume_attempt}" \
      "${prompt}" \
      "${test_command}"
    return $?
  fi

  if [[ "${phase}" == "verify" && -z "${last_error}" ]]; then
    task_increment_attempt "${task_id}"
    run_verifier_phase \
      "${task_id}" \
      "${resume_attempt}" \
      "${worktree}" \
      "${base_branch}" \
      "${prompt}" \
      "${test_command}" || return 1
    commit_task \
      "${task_id}" \
      "${worktree}" \
      "${title}" \
      "${base_branch}" \
      "${resume_attempt}" \
      "${prompt}" \
      "${test_command}"
    return $?
  fi

  local failure="${last_error:-Previous execution was interrupted before this phase completed.}"
  local agent_log="${LOG_ROOT}/task-${task_id}-attempt-${resume_attempt}-agent.jsonl"

  task_increment_attempt "${task_id}"
  task_update_status "${task_id}" "repairing"
  attempt_add \
    "${task_id}" \
    "${resume_attempt}" \
    "repair" \
    "running" \
    "${agent_log}"

  run_codex \
    "${worktree}" \
    "$(build_repair_prompt "${prompt}" "${test_command}" "${failure}")" \
    "${agent_log}"

  if run_gate_and_verify \
    "${task_id}" \
    "${resume_attempt}" \
    "${worktree}" \
    "${base_branch}" \
    "${prompt}" \
    "${test_command}"; then
    commit_task \
      "${task_id}" \
      "${worktree}" \
      "${title}" \
      "${base_branch}" \
      "${resume_attempt}" \
      "${prompt}" \
      "${test_command}"
    return $?
  fi

  return 1
}

process_task() {
  local task_id="${1}"
  local resume_mode="${2:-0}"

  local task_json

  task_json="$(task_get "${task_id}")"

  local title
  local prompt
  local test_command
  local base_branch
  local max_attempts
  local definition_path
  local definition_file
  local current_attempt
  local stored_branch
  local attempt_limit

  title="$(jq -r '.[0].title' <<<"${task_json}")"
  prompt="$(jq -r '.[0].prompt' <<<"${task_json}")"
  test_command="$(jq -r '.[0].test_command' <<<"${task_json}")"
  base_branch="$(jq -r '.[0].base_branch' <<<"${task_json}")"
  max_attempts="$(jq -r '.[0].max_attempts' <<<"${task_json}")"
  definition_path="$(jq -r '.[0].definition_path // empty' <<<"${task_json}")"
  current_attempt="$(jq -r '.[0].attempt // 0' <<<"${task_json}")"
  stored_branch="$(jq -r '.[0].branch // empty' <<<"${task_json}")"
  attempt_limit="$(jq -r '.[0].attempt_limit // 0' <<<"${task_json}")"

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

  if [[ -z "${attempt_limit}" || "${attempt_limit}" -eq 0 ]]; then
    attempt_limit="${max_attempts}"
    task_set_attempt_limit "${task_id}" "${attempt_limit}"
  fi

  echo
  echo "=================================================="
  echo "TASK #${task_id}"
  echo "${title}"
  echo "=================================================="
  echo

  local branch
  branch="${stored_branch:-$(task_branch_name "${task_id}" "${definition_path}" "${title}")}"
  local worktree="${WORKTREE_ROOT}/task-${task_id}"

  make_worktree \
    "${task_id}" \
    "${base_branch}" \
    "${branch}" \
    "${resume_mode}"

  task_start \
    "${task_id}" \
    "${branch}" \
    "${worktree}"

  export_json

  if [[ "${resume_mode}" == "1" ]]; then
    local phase
    local last_error
    local resume_max_attempts

    phase="$(task_last_phase "${task_id}")"
    last_error="$(task_last_error "${task_id}")"
    resume_max_attempts="$(
      task_prepare_resume_limit \
        "${task_id}" \
        "${max_attempts}" \
        "${current_attempt}"
    )"

    if [[ "${current_attempt}" -eq 0 ]]; then
      resume_mode="0"
    else
      if resume_task_phase \
        "${task_id}" \
        "${current_attempt}" \
        "${phase}" \
        "${worktree}" \
        "${base_branch}" \
        "${title}" \
        "${prompt}" \
        "${test_command}" \
        "${last_error}" \
        "${resume_max_attempts}"; then
        export_json
        echo
        echo "TASK COMPLETE"
        echo "branch: ${branch}"
        echo "worktree: ${worktree}"
        echo
        return 0
      fi

      task_fail "${task_id}"
      export_json
      return 1
    fi
  fi

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

      # COMMIT, PUSH, AND CREATE PR OUTSIDE CODEX
      commit_task \
        "${task_id}" \
        "${worktree}" \
        "${title}" \
        "${base_branch}" \
        "${attempt}" \
        "${prompt}" \
        "${test_command}"

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

resume_task() {
  local task_id="${1:-}"
  local task_json
  local status

  if [[ -z "${task_id}" || ! "${task_id}" =~ ^[0-9]+$ ]]; then
    echo "Usage: loop/loop.sh resume <task-id>" >&2
    return 2
  fi

  task_json="$(task_get "${task_id}")"
  if [[ "${task_json}" == "[]" ]]; then
    echo "Task #${task_id} not found" >&2
    return 1
  fi

  status="$(jq -r '.[0].status' <<<"${task_json}")"
  case "${status}" in
    queued)
      process_task "${task_id}"
      ;;
    running | testing | repairing | failed)
      process_task "${task_id}" 1
      ;;
    completed)
      echo "Task #${task_id} is already completed." >&2
      return 1
      ;;
    *)
      echo "Task #${task_id} cannot be resumed from status: ${status}" >&2
      return 1
      ;;
  esac
}

publish_task_command() {
  local task_id="${1:-}"
  local task_json
  local status
  local worktree
  local branch
  local base_branch
  local title
  local commit
  local pr_url
  local definition_path
  local definition_file
  local task_content
  local test_command

  if [[ -z "${task_id}" || ! "${task_id}" =~ ^[0-9]+$ ]]; then
    echo "Usage: loop/loop.sh publish <task-id>" >&2
    return 2
  fi

  task_json="$(task_get "${task_id}")"
  if [[ "${task_json}" == "[]" ]]; then
    echo "Task #${task_id} not found" >&2
    return 1
  fi

  status="$(jq -r '.[0].status' <<<"${task_json}")"
  pr_url="$(jq -r '.[0].pr_url // empty' <<<"${task_json}")"
  if [[ "${status}" == "completed" && -n "${pr_url}" ]]; then
    echo "Task #${task_id} is already completed: ${pr_url}" >&2
    return 1
  fi

  worktree="$(jq -r '.[0].worktree // empty' <<<"${task_json}")"
  branch="$(jq -r '.[0].branch // empty' <<<"${task_json}")"
  base_branch="$(jq -r '.[0].base_branch // "main"' <<<"${task_json}")"
  title="$(jq -r '.[0].title // empty' <<<"${task_json}")"
  commit="$(jq -r '.[0].result_commit // empty' <<<"${task_json}")"
  definition_path="$(jq -r '.[0].definition_path // empty' <<<"${task_json}")"
  task_content="$(jq -r '.[0].prompt // empty' <<<"${task_json}")"
  test_command="$(jq -r '.[0].test_command // empty' <<<"${task_json}")"

  if [[ -n "${definition_path}" ]]; then
    definition_file="$(task_definition_file "${definition_path}")"
    if [[ ! -f "${definition_file}" ]]; then
      echo "Task definition not found: ${definition_file}" >&2
      return 1
    fi

    title="$(task_definition_field "${definition_file}" title)"
    task_content="$(task_definition_body "${definition_file}")"
    test_command="$(task_definition_field "${definition_file}" test_command)"
    base_branch="$(task_definition_field "${definition_file}" base_branch)"
    base_branch="${base_branch:-main}"
  fi

  if [[ -z "${worktree}" || ! -d "${worktree}" ]]; then
    echo "Task #${task_id} worktree not found: ${worktree:-<none>}" >&2
    return 1
  fi
  if [[ -z "${branch}" ]]; then
    branch="$(git -C "${worktree}" branch --show-current)"
  fi
  if [[ -z "${branch}" ]]; then
    echo "Task #${task_id} has no branch" >&2
    return 1
  fi
  if [[ "$(git -C "${worktree}" branch --show-current)" != "${branch}" ]]; then
    echo "Task #${task_id} worktree branch does not match the recorded branch" >&2
    return 1
  fi
  if [[ -z "${commit}" ]]; then
    echo "Task #${task_id} has no committed result to publish" >&2
    return 1
  fi
  if ! git -C "${worktree}" cat-file -e "${commit}^{commit}" 2>/dev/null; then
    echo "Task #${task_id} result commit not found: ${commit}" >&2
    return 1
  fi
  if [[ -n "$(git -C "${worktree}" status --short)" ]]; then
    echo "Task #${task_id} worktree has uncommitted changes; refusing to publish" >&2
    return 1
  fi

  publish_committed_task \
    "${task_id}" \
    "$(jq -r '.[0].attempt // 0' <<<"${task_json}")" \
    "${worktree}" \
    "${base_branch}" \
    "${title}" \
    "${commit}" \
    "${task_content}" \
    "${test_command}"
}

status() {
  local task_count
  task_count="$(sqlite3 -noheader -batch "${DB}" "SELECT COUNT(*) FROM tasks;")"

  if [[ "${task_count}" == "0" ]]; then
    echo "No tasks found."
    return 0
  fi

  sqlite3 \
    -header \
    -column \
    "${DB}" \
    "
    SELECT
      id,
      status,
      attempt,
      attempt_limit,
      definition_path,
      branch,
      COALESCE(
        (
          SELECT phase
          FROM attempts
          WHERE attempts.task_id = tasks.id
          ORDER BY attempts.id DESC
          LIMIT 1
        ),
        ''
      ) AS phase
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
      else
        usage
        exit 1
      fi
      ;;

    run)
      db_init
      acquire_run_lock
      run_next
      ;;

    resume)
      db_init
      acquire_run_lock
      resume_task "${2:-}"
      ;;

    publish)
      db_init
      acquire_run_lock
      publish_task_command "${2:-}"
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
