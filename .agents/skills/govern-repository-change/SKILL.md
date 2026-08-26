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
For any later Issue-body edit, send the complete UTF-8 body through a payload or
`--body-file`, read the Issue back, and revalidate its sections. Never pass a
multiline body as an inline shell argument; quoting failures can silently truncate
the contract.

## Manage the governance lifecycle

Treat versioned source and external enforcement as separate planes. Governance
source is installed or removed only through an Issue-linked PR. The lifecycle
script never deletes itself or other tracked files; it manages only the dedicated
`swaw-change-governance` Ruleset and reports the exact source-removal boundaries
declared by `ownership.json`. It never manages `protect-main`.

```powershell
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 status
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 plan-install
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 install
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 plan-disable
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 disable
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 plan-uninstall
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 uninstall
```

- Run `status` and the matching `plan-*` command before every lifecycle mutation.
- `install` is valid only after the manifest and trusted workflows are present on
  GitHub `main`. It creates an absent dedicated Ruleset or enables its exact
  disabled projection; arbitrary drift is never reconciled. Any other Ruleset in
  the reserved `swaw-change-governance--*` namespace is a blocking collision, not
  an adoption candidate.
- `disable` changes only the dedicated Ruleset's enforcement to `disabled`.
- `uninstall` requires that disabled state, deletes only the exact dedicated
  Ruleset, and reports `source_removal_pending` plus a structured source
  disposition: directories, files, exact managed-block markers, and retained
  shared files. Issues, PRs, commits, Actions history, product validation,
  `protect-main`, and its retained manager are never removed.
- Before `uninstall`, the remote `protect-main` must exactly match its retained
  active declaration and contain no governance checks. Keep the dedicated
  Ruleset active while applying that product-baseline migration; otherwise
  `uninstall` fails closed to prevent orphaned required contexts.
- Prepare and fully review the exact source-removal Draft PR while governance is
  still active, then mark it ready and let that event finish. After its HEAD,
  body, checks, and conversations are final, the owner must remove and reapply the
  migration label as the last PR mutation. Separately authorize `disable` and
  `uninstall` from a clean synchronized `main`, read back `absent`, and then merge
  that unchanged PR immediately. Never merge source removal while the dedicated
  Ruleset is active; its required contexts would outlive their workflow providers.
- `source_removal_pending` is an immediate operation result, not stored lifecycle
  memory. A later `status` with source present and Ruleset absent reports
  `source_only`; the Issue and prepared Draft PR are the durable record of intent.
- The 128-bit token is a low-collision installation identity, not proof of who
  created a Ruleset. Keep it stable. To rotate it, first disable and uninstall the
  old tokenized entity using the old manifest, then merge the synchronized
  manifest/JSON change and install the new identity.
- Partial or invalid source, remote drift, and namespace collisions fail closed.
  There is no general `-Force`. Prefer a reviewed source repair. If the script can
  no longer recover, the repository owner must record the exact tokenized name and
  ID, disable that one Ruleset in GitHub Settings, read it back, and only then
  delete it when uninstall is intended; unrelated sibling identities remain
  untouched.
- If stale governance contexts are manually reintroduced after a complete source
  uninstall, the retained product manager permits an explicit recovery update
  only after confirming the governance executable sources are absent on `main`.
- These commands are idempotent, but a failed request has an unknown outcome.
  Never retry automatically; run `status` and inspect GitHub first.
- `install`, `disable`, and `uninstall` mutate the GitHub control plane and always
  require separate explicit authorization under root policy.

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
  governance enforced or a PR merge-eligible, verify both remote layers: use
  `.github/rulesets/scripts/protect-main.ps1 status` for the retained product
  `protect-main` declaration and
  `scripts/lifecycle.ps1 status` for governance. Apply either control-plane change
  only after explicit authorization. Report missing, disabled, or drifting
  required enforcement as a blocker.
- Never merge or enable auto-merge. Report when required checks and review state
  make the PR eligible for the repository owner to merge.
- Treat `.github/workflows/**`, the policy-loaded `governance.psm1`, and its
  retained `repository.psm1` dependency as trust roots. Their migration requires
  an owner-authored PR and the repository owner
  to remove and reapply `governance-migration` after reviewing the current HEAD.
  Make that the final PR mutation: every later commit or PR-body edit invalidates
  the authorization and requires another owner review and label cycle. Never add,
  remove, or automate that label as Agent.

## Sources of truth

- Root maintenance and Git protocol: `../../../AGENTS.md`
- Exact governance ownership: `ownership.json`
- Issue input contract: `../../../.github/ISSUE_TEMPLATE/change.yml`
- PR input contract: `../../../.github/PULL_REQUEST_TEMPLATE.md`
- Trusted change-policy validation: `../../../.github/workflows/change-policy.yml`
- Candidate governance validation:
  `../../../.github/workflows/validate-governance.yml`
- Candidate product validation: `../../../.github/workflows/validate.yml`
- Desired governance enforcement:
  `../../../.github/rulesets/swaw-change-governance.json`
- Desired product and baseline protection:
  `../../../.github/rulesets/protect-main.json`
- Retained product Ruleset manager and shared dependencies:
  `../../../.github/rulesets/scripts/`
- Retained product Ruleset verification:
  `../../../.github/rulesets/tests/protect-main.ps1`
- Governance verification: `tests/workflow.ps1`,
  `tests/ruleset-migration.ps1`, `tests/lifecycle-model.ps1`,
  `tests/lifecycle.ps1`, and `tests/policy.ps1`
