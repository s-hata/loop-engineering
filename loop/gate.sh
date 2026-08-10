#!/usr/bin/env bash

set -euo pipefail

run_gate() {
  local worktree="${1}"
  local command="${2}"
  local logfile="${3}"

  echo "=== TEST GATE ===" | tee "${logfile}"
  echo "${command}" | tee -a "${logfile}"
  echo | tee -a "${logfile}"

  if [[ -z "${command}" ]]; then
    echo "No automated test command configured." | tee -a "${logfile}"
    echo "exit_code=0" >>"${logfile}"
    return 0
  fi

  set +e

  (
    cd "${worktree}"
    bash -lc "${command}"
  ) 2>&1 | tee -a "${logfile}"

  local exit_code="${PIPESTATUS[0]}"

  set -e

  echo >>"${logfile}"
  echo "exit_code=${exit_code}" >>"${logfile}"

  return "${exit_code}"
}
