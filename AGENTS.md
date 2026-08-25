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
8. Review the complete diff against `main`.
9. Commit and push the branch.
10. Create or update the pull request.
11. Include requirement-to-test traceability in the PR description.

Continue until the complete task is reviewable. Do not stop after an intermediate increment or leave a known in-scope problem for unspecified future work.

Stop only when a material ambiguity could change financial meaning, persisted compatibility, privacy, security, or destructive behavior.

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
