---
name: govern-repository-change
description: Develop version-controlled repository changes through an Issue, linked branch, pull request, local validation, review, and human merge. Use when starting, resuming, or submitting repository changes. Do not use for read-only analysis.
---

# Govern Repository Change

Use one lightweight path for changes intended to enter the repository.

## Workflow

1. Create or reuse one open GitHub Issue. Record the outcome, scope,
   non-goals, validation scope, and acceptance criteria.
2. Create one Issue-linked branch from current `main`; do not develop on
   `main`. Keep the Issue, branch, and PR focused on the same change.
3. Implement and commit coherent changes. Use `ghswaw` for GitHub Issue and PR
   operations and ordinary `git` commands for local work.
4. Run the local tests named by the Issue and any additional checks justified
   by the changed code. Record commands and results in the PR.
5. Push the branch and create or update a Draft PR targeting `main`. Reference
   the Issue with `Refs: #N`; do not use a closing keyword.
6. The repository owner types `/review`, chooses **Review against a base
   branch**, and selects `origin/main`. Fix actionable findings in the
   development task, then repeat `/review` only if the PR changed.
7. Only the repository owner marks the PR ready, merges it, and later decides
   whether to close the Issue.

## Optional full validation

Only when the repository owner explicitly requests it, run the selected PR
branch with:

```powershell
ghswaw workflow run validate.yml --ref <PR-head-branch>
```

Record the returned run URL and tested revision in the PR. Do not trigger full
validation for ordinary changes; it does not replace local tests or review.

## Authorization boundary

A request to implement a change authorizes the matching Issue, branch, normal
commits, non-force push, and Draft PR creation or update. Ask separately before
history rewriting, force-pushing, changing other refs, marking Ready, merging,
closing the Issue, or changing remote repository settings and Rulesets.
