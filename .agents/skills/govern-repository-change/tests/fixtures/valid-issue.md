### Outcome

Exercise the offline workflow.

### Reason

Protect change-governance boundaries.

### Scope

The temporary fixture only.

### Non-goals

Real GitHub access.

### Invariants

No external state changes.

### Validation scope

- Targeted checks: the offline governance workflow test.
- Important scenarios: linked Issue, branch, and PR identity remain consistent.
- Known omissions: live GitHub mutations.
- Final full remote validation: not required for this fixture.

### Acceptance criteria

- [ ] The status is valid.

### Readiness

- [x] The outcome is bounded enough for one branch and one PR.
- [x] Unknowns and assumptions are explicit; implementation will not silently decide them.
- [x] Version-controlled changes will begin only after an Issue-linked branch exists.
