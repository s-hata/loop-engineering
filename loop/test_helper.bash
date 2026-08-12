#!/usr/bin/env bash

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"

setup_fixture() {
  FIXTURE_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/loop-bats.XXXXXX")"
  export FIXTURE_ROOT

  cp -R "${PROJECT_ROOT}/loop" "${FIXTURE_ROOT}/loop"

  git -C "${FIXTURE_ROOT}" init -q -b main
  git -C "${FIXTURE_ROOT}" config user.email "loop-bats@example.invalid"
  git -C "${FIXTURE_ROOT}" config user.name "loop-bats"
  git -C "${FIXTURE_ROOT}" add loop
  git -C "${FIXTURE_ROOT}" commit -qm "fixture"

  cd "${FIXTURE_ROOT}" || return 1
}

teardown_fixture() {
  if [[ -n "${FIXTURE_ROOT:-}" && -d "${FIXTURE_ROOT}" ]]; then
    rm -rf -- "${FIXTURE_ROOT}"
  fi
}

setup() {
  setup_fixture
}

teardown() {
  teardown_fixture
}

assert_contains() {
  local actual="${1}"
  local expected="${2}"

  if [[ "${actual}" != *"${expected}"* ]]; then
    echo "expected output to contain: ${expected}" >&2
    echo "actual output: ${actual}" >&2
    return 1
  fi
}

assert_file_contains() {
  local file="${1}"
  local expected="${2}"

  if ! grep -Fq -- "${expected}" "${file}"; then
    echo "expected ${file} to contain: ${expected}" >&2
    return 1
  fi
}
