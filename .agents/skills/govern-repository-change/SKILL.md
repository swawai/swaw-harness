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
6. The repository owner starts Codex `/review` when review is wanted. Review the
   current PR and its validation evidence. Fix actionable findings in the
   development task, then request review again.
7. Only the repository owner marks the PR ready, merges it, and later decides
   whether to close the Issue.

GitHub full validation is optional and runs only when the repository owner
explicitly requests it. It does not replace local tests or review.

## Authorization boundary

A request to implement a change authorizes the matching Issue, branch, normal
commits, non-force push, and Draft PR creation or update. Ask separately before
history rewriting, force-pushing, changing other refs, marking Ready, merging,
closing the Issue, or changing remote repository settings and Rulesets.
