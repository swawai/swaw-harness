---
name: govern-repository-change
description: Develop version-controlled repository changes through an Issue, linked branch, pull request, local validation, review, and human merge. Use when starting, resuming, or submitting repository changes. Do not use for read-only analysis.
---

# Govern Repository Change

Use one lightweight path for changes intended to enter the repository.

## Workflow

1. Create or reuse one open GitHub Issue. Record the outcome, scope,
   non-goals, validation scope, and acceptance criteria.
2. From a clean, current `main`, create and check out one Issue-linked branch:

   ```powershell
   ghswaw issue develop N --repo <owner>/<repository> --base main --name <branch> --checkout
   if ($LASTEXITCODE -ne 0) {
       throw 'Issue-linked branch creation or checkout failed.'
   }

   $linkedBranches = @(ghswaw issue develop --list N --repo <owner>/<repository>)
   if ($LASTEXITCODE -ne 0) {
       throw 'Issue-linked branch readback failed.'
   }

   $currentBranch = (& git branch --show-current)
   if ($LASTEXITCODE -ne 0 -or $currentBranch.Trim() -cne '<branch>') {
       throw "Expected checked-out branch '<branch>'."
   }
   ```

   Verify that `$linkedBranches` contains the exact branch before editing files.
   An ordinary Git branch or generic remote-branch creation does not establish
   this GitHub Development relationship and must not substitute for the GitHub
   CLI `issue develop` operation. Keep the Issue, branch, and PR focused on the
   same change.
3. Implement and commit coherent changes. Use `ghswaw` for GitHub Issue and PR
   operations and ordinary `git` commands for local work. Send multiline Issue
   and PR bodies through UTF-8 `--body-file` or JSON input, never inline; read
   them back immediately and verify every required section before continuing.
4. Run the local tests named by the Issue and any additional checks justified
   by the changed code. Record commands and results in the PR.
5. Push the branch and create or update a Draft PR targeting `main`. Reference
   the Issue with `Refs: #N`; this is a non-closing textual reference, not the
   formal Development relationship, and a closing keyword must not be used.
   Read the Issue back through `ghswaw` and verify that its
   `closedByPullRequestsReferences` contains the exact PR and its state remains
   `OPEN`. If the linked branch did not promote to the PR relationship, add the
   exact Issue and PR with the GraphQL `addCloseIssueReferences` mutation, then
   repeat the readback before continuing.
6. The repository owner types `/review`, chooses **Review against a base
   branch**, and selects `origin/main`. Fix actionable findings in the
   development task, then repeat `/review` only if the PR changed.
7. Treat disabled `Auto-close issues with merged linked pull requests` as a
   required external invariant. If it cannot be confirmed, stop and report the
   blocker; do not change the setting without separate owner authorization.
   Only the repository owner marks the PR ready, merges it, and later decides
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
