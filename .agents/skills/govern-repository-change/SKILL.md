---
name: govern-repository-change
description: Govern version-controlled additions, modifications, and deletions through GitHub Issues, linked branches, commits, pull requests, required checks, and human merge. Use before starting, resuming, or submitting such work. Do not use for read-only analysis, explanation, or diagnosis.
---

# Govern Repository Change

Treat the repository-root `AGENTS.md` as the policy authority. This Skill is the
standard operational entry point; it does not replace or relax that policy.

## Route the task

- For read-only analysis, explanation, review, or diagnosis, do not create an
  Issue or branch. Use `scripts/status.ps1` only when repository workflow state
  is relevant.
- A user request to implement, build, fix, refactor, test, document, or otherwise
  change content intended for version control authorizes creation of the required
  Issue and linked branch. It does not authorize commit, rebase, push, PR
  creation, or merge.
- Before changing files, run `scripts/status.ps1`. Resume an existing valid
  Issue-linked branch instead of creating duplicate work.
- If the requested outcome, scope, non-goals, invariants, or acceptance criteria
  are materially unclear, resolve that ambiguity before creating the Issue.

## Start a governed change

Use `scripts/start.ps1` only from a clean `main` worktree. State the intended
Issue fields in commentary before invoking it.

```powershell
& .\.agents\skills\govern-repository-change\scripts\start.ps1 `
  -Title 'Govern repository changes' `
  -Slug 'govern-repository-changes' `
  -Outcome 'Every version-controlled change uses an Issue-linked review boundary.' `
  -Reason 'The repository needs one auditable development path.' `
  -Scope 'Repository change-governance files.' `
  -NonGoals 'Product behavior changes.' `
  -Invariants 'Windows Bootstrap remains independently buildable.' `
  -AcceptanceCriteria @(
      'A linked branch is created from main.',
      'The Issue contains independently verifiable criteria.'
  )
```

The script performs preflight checks, creates one GitHub Issue, and then creates
and checks out its linked branch. These operations are not atomic. If the Issue
result is uncertain or branch creation fails, do not retry, close, or delete
anything automatically. Report the output and inspect GitHub before recovery.

## Continue and submit

- Keep implementation, relevant tests, and current protocol updates together;
  follow the commit boundaries and message contract in root `AGENTS.md`.
- If scope or acceptance changes materially, obtain direction and update the
  Issue before continuing.
- Stage and commit only after the user explicitly authorizes a commit. Rebase,
  push, and PR creation each remain subject to the authorization boundary in
  root `AGENTS.md`.
- Prefer repository Skill scripts over handcrafted GitHub mutation commands.
  Direct `ghswaw` use is allowed for read-only inspection or a reported recovery
  step when no script covers it.
- A workflow file creates checks but does not make them required. Before calling
  governance enforced or a PR merge-eligible, verify the active remote `main`
  ruleset required by root `AGENTS.md`. Use `scripts/ruleset.ps1 status` to compare
  GitHub with `.github/rulesets/protect-main.json`, `plan` to report the required
  create or update, and `apply` only after explicit authorization to mutate the
  repository control plane. On first installation, do not activate the Ruleset
  until the trusted `pull_request_target` policy workflow exists on the default
  branch; if activation happened out of order, report the one-time bootstrap
  blocker defined by root policy instead of inventing a reusable bypass. Treat an
  uncertain apply result as non-retryable until `status` and GitHub inspection
  establish the actual state. Report missing or drifting enforcement as a blocker.
- Never merge or enable auto-merge. Report when required checks and review state
  make the PR eligible for the repository owner to merge.
- Treat `.github/workflows/**` and the policy-loaded `governance.psm1` as trust
  roots. Their migration requires an owner-authored PR and the repository owner
  to apply `governance-migration` after reviewing the diff; never add, remove, or
  automate that label as Agent.

## Sources of truth

- Root maintenance and Git protocol: `../../../AGENTS.md`
- Issue input contract: `../../../.github/ISSUE_TEMPLATE/change.yml`
- PR input contract: `../../../.github/PULL_REQUEST_TEMPLATE.md`
- Trusted change-policy validation: `../../../.github/workflows/change-policy.yml`
- Candidate product validation: `../../../.github/workflows/validate.yml`
- Desired `main` protection: `../../../.github/rulesets/protect-main.json`
- Offline verification: `tests/workflow.ps1`, `tests/ruleset.ps1`, and
  `tests/policy.ps1`
