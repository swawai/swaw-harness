---
name: govern-repository-change
description: Develop version-controlled repository changes through an Issue, linked branch, pull request, local validation, review, and human merge. Use when starting, resuming, or submitting repository changes. Do not use for read-only analysis.
---

# Govern Repository Change

Use one lightweight path for changes intended to enter the repository.

## Workflow

1. Before any GitHub operation, verify that the identity entry is available
   from `PATH` and healthy:

   ```powershell
   $ghswawCommand = Get-Command ghswaw -CommandType Application -ErrorAction SilentlyContinue
   if ($null -eq $ghswawCommand) {
       throw 'Expected ghswaw on PATH.'
   }

   ghswaw .doctor
   if ($LASTEXITCODE -ne 0) {
       throw 'ghswaw identity or GitHub CLI runtime check failed.'
   }
   ```

   Invoke the command by its `ghswaw` name. Do not hard-code the resolved host
   path or bypass the identity entry by calling its underlying `gh` executable.
   If the check fails, stop instead of installing or repairing the dependency.
2. Create or reuse one open GitHub Issue. Record the outcome, scope,
   non-goals, validation scope, and acceptance criteria.
3. Before creating a linked branch, require a clean local `main`, fetch the
   remote base, fast-forward only, and verify the two refs exactly match:

   ```powershell
   $currentBranch = (& git branch --show-current)
   if ($LASTEXITCODE -ne 0 -or $currentBranch.Trim() -cne 'main') {
       throw "Expected current branch 'main'."
   }

   $worktreeStatus = @(& git status --porcelain)
   if ($LASTEXITCODE -ne 0 -or $worktreeStatus.Count -ne 0) {
       throw 'Expected a clean worktree on main.'
   }

   git fetch origin main
   if ($LASTEXITCODE -ne 0) {
       throw 'Fetching origin/main failed.'
   }

   git merge --ff-only origin/main
   if ($LASTEXITCODE -ne 0) {
       throw 'Local main cannot be fast-forwarded to origin/main.'
   }

   $localMain = (& git rev-parse main)
   if ($LASTEXITCODE -ne 0) {
       throw 'Reading local main failed.'
   }
   $remoteMain = (& git rev-parse origin/main)
   if ($LASTEXITCODE -ne 0 -or $localMain.Trim() -cne $remoteMain.Trim()) {
       throw 'Local main does not exactly match origin/main.'
   }
   ```

   Local-only commits or divergence are blockers. Do not merge, rebase, reset,
   or otherwise repair them automatically. Then create and check out the
   Issue-linked branch from the verified remote `main`:

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
4. Implement and commit coherent changes. Use `ghswaw` for GitHub Issue and PR
   operations and ordinary `git` commands for local work. Send multiline Issue
   and PR bodies through UTF-8 `--body-file` or JSON input, never inline; read
   them back immediately and verify every required section before continuing.
5. Run the local tests named by the Issue and any additional checks justified
   by the changed code. Record commands and results in the PR.
6. Push the branch and create or update a Draft PR targeting `main`. Reference
   the Issue with `Refs: #N`; this is a non-closing textual reference, not the
   formal Development relationship, and a closing keyword must not be used.
   Read the Issue back through `ghswaw` and verify that its
   `closedByPullRequestsReferences` contains the exact PR and its state remains
   `OPEN`. If the linked branch did not promote to the PR relationship, add the
   exact Issue and PR with the GraphQL `addCloseIssueReferences` mutation, then
   repeat the readback before continuing.
7. The repository owner types `/review`, chooses **Review against a base
   branch**, and selects `origin/main`. Fix actionable findings in the
   development task, then repeat `/review` only if the PR changed.
8. Treat the repository-owner attestation in the root `AGENTS.md` Git change
   protocol as confirmation that `Auto-close issues with merged linked pull
   requests` is disabled. Do not ask the owner to repeat that confirmation
   unless one of the contradictory conditions recorded there occurs. Do not
   change the setting without separate owner authorization. Only the repository
   owner marks the PR ready, merges it, and later decides whether to close the
   Issue.

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
