#!/usr/bin/env bash

task_title_slug() {
  local title="${1:-}"
  local slug

  slug="$(printf '%s' "${title}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  printf '%s\n' "${slug:-task}"
}

task_branch_name() {
  local task_id="${1}"
  local definition_path="${2:-}"
  local title="${3:-}"
  local filename="${definition_path##*/}"
  local identifier
  local slug

  if [[ "${filename}" =~ ^task-([0-9]+)-([a-z0-9][a-z0-9-]*)\.md$ ]]; then
    identifier="${BASH_REMATCH[1]}"
    slug="${BASH_REMATCH[2]}"
  else
    printf -v identifier '%03d' "${task_id}"
    slug="$(task_title_slug "${title}")"
  fi

  printf 'agent/%s/%s\n' "${identifier}" "${slug}"
}
