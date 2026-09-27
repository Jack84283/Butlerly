# Implementation documentation

Google Drive is Butlerly's editable documentation workspace. GitHub stores immutable, versioned implementation snapshots when a Codex task needs reproducible approved inputs.

## Authority model

- Current approved Drive documents are the editable source used to prepare or update requirements.
- A `codex-ready` implementation issue must reference the required versioned repository snapshot(s) under `docs/`.
- Repository snapshots must match the approved Drive source at snapshot time and must not contain superseded behavior.
- Do not silently edit an approved snapshot so that an in-flight task changes meaning. Create a reviewed new version and update the issue instead.
- Completed or superseded snapshots may be deleted when they are no longer needed by an active task or audit trail.
- Do not use an old repository snapshot to reconstruct behavior that the current approved product has superseded.
- IMP identifiers must be unique across active documentation.

Before implementation, always inspect the current `main` branch as well as the issue-linked snapshots. Existing correct behavior must not be reimplemented merely because an old document once described it as pending.
