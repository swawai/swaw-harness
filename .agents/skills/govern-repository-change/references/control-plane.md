# Governance control plane

Read this reference only for Ruleset installation, migration, disable,
recovery, or uninstall work. Versioned source and external enforcement are
separate planes; every mutation requires separate explicit owner authorization.

The governance lifecycle owns only the tokenized
`swaw-change-governance--*` Ruleset declared by `ownership.json`. It never
creates, disables, deletes, or adopts `protect-main`; the retained product
manager owns that Ruleset.

```powershell
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 status
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 plan-install
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 install
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 plan-disable
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 disable
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 plan-uninstall
& .\.agents\skills\govern-repository-change\scripts\lifecycle.ps1 uninstall

& .\.github\rulesets\scripts\protect-main.ps1 status
& .\.github\rulesets\scripts\protect-main.ps1 plan
& .\.github\rulesets\scripts\protect-main.ps1 apply
```

Run `status` and the matching plan before every mutation. A failed request has
unknown outcome: never retry automatically; read remote state first.

## Install or migrate

- Trusted workflows and the desired Ruleset declaration must already be on
  GitHub `main`. `install` creates an absent dedicated Ruleset or enables its
  exact disabled projection; it never reconciles arbitrary drift.
- Any sibling in the reserved tokenized namespace is a blocking collision, not
  an adoption candidate. The 128-bit ownership token is a stable installation
  identity, not proof of the creator.
- When migrating from product-required heavy validation to the lightweight
  policy gate, activate and verify the dedicated Ruleset containing only
  `Change policy` first. Then separately plan, apply, and verify `protect-main`
  without the heavy Product context. This order avoids a window with no policy
  gate.
- Repository declarations are not evidence of enforcement. Re-read both remote
  Rulesets after mutation and report absent, disabled, or drifting state.

## Disable, uninstall, or recover

- `disable` changes only the dedicated Ruleset enforcement. `uninstall`
  requires it disabled, deletes only that exact entity, and reports the source
  disposition; it never deletes tracked source, Issues, PRs, Actions history,
  product validation, or `protect-main`.
- Before uninstall, `protect-main` must be active, in sync, and contain no
  governance contexts. Keep governance active while applying that product
  migration so no required context loses its workflow provider.
- Prepare and fully review the source-removal Draft PR while governance is
  active. Once its HEAD, body, checks, and conversations are final, mark Ready
  and wait for that event, then have the owner reapply the migration label as
  the last PR mutation. From synchronized clean `main`, separately authorize
  disable and uninstall, verify the dedicated Ruleset is absent, and only then
  merge the unchanged removal PR.
- `source_removal_pending` is an immediate result, not stored memory. Later
  `status` with source present and Ruleset absent reports `source_only`; the
  Issue and Draft PR preserve intent.
- Partial source, drift, unknown remote state, and namespace collisions fail
  closed. There is no general `-Force`. If scripts cannot recover, the owner
  records the exact tokenized name and ID, disables only that entity in GitHub,
  reads it back, and deletes it only when uninstall is intended.
- Rotate an ownership token only by disabling and uninstalling the old identity
  with its old manifest, then merging and installing the new identity. Never
  infer ownership of unrelated sibling Rulesets.
