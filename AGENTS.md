# Repository instructions

## Pull requests

- Use `.github/PULL_REQUEST_TEMPLATE.md` for every pull request.
- Fill every applicable section with facts from the task, diff, and verification results.
- Include the related Loop task or issue when one exists.
- Record the exact test command and its result. Do not claim manual verification that was not performed.
- Before creating a pull request, review the diff for unrelated changes and confirm that the acceptance criteria are covered.
- When using `gh pr create`, provide the completed template with `--body-file` (or use `--template .github/PULL_REQUEST_TEMPLATE.md` for an interactive creation).
