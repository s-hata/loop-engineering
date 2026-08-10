.DEFAULT_GOAL := help

SHELL := /bin/bash

BATS ?= bats
SHELLCHECK ?= shellcheck
SHFMT ?= shfmt

LOOP_SCRIPTS := $(wildcard loop/*.sh)
LOOP_HELPERS := $(wildcard loop/*.bash)
LOOP_TESTS := $(wildcard loop/*.bats)

.PHONY: help sh-test sh-lint sh-fmt sh-fmt-check \
	check-deps sh-check-dev-deps task-add task-status task-run task-resume task-reset \
	task-reset-force sh-check

help:
	@printf '%s\n' \
		'Usage: make <target>' \
		'' \
		'General targets:' \
		'  check-deps         Check runtime dependencies' \
		'' \
		'Shell quality targets:' \
		'  sh-test            Run Bats tests' \
		'  sh-lint            Run ShellCheck' \
		'  sh-fmt             Format shell and Bats files' \
		'  sh-fmt-check       Check formatting without changing files' \
		'  sh-check-dev-deps  Check test and quality tools' \
		'  sh-check           Run dependency checks, lint, formatting, and tests' \
		'' \
		'Task targets:' \
		'  task-add           Add a task definition (TASK_FILE=path)' \
		'  task-status        Show task queue status' \
		'  task-run           Run the next queued task' \
		'  task-resume        Resume a task without discarding its worktree' \
		'  task-reset         Reset a task for rerun (TASK_ID=n)' \
		'  task-reset-force   Reset and discard worktree changes (TASK_ID=n)'

check-deps:
	@missing=0; \
	for command_name in git codex sqlite3 jq bash; do \
		if command -v "$$command_name" >/dev/null 2>&1; then \
			echo "[ok]      $$command_name"; \
		else \
			echo "[missing] $$command_name" >&2; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then exit 1; fi

sh-check-dev-deps:
	@missing=0; \
	for command_name in bats shellcheck shfmt; do \
		if command -v "$$command_name" >/dev/null 2>&1; then \
			echo "[ok]      $$command_name"; \
		else \
			echo "[missing] $$command_name" >&2; \
			missing=1; \
		fi; \
	done; \
	if [ "$$missing" -ne 0 ]; then exit 1; fi

sh-test: check-deps sh-check-dev-deps
	$(BATS) $(LOOP_TESTS)

sh-lint: sh-check-dev-deps
	$(SHELLCHECK) $(LOOP_SCRIPTS) $(LOOP_HELPERS) $(LOOP_TESTS)

sh-fmt:
	$(SHFMT) -w -i 2 -ci -ln bash $(LOOP_SCRIPTS) $(LOOP_HELPERS)
	$(SHFMT) -w -i 2 -ci -ln bats $(LOOP_TESTS)

sh-fmt-check: sh-check-dev-deps
	$(SHFMT) -d -i 2 -ci -ln bash $(LOOP_SCRIPTS) $(LOOP_HELPERS)
	$(SHFMT) -d -i 2 -ci -ln bats $(LOOP_TESTS)

task-add: check-deps
	@if [ -z "$(TASK_FILE)" ]; then \
		echo 'Usage: make task-add TASK_FILE=.loop/tasks/task-001-example.md' >&2; \
		exit 2; \
	fi
	@if [ ! -f "$(TASK_FILE)" ]; then \
		echo "Task definition not found: $(TASK_FILE)" >&2; \
		exit 1; \
	fi
	./loop/loop.sh add "$(TASK_FILE)"

task-status: check-deps
	./loop/loop.sh status

task-run: check-deps
	./loop/loop.sh run

task-resume: check-deps
	@if [ -z "$(TASK_ID)" ]; then \
		echo 'Usage: make task-resume TASK_ID=<number>' >&2; \
		exit 2; \
	fi; \
	case "$(TASK_ID)" in \
		*[!0-9]*) echo 'TASK_ID must be a number' >&2; exit 2 ;; \
	esac
	./loop/loop.sh resume "$(TASK_ID)"

task-reset:
	@if [ -z "$(TASK_ID)" ]; then \
		echo 'Usage: make task-reset TASK_ID=<number>' >&2; \
		exit 2; \
	fi; \
	case "$(TASK_ID)" in \
		*[!0-9]*) echo 'TASK_ID must be a number' >&2; exit 2 ;; \
	esac; \
	set -e; \
	. ./loop/branch.sh; \
	task_id="$(TASK_ID)"; \
	branch=''; \
	worktree=".loop/worktrees/task-$$task_id"; \
	if [ ! -f '.loop/state.db' ]; then \
		echo 'State database not found: .loop/state.db' >&2; \
		exit 1; \
	fi; \
	./loop/loop.sh init >/dev/null; \
	task_count="$$(sqlite3 -noheader -batch '.loop/state.db' "SELECT COUNT(*) FROM tasks WHERE id = $$task_id;")"; \
	if [ "$$task_count" != '1' ]; then \
		echo "Task #$$task_id not found" >&2; \
		exit 1; \
	fi; \
	stored_branch="$$(sqlite3 -noheader -batch '.loop/state.db' "SELECT branch FROM tasks WHERE id = $$task_id;")"; \
	definition_path="$$(sqlite3 -noheader -batch '.loop/state.db' "SELECT definition_path FROM tasks WHERE id = $$task_id;")"; \
	title=''; \
	if [ -n "$$definition_path" ] && [ -f "$$definition_path" ]; then \
		title="$$(awk 'NR == 1 && $$0 == "---" { frontmatter = 1; next } frontmatter && $$0 == "---" { exit } frontmatter && index($$0, "title:") == 1 { value = substr($$0, 7); sub(/^[[:space:]]*/, "", value); print value; exit }' "$$definition_path")"; \
	fi; \
	if [ -n "$$stored_branch" ]; then \
		branch="$$stored_branch"; \
	else \
		branch="$$(task_branch_name "$$task_id" "$$definition_path" "$$title")"; \
	fi; \
	if [ -z "$$definition_path" ]; then definition_path='(legacy task definition)'; fi; \
	printf '\n==================================================\nTASK #%s\n%s\n==================================================\n' "$$task_id" "$$definition_path"; \
	git worktree prune; \
	if [ -d "$$worktree" ]; then \
		if [ "$(FORCE)" = '1' ]; then \
			git worktree remove --force "$$worktree"; \
		else \
			git worktree remove "$$worktree"; \
		fi; \
	fi; \
	if git show-ref --verify --quiet "refs/heads/$$branch"; then \
		git branch -D "$$branch"; \
	fi; \
	sqlite3 '.loop/state.db' "UPDATE tasks SET status = 'queued', attempt = 0, attempt_limit = 0, branch = NULL, worktree = NULL, last_error = NULL, result_commit = NULL, started_at = NULL, finished_at = NULL, updated_at = CURRENT_TIMESTAMP WHERE id = $$task_id;"; \
	echo "Reset task #$$task_id"

task-reset-force: FORCE = 1
task-reset-force: task-reset

sh-check: check-deps sh-check-dev-deps sh-fmt-check sh-lint sh-test
