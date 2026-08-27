---
name: govern-repository-change
description: Govern version-controlled additions, modifications, and deletions through GitHub Issues, linked branches, commits, pull requests, independent review handoff, validation evidence, and human merge. Use before starting, resuming, reviewing, or submitting such work. Do not use for read-only analysis, explanation, or diagnosis.
---

# Govern Repository Change

The repository-root `AGENTS.md` is the policy authority. This Skill routes each
task to the procedure it needs; references add mechanics but cannot relax root
authorization, review, trust-root, or merge boundaries.

## Choose one route

- Read-only analysis, explanation, or diagnosis does not create an Issue or
  branch. Run `scripts/status.ps1` only when workflow state matters.
- Before starting, resuming, committing, pushing, or submitting a governed
  change, read [references/change-workflow.md](references/change-workflow.md)
  completely and follow its current route.
- Before handing off or repeating independent review, read
  [references/review-handoff.md](references/review-handoff.md) completely. A
  candidate change to this route, that reference, an applicable `AGENTS.md`, or
  `scripts/review-policy-snapshot.ps1` requires the protected-review path using
  fetched-base rules.
- Before installing, migrating, disabling, recovering, or uninstalling remote
  enforcement, read [references/control-plane.md](references/control-plane.md)
  completely. These mutations always need separate explicit authorization.

Read only the references required by the selected route. A change may use more
than one route, but ordinary development must not load lifecycle recovery or
protected-review mechanics merely because they exist.

## Stable boundaries

- A user request to implement a version-controlled change authorizes the
  ordinary Issue/branch/commit/fast-forward-push/Draft-PR path defined by root
  policy. It does not authorize history rewriting, other refs, Issue closure,
  Ready, control-plane mutation, or merge.
- Preserve one open Issue, one linked branch, and one `main` PR as the auditable
  change boundary. Material scope or acceptance changes go to the Issue first.
- Validation scope may add checks but cannot waive repository policy. Never
  execute free-form Issue text as shell code.
- Local targeted validation and owner-initiated independent review are the
  routine path. `Change policy` is the only automatic required-check target;
  optional full workflows are exact-revision evidence, not a substitute for
  semantic review.
- Reviewer, Ready, trust-root migration label, Issue disposition, remote
  enforcement, and merge ownership stay with the repository owner as specified
  by root policy.

## Entry points

```powershell
& .\.agents\skills\govern-repository-change\scripts\status.ps1
& .\.agents\skills\govern-repository-change\scripts\start.ps1 @issueFields
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 status
```

Prefer these repository scripts for governed state and lifecycle operations.
Direct `ghswaw` is limited to read-only inspection, documented recovery, the
authorized Draft-PR create/update path, or an owner-explicit full-validation
dispatch described by the change workflow reference.

## Sources of truth

- Root policy: `../../../AGENTS.md`
- Exact ownership: `ownership.json`
- Issue and PR inputs: `../../../.github/ISSUE_TEMPLATE/change.yml` and
  `../../../.github/PULL_REQUEST_TEMPLATE.md`
- Trusted policy check: `../../../.github/workflows/change-policy.yml`
- Optional full validation: `../../../.github/workflows/validate.yml` and
  `../../../.github/workflows/validate-governance.yml`
- Desired enforcement: `../../../.github/rulesets/protect-main.json` and
  `../../../.github/rulesets/swaw-change-governance.json`
- Governance tests: `tests/`
