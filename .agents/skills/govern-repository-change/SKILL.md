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
  change version-controlled content authorizes establishing the required Issue
  and linked branch. Once the Issue is ready, the same authorization covers
  ordinary commits, non-force fast-forward pushes to that exact branch, and
  creating a Draft PR or updating the same PR. It does not authorize amend,
  rebase, history rewriting, force-push, other branches or tags, marking a PR
  ready, repository control-plane mutations, or merge.
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
- After proportionate verification, inspect the worktree and staged diff, then
  create coherent commits without requesting another authorization prompt.
- Immediately before a push, rerun `scripts/status.ps1`. Proceed only when the
  governed context is valid, the worktree is clean, the branch tracks its exact
  `origin` counterpart, it is not behind or diverged, and GitHub's branch OID
  still matches the local remote-tracking OID. Push only `HEAD` to that same
  branch without force, then rerun status to verify the remote result.
- A verified branch may be published and represented by a Draft PR without a
  separate authorization prompt. Leave ready-for-review state, acceptance,
  trust-root migration labels, and merge to the repository owner.
- Prefer repository Skill scripts over handcrafted GitHub mutation commands.
  Direct `ghswaw` use is allowed for read-only inspection, a reported recovery
  step, or the Draft PR creation or same-PR update authorized above when no
  script covers it. Before a PR mutation, verify the repository, `main` base,
  exact Issue-linked head branch, and absence of a conflicting open PR; never
  use this allowance to mark a PR ready or merge it.
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
  to remove and reapply `governance-migration` after reviewing the current HEAD.
  Make that the final PR mutation: every later commit or PR-body edit invalidates
  the authorization and requires another owner review and label cycle. Never add,
  remove, or automate that label as Agent.

## Sources of truth

- Root maintenance and Git protocol: `../../../AGENTS.md`
- Issue input contract: `../../../.github/ISSUE_TEMPLATE/change.yml`
- PR input contract: `../../../.github/PULL_REQUEST_TEMPLATE.md`
- Trusted change-policy validation: `../../../.github/workflows/change-policy.yml`
- Candidate product validation: `../../../.github/workflows/validate.yml`
- Desired `main` protection: `../../../.github/rulesets/protect-main.json`
- Offline verification: `tests/workflow.ps1`, `tests/ruleset.ps1`, and
  `tests/policy.ps1`
