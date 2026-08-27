# Ordinary change workflow

Read this reference before starting, resuming, committing, pushing, or
submitting version-controlled work.

## Establish or resume the change

1. Run `scripts/status.ps1`. Resume a valid Issue-linked branch; do not create a
   duplicate change boundary.
2. Start only from a clean, synchronized `main`. Before invoking
   `scripts/start.ps1`, state the intended Issue fields to the owner.
3. Record Outcome, Reason, Scope, Non-goals, Invariants, Acceptance criteria,
   and a Validation scope containing repository-controlled checks or test IDs,
   important scenarios, known omissions, and whether final full GitHub
   validation is required.

```powershell
$issueFields = @{
    Title = 'Govern one bounded change'
    Slug = 'govern-bounded-change'
    Outcome = 'The observable result.'
    Reason = 'Why it is needed.'
    Scope = 'Owned paths or behavior.'
    NonGoals = 'Explicit exclusions.'
    Invariants = 'Behavior that must remain true.'
    ValidationScope = @(
        'Targeted checks: named repository tests.'
        'Important scenarios: success and failure boundaries.'
        'Known omissions: explicitly untested behavior.'
        'Final full remote validation: required/not required, with reason.'
    ) -join "`n"
    AcceptanceCriteria = @('One independently verifiable result.')
}
& .\.agents\skills\govern-repository-change\scripts\start.ps1 @issueFields
```

Issue creation and linked-branch creation are not atomic. If either result is
uncertain, do not retry, close, or delete automatically; inspect GitHub and
report the observed state. Send later Issue edits as a complete UTF-8 payload or
body file, read them back, and revalidate the contract.

## Implement and commit

- Keep implementation, tests, and any current spec change together. Update the
  Issue first when its semantic contract changes.
- Commit titles use `type(scope): imperative summary`; allowed types are
  `feat`, `fix`, `refactor`, `test`, `docs`, `build`, `ci`, and `chore`. Scope is
  a stable lowercase ASCII domain, the summary starts with lowercase ASCII or a
  digit, and the title is at most 72 characters without a final period.
- Use `Refs: #<issue-id>` and applicable `Spec: <rule-id>` trailers. Explain
  architecture, protocol, recovery, security, compatibility, or non-obvious
  tradeoffs in the body. Never use a closing keyword for the primary Issue
  except in the bounded bootstrap below.
- Derive the message and semantic boundary from the staged diff. Before commit,
  inspect worktree and staged paths, run proportionate validation, and stage
  only task-owned files.

## Validate locally and optionally remotely

Run the Issue-declared targeted checks locally against the stable candidate and
record exact commands, results, and omissions in the PR. A reviewer may expand
the scope but cannot silently waive declared evidence.

Product and governance full workflows are optional exact-revision evidence.
They self-test automatically only when their own workflow trust root changes.
For any other candidate, do not dispatch them merely because the Issue says they
are needed. Wait for the owner to explicitly request `启动 GitHub 全量验证`,
then resolve the current PR number plus immutable base and head SHAs, dispatch
only the applicable workflow(s), and verify that each run tested those exact
inputs. A later head change invalidates the result. Updating PR verification
evidence also invalidates any prior independent review.

```powershell
$prNumber = <open-pr-number>
$revisions = ghswaw pr view $prNumber --json baseRefOid,headRefOid |
    ConvertFrom-Json
$inputs = @(
    '--ref', 'main',
    '-f', "pr_number=$prNumber",
    '-f', "base_sha=$($revisions.baseRefOid)",
    '-f', "head_sha=$($revisions.headRefOid)"
)
ghswaw workflow run validate.yml @inputs
ghswaw workflow run validate-governance.yml @inputs
```

Run only the workflow named by the authorized scope; both commands are shown so
the dispatch contract is explicit, not to make both routine.

## Push and prepare the Draft PR

Immediately before push, rerun `scripts/status.ps1`. Proceed only when the
context is valid, the worktree is clean, the branch tracks its exact origin
counterpart, it is not behind or diverged, and GitHub's branch OID matches the
remote-tracking OID. Push only `HEAD` to the same branch without force, then
rerun status.

Create or update only the matching Draft PR against `main`. Use a standalone
`Refs: #<issue-id>` line and, outside the bounded bootstrap below, never use
`close`, `fix`, or `resolve` closing keywords for the primary Issue. Record
Outcome, Changes, Verification, Deviations from Issue, Review focus, and the
complete author checklist.

There is one bounded bootstrap exception when the fetched base's trusted
`Change policy` still requires a standalone `Closes #N` while this candidate is
introducing the non-closing contract. That migration PR carries both standalone
`Closes #N` and `Refs: #N` lines, documents the deviation, uses fetched-base
status as the live transaction authority, and proves the candidate contract
with offline tests. Disable GitHub's repository auto-close setting before
merge. The exception expires as soon as this policy becomes the PR base; no
later PR may reuse it.

`scripts/start.ps1` intentionally keeps GitHub's formal Development link. A
non-closing PR reference alone cannot override GitHub's repository setting
**Settings → General → Issues → Auto-close issues with merged linked pull
requests**. The owner must disable that external setting before relying on
post-merge manual Issue disposition; repository files cannot prove it. After
merge, only the owner reviews and closes or retains the Issue.

If an Issue is edited, closed, or reopened after `Change policy` passes, edit
the PR body or push a new commit so the required check reruns against the new
Issue snapshot. Never carry the old green result forward.

Trust-root paths require an owner-authored PR. After the final HEAD, PR body,
checks, and conversations are stable, the owner reviews that exact candidate and
removes then reapplies `governance-migration` as the final PR mutation. Any later
commit or PR-body edit invalidates it. The Agent never operates that label,
marks Ready, merges, or enables auto-merge.
