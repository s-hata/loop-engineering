#!/usr/bin/env bats

load test_helper

@test "verify runs all npm checks in order" {
  local npm_log="${FIXTURE_ROOT}/npm.log"
  mkdir -p "${FIXTURE_ROOT}/bin"
  cat >"${FIXTURE_ROOT}/bin/npm" <<'NPM'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${NPM_LOG}"
if [[ "${NPM_FAIL_ON:-}" == "$*" ]]; then
	exit "${NPM_FAIL_CODE:-17}"
fi
NPM
  chmod +x "${FIXTURE_ROOT}/bin/npm"

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "NPM_LOG=${npm_log}" \
    "${FIXTURE_ROOT}/loop/verify.sh"

  [ "${status}" -eq 0 ]
  [ "$(cat "${npm_log}")" = $'run typecheck\nrun lint\ntest\nrun build' ]
}

@test "verify stops when a command fails" {
  local npm_log="${FIXTURE_ROOT}/npm.log"
  mkdir -p "${FIXTURE_ROOT}/bin"
  cat >"${FIXTURE_ROOT}/bin/npm" <<'NPM'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${NPM_LOG}"
if [[ "${NPM_FAIL_ON:-}" == "$*" ]]; then
	exit "${NPM_FAIL_CODE:-17}"
fi
NPM
  chmod +x "${FIXTURE_ROOT}/bin/npm"

  run env \
    "PATH=${FIXTURE_ROOT}/bin:${PATH}" \
    "NPM_LOG=${npm_log}" \
    "NPM_FAIL_ON=run lint" \
    "NPM_FAIL_CODE=23" \
    "${FIXTURE_ROOT}/loop/verify.sh"

  [ "${status}" -eq 23 ]
  [ "$(cat "${npm_log}")" = $'run typecheck\nrun lint' ]
}
