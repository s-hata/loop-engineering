---
name: loop-task-creator
description: Create or update Loop Engineering task definition files under .loop/tasks through a short requirements interview. Use when a user asks to turn a request, issue, or acceptance criteria into a Codex implementation task; inspect the repository, ask focused questions for material gaps, and write the task only when the scope is reviewable or the user explicitly requests a draft. Do not use for implementing the task itself or for changing product source code.
---

# Loop Task Creator

Create one reviewable task definition for the Loop Engineering runner. Treat the task file as the source of truth for the title, bounded implementation request, acceptance criteria, constraints, and optional deterministic test command.

## Workflow

### 1. Inspect before interviewing

Perform read-only inspection before asking questions or writing files:

- Confirm `.loop/tasks/` exists; create it only when a task will actually be written.
- Read `.loop/tasks/task-template.md` when present.
- List existing task filenames to avoid duplicate slugs and to calculate the next local identifier.
- Read project configuration only when it exists. Never assume `src/`, `tests/`, npm, or another product layout.
- Check the current task file and nearby project documentation when the user asks to update an existing task.
- When the request concerns architecture or a documented decision, inspect the relevant files under `docs/architecture/` and `docs/adr/` when those directories exist.

Summarize facts found in the repository separately from information supplied by the user. Do not treat a directory name, an empty placeholder, or a conventional project layout as a product requirement.

### 2. Interview to close material gaps

Do not create a task file during the interview. First establish enough information for another agent to implement and verify the request.

Track each relevant item as one of:

- **Confirmed:** explicitly stated by the user or directly evidenced by the repository.
- **Proposed:** an option or recommendation offered for the user's decision.
- **Open:** not known yet and material to the implementation or review.

Ask focused follow-up questions using the following priority:

1. Desired outcome and target area.
2. Scope boundaries and explicit non-goals.
3. Observable acceptance criteria, including important edge cases.
4. Compatibility requirements and constraints such as supported runtime, platform, API, or data format.
5. Deterministic verification command, or an explicit decision to leave `test_command` empty.

Ask no more than three concise questions in one turn. Prefer one question when a single decision blocks progress. Reuse repository evidence to make questions concrete, but label recommendations as proposals. If the user asks Codex to choose, present a small set of appropriate options and obtain approval for the selected option; do not silently convert a guess into a requirement.

After each answer, update the confirmed/proposed/open summary and ask only the next unanswered material questions. Do not repeat questions the user has already answered.

### 3. Apply the readiness gate

The task is ready to write when all of the following are known:

- A bounded outcome and target scope.
- Observable acceptance criteria that can be reviewed independently of the implementation approach.
- Constraints and non-goals needed to prevent scope drift.
- A verification approach, including whether `test_command` is intentionally empty.

When a material item remains open, continue the interview or ask the user whether to create a draft. Before writing a non-draft task, present a concise requirements summary and obtain confirmation unless the user has already explicitly approved the complete specification in the current conversation.

If the user explicitly requests a draft or declines to resolve an open item, create a draft only after clearly labeling it in the title and body. Put confirmed requirements in acceptance criteria; put unresolved decisions in a separate draft/open-questions note. Never present an assumption as a confirmed acceptance criterion.

### 4. Choose the filename

Use this format:

```text
task-<identifier>-<kebab-case-slug>.md
```

- Prefer a GitHub Issue or ticket number as `<identifier>`: `task-123-sqlite-migration.md`.
- If no external identifier exists, scan existing files and use the next three-digit sequence: `task-001-sqlite-migration.md`.
- Exclude `task-template.md` from sequence calculation.
- Use lowercase ASCII letters, digits, and single hyphens only.
- Derive the slug from the task's primary outcome; keep it concise and at most 48 characters.
- Do not use spaces, Japanese characters, punctuation, secrets, usernames, or dates as a substitute for a missing identifier.
- Never overwrite an existing file. If the intended name exists, increment the local sequence or ask the user to resolve an identifier collision.

For an update, resolve the exact existing task path first. Preserve unrelated content and ask before changing the task's scope or replacing an existing definition. Do not create a second task for the same outcome unless the user requests a new task.

### 5. Write and verify

Write only the requested task definition under `.loop/tasks/`. Re-read it after writing and check:

- YAML frontmatter has `title`, `base_branch`, `max_attempts`, and `test_command`.
- The filename follows the identifier and slug rules.
- The body has `Task`, `Acceptance criteria`, `Constraints`, and `Verification notes` sections.
- Acceptance criteria contain observable outcomes and do not include unapproved assumptions.
- `test_command` is deterministic and executable in the target product repository, or is intentionally empty.

## File format

Use this frontmatter:

```markdown
---
title: Short task title
base_branch: main
max_attempts: 5
test_command:
---
```

The body must contain these sections:

```markdown
## Task

Describe the bounded implementation request.

## Acceptance criteria

- State observable, verifiable outcomes.
- Include criteria that cannot be reduced to a shell command.

## Constraints

- State compatibility, scope, or safety constraints.

## Verification notes

Describe useful checks or context. Keep this separate from acceptance criteria.
```

`test_command` is optional. Add only deterministic checks that can actually be executed in the target product repository. Do not force every acceptance criterion into a command; leave the field empty when the remaining criteria require review, observation, or domain judgment.

## Safety and scope

- Create or edit only the requested task file under `.loop/tasks/`.
- Do not modify `state.db`, task status, worktrees, product source, or product tests.
- Do not put credentials, tokens, private data, or unreviewed secrets in a task file.
- Keep acceptance criteria separate from implementation suggestions.
- If the request is broad, keep one bounded task unless the user asks for decomposition.
- Do not claim that a task has been implemented or verified merely because its definition file was created.

## Documentation organization

- Store architecture definitions and the architecture source of truth under `docs/architecture/`.
- Store decision rationale, considered alternatives, and consequences under `docs/adr/`.
- Link task definitions to the relevant architecture document and ADR instead of duplicating their content in `.loop/tasks/`.
- When the user explicitly requests an architecture definition, write it under `docs/architecture/`; when the user explicitly requests the decision history, write it under `docs/adr/`.
- Do not create or update architecture or ADR documents merely because a task references them; make those changes only when the user requests the documentation change.

## Completion report

Report the created or updated path, selected identifier/slug, whether it is a draft, and any fields intentionally left empty. Mention that the task definition—not the implementation—was created or updated.
