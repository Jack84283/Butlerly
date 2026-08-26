# Butlerly agent guide

## Authority order

When requirements conflict, use this precedence:

1. Butlerly Company Constitution
2. User Bill of Rights
3. Version 1 MVP definition
4. Product requirements
5. Architecture documents and accepted ADRs
6. UX specifications and design system
7. Engineering standards
8. Implementation specifications
9. Individual task instructions

Stop and request human review for a material conflict; do not silently choose a lower-level instruction.

## Core constraints

- Keep core operation local-first, offline-capable, and account-free.
- Treat SQLite on the user device as the Version 1 system of record.
- Keep AI optional, assistive, and behind provider abstractions.
- Keep domain logic independent of Flutter, SQLite, provider SDKs, and operating-system APIs.
- Put presentation, application, domain, and infrastructure responsibilities in their proper layers.
- Do not add future Life OS modules or speculative platform systems.
- Never commit secrets or personal user data.

## Authoritative implementation sources

For implementation work, read the approved documents linked by the GitHub issue. Repository copies under `docs/` are fixed implementation snapshots.

Do not implement documents marked Draft, Proposed, Superseded, or Pending Decision. When repository documents conflict, follow the authority order above and report material conflicts.

## Task completion contract

For a `codex-ready` issue:

1. Synchronize with the latest `main` branch and create or reuse a task branch.
2. Read every linked authoritative document completely.
3. Map each acceptance criterion to implementation and tests.
4. Inspect existing migrations and persisted compatibility requirements.
5. Implement all in-scope work.
6. Run `./tool/validate.sh`.
7. Fix all in-scope failures.
8. Perform the mandatory iterative pre-PR self-review described below. Fix every in-scope problem found and repeat review/validation until no consequential in-scope defect remains.
9. Review the final complete diff against `main` one last time.
10. Commit and push the branch.
11. Create or update the pull request only after the self-review exit criteria are satisfied.
12. Include requirement-to-test traceability and the completed self-review summary in the PR description.

Continue until the complete task is reviewable. Do not stop after an intermediate increment or leave a known in-scope problem for unspecified future work.

Stop only when a material ambiguity could change financial meaning, persisted compatibility, privacy, security, or destructive behavior.

## Mandatory iterative pre-PR self-review

Opening or updating a pull request is a quality gate, not the first review step. Before creating a new PR for implementation work, Codex must perform several deliberate self-review passes over its completed work. Do not assume that passing tests proves the implementation is complete.

At minimum, perform these review passes:

### Pass 1 — Requirements and product behavior

- Re-read the issue and every linked authoritative source after implementation.
- Verify every acceptance criterion against the actual production behavior, not merely the presence of classes, methods, tests, or configuration.
- Confirm user-visible features are reachable through the real UI/navigation path and behave as specified.
- Check empty, error, loading, retry, localization, and relevant accessibility states.
- Identify anything implemented in code but not actually wired into the user experience.

### Pass 2 — Architecture and integration

- Review the complete diff against `main`, including callers and downstream consumers outside the edited files.
- Verify new services, use cases, repositories, rules, routes, and configuration are actually invoked where intended.
- Trace important data end-to-end through presentation, application, domain, persistence, and back again.
- Look for partial integrations, dead registrations, duplicate calculations, layer violations, and behavior accidentally implemented in presentation code.
- Verify generic/declarative mechanisms implement every semantic they accept; unsupported semantics must fail validation rather than be silently ignored.

### Pass 3 — Persistence, compatibility, and real-data edge cases

- Exercise write/read/reload or install/reconstruct paths for persisted definitions and state, not only in-memory fixtures.
- Check migrations, historical versions, upgrade behavior, defaults, nullability, and backward compatibility.
- Test realistic boundary cases relevant to the change, including zero/empty data, one item, multiple groups/dates, same-currency and foreign-currency data, missing normalization/FX data, reconciliation/deduplication, period/timezone boundaries, and unresolved dimensions when applicable.
- For financial calculations, independently sanity-check sign conventions, filters, units, currency basis, canonical transaction scope, and arithmetic relationships.

### Pass 4 — Adversarial regression review

- Review the implementation as if reviewing another engineer's PR and actively try to find reasons it should not merge.
- Apply the repository Code Review Rules below to the final diff.
- Inspect nearby existing behavior for regressions that task-specific tests may miss.
- Add targeted regression tests for every defect discovered during self-review.
- Re-run `./tool/validate.sh` after corrections.

If any pass finds a consequential in-scope defect, fix it, add or improve tests where appropriate, and repeat the affected passes. More than one iteration is expected when changes are non-trivial. Do not create the PR merely because a fixed number of passes has been completed.

### Pre-PR exit criteria

A new implementation PR may be created only when all of the following are true:

- Every acceptance criterion is implemented and mapped to verification.
- No known consequential in-scope defect remains.
- Production UI paths are wired and reachable where required.
- Persistence/reconstruction/migration paths affected by the change have been exercised.
- Financial calculations and units have been sanity-checked with representative edge cases when applicable.
- Parsed, persisted, and reconstructed declarative behavior is equivalent where applicable.
- Required validation passes, or any unexecutable check is explicitly reported with the reason and equivalent checks performed where possible.
- The final diff has received an adversarial self-review using the same standards expected from the later independent PR review.

The independent PR review remains required. The purpose of self-review is to prevent avoidable defects from being delegated to that later review stage, not to replace independent review.

## Clarification protocol

When blocked:

1. Continue all unaffected work.
2. Add a structured question to the issue.
3. Identify the conflicting sources.
4. List the available choices and consequences.
5. Recommend one choice.
6. Apply the `needs-decision` label.
7. Do not silently choose a financial or migration meaning.

## Code Review Rules

### Rule immutability

- Flag bundled definitions changed without a rule-version increment.
- Require upgrade tests when an installed rule definition changes.
- Preserve historical versions referenced by findings.

### Financial periods

- Primary and baseline calculations must use independently resolved windows.
- Use `transaction_date` and the persisted financial IANA timezone.
- Do not silently fall back from unsupported period types.

### Derived findings

- Recalculation must not reset acknowledged or dismissed lifecycle.
- Deleting derived results must never delete financial records.

### Declarative behavior

- Flag rule-ID-specific production branches.
- Parsed and SQLite-reconstructed definitions must behave identically.
- Unsupported YAML semantics must fail validation rather than be ignored.

### Test quality

- Require production-path tests for persistence and migration behavior.
- Manually constructed engine fixtures do not replace repository integration tests.

## Required verification

For each implementation task, format code, run static analysis, run relevant tests, and build affected targets where the local toolchain permits it. Report any check that could not be executed.
