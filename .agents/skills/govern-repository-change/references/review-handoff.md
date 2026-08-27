# Independent review handoff

Read this reference after the Draft PR body and candidate branch are stable.

## Freeze the inputs

Run `scripts/status.ps1`, fetch the PR base, and verify a clean worktree plus
equality among local `HEAD`, the exact remote branch OID, and GitHub's PR head
SHA. Ensure the Issue Validation scope and PR Verification and Review focus
describe the current candidate. Resolve base and head to immutable commit SHAs.
For the one-time closing-reference bootstrap defined by the change workflow,
the fetched-base status script governs the live PR while candidate status is
future-contract test evidence; report both results and the documented deviation.

Inspect the complete base-to-head diff before choosing a mode. Any change to an
applicable `AGENTS.md`, the Skill's review route, this reference, or
`scripts/review-policy-snapshot.ps1` makes candidate review policy untrusted.

## Ordinary review

For an ordinary candidate, ask the owner to type `/review` in the current Codex
task, choose **Review against a base branch**, and select fetched `origin/main`.
Do not invoke it for the owner or require a custom prompt. A short `修` resumes
the same task after findings. If review delivery is configured as Detached,
disclose that it opens separately.

The review is read-only evidence about the selected diff, not proof of a fresh
chat, detached context, or temporary clone. It must use the Issue, applicable
Accepted spec, complete PR body and diff, validation scope, and evidence; report
prioritized actionable correctness, security, recovery, protocol, regression,
and test gaps; and never mutate repository or GitHub state.

The reviewer must obtain the current PR and Issue itself through read-only
`scripts/status.ps1` and `ghswaw pr view` / `ghswaw issue view`, then verify that
`baseRefOid` equals the fetched base selected for review and `headRefOid` equals
the reviewed `HEAD`. It must not infer these inputs from conversational context.
If read-only GitHub access, any required input, or either exact SHA comparison
is unavailable, the review is inconclusive and cannot support merge eligibility.

## Protected review

Do not use ordinary `/review` when review-governing policy changes. Materialize
and run the exact fetched-base `scripts/review-policy-snapshot.ps1` with immutable
base and head SHAs; the candidate enumerator cannot authorize itself. Enumerate
policies from both trees so changed or deleted nested policies remain visible.
Read every base version as non-waivable and every candidate version as additive.

Read the fetched-base and candidate `SKILL.md`. When present, also read each
revision's `references/review-handoff.md`; if the fetched base predates that
reference, its `SKILL.md` Review and hand off section remains the non-waivable
source. Report exact SHAs and the complete policy path list, then ask the owner
to type `启动受保护评审`. This is a natural-language governance trigger, not a
slash command or hidden UI option.

If the fetched base lacks review constraints or its policy enumerator during a
bootstrap, independently enumerate changed paths and both Git trees with
read-only Git commands. Before requesting the trigger, show the owner the exact
SHAs, policy paths, and this complete minimum: review the full diff; read the
complete Issue, applicable Accepted spec, complete PR body, validation scope and
evidence; report the prioritized risks above; remain read-only; and never mark
Ready, mutate repository or GitHub state, operate the control plane, or merge.
The owner's reply authorizes exactly the displayed minimum. Candidate policy is
review input, never bootstrap authority.

After the explicit trigger, create a disposable independent clone pinned to the
exact PR head, detach it, remove every remote, and verify a clean worktree, zero
remotes, and no credential-bearing clone-local configuration. This proves only
clone-local state; a same-user reviewer may still inherit global credential
helpers or authenticated tools. Instruct it not to use network access or any
authenticated external tool. If OS-level isolation is required, fail closed
unless a separate OS identity, container, or VM is available.

Spawn a fresh read-only reviewer subagent bound to the immutable base and head.
Give it every non-waivable base policy snapshot, additive candidate policy, the
complete Issue, applicable Accepted spec, complete PR body including deviations,
verification and review focus, complete diff, and evidence. If any snapshot,
fresh reviewer, or isolated clone cannot be established, fail closed rather than
downgrading to ordinary review.

## Findings and completion

Return findings to the same implementation task. Update the Issue first if scope
or acceptance changes, then verify, commit, and push normally. Every new commit
or changed review input invalidates the prior result; ask the owner to repeat the
applicable `/review` or `启动受保护评审` trigger.

With no actionable findings, rerun status and re-read the Issue, complete PR,
`baseRefOid`, and `headRefOid` to confirm every reviewed snapshot is unchanged.
Verify actual required checks, remote Rulesets, and review conversations before
reporting eligibility. Never mark Ready or merge. The owner may explicitly
request this isolated procedure for an otherwise ordinary PR.
