#!/usr/bin/env bats

# shellcheck disable=SC2016
load test_helper

@test "build_review_diff includes tracked and untracked changes but excludes loop state" {
  printf '%s\n' original >tracked.txt
  git add tracked.txt
  git commit -qm "tracked fixture"
  printf '%s\n' changed >tracked.txt
  printf '%s\n' new >untracked.txt
  mkdir -p .loop
  printf '%s\n' state >.loop/state.db

  run bash -c \
    'source "$1/verifier.sh"; build_review_diff main' \
    _ "${FIXTURE_ROOT}/loop"

  [ "${status}" -eq 0 ]
  assert_contains "${output}" "tracked.txt"
  assert_contains "${output}" "untracked.txt"
  [[ "${output}" != *"state.db"* ]]
}

@test "run_verifier returns the structured PASS verdict" {
  mkdir -p "${FIXTURE_ROOT}/bin"
  cat >"${FIXTURE_ROOT}/bin/codex" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail
message_file=''
previous=''
for argument in "$@"; do
  if [[ "${previous}" == '--output-last-message' ]]; then
    message_file="${argument}"
  fi
  previous="${argument}"
done
cat >/dev/null
printf '%s\n' 'VERDICT: PASS' 'FINDINGS:' '- none' >"${message_file}"
printf '%s\n' '{"type":"turn.completed"}'
CODEX
  chmod +x "${FIXTURE_ROOT}/bin/codex"

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    bash -c \
    'source "$1/verifier.sh"; run_verifier "$2" main "task" "test" "$3" "$4"' \
    _ "${FIXTURE_ROOT}/loop" "${FIXTURE_ROOT}" \
    "${FIXTURE_ROOT}/review.jsonl" "${FIXTURE_ROOT}/review.txt"

  [ "${status}" -eq 0 ]
  assert_file_contains "${FIXTURE_ROOT}/review.txt" "VERDICT: PASS"
  assert_file_contains "${FIXTURE_ROOT}/review.jsonl" "turn.completed"
}

@test "run_verifier fails closed for an invalid verdict" {
  mkdir -p "${FIXTURE_ROOT}/bin"
  cat >"${FIXTURE_ROOT}/bin/codex" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail
message_file=''
previous=''
for argument in "$@"; do
  if [[ "${previous}" == '--output-last-message' ]]; then
    message_file="${argument}"
  fi
  previous="${argument}"
done
cat >/dev/null
printf '%s\n' 'not a verdict' >"${message_file}"
CODEX
  chmod +x "${FIXTURE_ROOT}/bin/codex"

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    bash -c \
    'source "$1/verifier.sh"; run_verifier "$2" main "task" "test" "$3" "$4"' \
    _ "${FIXTURE_ROOT}/loop" "${FIXTURE_ROOT}" \
    "${FIXTURE_ROOT}/review.jsonl" "${FIXTURE_ROOT}/review.txt"

  [ "${status}" -eq 2 ]
}
