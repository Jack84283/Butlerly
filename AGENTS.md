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
9. Perform the mandatory fresh independent pre-PR review described below. Fix every actionable P1/P2-equivalent finding and repeat that review until none remain.
10. Perform the pre-PR CI parity gate described below and leave the working tree clean.
11. Review the final complete diff against `main` one last time.
12. Commit and push the branch.
13. Create or update the pull request only after the self-review, fresh independent review, and CI-parity exit criteria are satisfied.
14. Monitor all required GitHub checks after every PR push and perform the mandatory post-PR CI repair loop below until all required checks pass.
15. Include requirement-to-test traceability, completed self-review evidence, fresh independent-review evidence, validation evidence, and final CI status in the PR description.

Continue until the complete task is reviewable. Do not stop after an intermediate increment or leave a known in-scope problem for unspecified future work.

Stop only when a material ambiguity could change financial meaning, persisted compatibility, privacy, security, or destructive behavior.

## Mandatory iterative pre-PR self-review

Opening or updating a pull request is a quality gate, not the first review step. Before creating a new PR for implementation work, Codex must perform several deliberate self-review passes over its completed work. Do not assume that passing tests proves the implementation is complete.

For non-trivial changes, complete at least two full end-to-end self-review cycles. A cycle means running all applicable passes below, fixing every consequential issue found, adding regression coverage where appropriate, and re-running validation. If the second cycle still finds a consequential defect, continue additional cycles until a complete cycle finds no consequential in-scope defect. The number of review cycles is therefore a minimum, not a stopping condition.

At minimum, each cycle must include these review passes:

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
- Explicitly search for P1/P2-class defects: production-path failure, incorrect financial values, persistence/reload breakage, unreachable required UI, silently ignored supported semantics, data loss, privacy/security regressions, misleading success/all-clear states, environment-dependent parsing, shell/toolchain assumptions, and platform-specific failures.
- Inspect nearby existing behavior for regressions that task-specific tests may miss.
- Add targeted regression tests for every defect discovered during self-review.
- Re-run `./tool/validate.sh` after corrections.

If any pass finds a consequential in-scope defect, fix it, add or improve tests where appropriate, and repeat the affected passes. More than one iteration is expected when changes are non-trivial. Do not create the PR merely because a fixed number of passes has been completed.

## Mandatory fresh independent pre-PR review

Self-review is necessary but not sufficient. For every non-trivial implementation, Codex must perform a **fresh independent review in a separate review context** after implementation and self-review are complete, and before opening the PR.

The independent reviewer must not rely on the implementation conversation, implementation notes, rationale, intermediate plans, or the author's assumptions. It must start from only:

- the approved GitHub issue and linked authoritative repository sources;
- `AGENTS.md` and `.github/codex/prompts/review.md`;
- the final diff against `main`;
- the final test/validation evidence.

The independent review must use the same severity standard as the later GitHub PR review and actively search for defects rather than confirm the implementation. It must inspect production behavior, integration, persistence/reconstruction, financial semantics where applicable, UI reachability, failure states, data loss/privacy/security risks, declarative semantics, shell/toolchain portability, environment-dependent behavior, and tests that may merely mirror the implementation.

### Fresh-review execution rules

- Treat the independent review as a new reviewer assignment, not another continuation of the implementation reasoning.
- Do not prime the reviewer with statements such as “the implementation is complete,” “all tests pass,” or explanations of why particular design choices were made beyond what exists in authoritative sources and the final diff.
- Require explicit P0/P1/P2-style findings with file/line evidence when issues exist.
- If the fresh review finds any actionable P1/P2-equivalent issue, return to implementation, fix it, add regression coverage, rerun validation, and then run a **new fresh independent review again** over the updated final diff.
- Repeat until a fresh independent review returns no actionable P1/P2-equivalent findings.
- P3-only cleanup may be deferred when clearly non-consequential and outside acceptance criteria, but it must be documented in the PR description.

### Fresh-review evidence

The PR description must record:

- that a fresh independent pre-PR review was executed;
- the final reviewed commit/diff state;
- any P1/P2 findings discovered before PR creation and how they were fixed;
- confirmation that the final fresh review found no unresolved actionable P1/P2-equivalent issue.

If the environment or available Codex tooling cannot create a genuinely separate review context, do not silently substitute ordinary self-review. Report that limitation on the issue before PR creation and use the strongest available independent-review mechanism.

## Pre-PR CI parity gate

The first GitHub CI run should be confirmation, not the first time CI-compatible validation is attempted.

Before creating or updating an implementation PR:

1. Run `./tool/setup.sh` when dependency/tool setup is required.
2. Record `dart --version` and `flutter --version` in the implementation log/PR evidence.
3. Run `./tool/validate.sh` from a clean working tree.
4. If formatting changes any file, treat that as a validation failure: keep the formatter output, re-run the affected self-review checks, and run `./tool/validate.sh` again.
5. Run `git diff --check`.
6. Run `git status --short` and ensure there are no uncommitted generated, formatted, or test-induced changes before PR creation.
7. Compare the repository CI workflow for any validation step not represented by `./tool/validate.sh` (for example, platform builds) and execute the equivalent locally when the toolchain permits it.
8. Never knowingly open a PR with a locally reproducible CI failure. If an exact CI check cannot run because of environment restrictions, state the restriction explicitly in the PR and run the closest equivalent check.

A repeated first-run CI failure caused by formatting, generated files, or another locally reproducible check is a process defect and must be corrected before the next implementation task rather than accepted as normal repair work.

### Pre-PR exit criteria

A new implementation PR may be created only when all of the following are true:

- Every acceptance criterion is implemented and mapped to verification.
- No known consequential in-scope defect remains.
- At least two complete self-review cycles have been performed for non-trivial work, and the final complete cycle found no consequential defect.
- A fresh independent pre-PR review has been performed in a separate review context for non-trivial work.
- The final fresh independent review found no unresolved actionable P1/P2-equivalent issue.
- Production UI paths are wired and reachable where required.
- Persistence/reconstruction/migration paths affected by the change have been exercised.
- Financial calculations and units have been sanity-checked with representative edge cases when applicable.
- Parsed, persisted, and reconstructed declarative behavior is equivalent where applicable.
- `./tool/validate.sh` passes on the final formatted tree, or any unexecutable check is explicitly reported with the reason and equivalent checks performed where possible.
- `git diff --check` passes and `git status --short` shows no unintended working-tree changes.
- The final diff has received an adversarial self-review using the same standards expected from the later independent PR review.

The independent GitHub PR review remains required. The purpose of the fresh pre-PR review is to catch avoidable P1/P2 defects before publication, not to replace the post-publication quality gate.

## Mandatory post-PR CI repair loop

Creating or updating a pull request does not complete a Codex implementation task. Codex owns the PR through required-check completion.

After every push to an implementation PR branch, Codex must:

1. Monitor the PR until all required GitHub checks for the new head commit reach a terminal state. Do not rely on stale checks from an earlier commit.
2. Confirm that every required check actually ran. A missing expected check, missing check suite, or workflow that failed to start is itself an item to diagnose when it is caused by the PR or repository configuration.
3. If all required checks pass, record the green CI state on the PR/issue and proceed to readiness reporting.
4. If any required check fails, inspect the failing job, step, and logs before stopping.
5. Classify the failure as one of:
   - **in-scope implementation/repository failure** — code, tests, formatting, generated files, dependency configuration, workflow configuration, platform build, validation script, or another defect introduced/exposed by the PR;
   - **transient CI/infrastructure failure** — runner outage, service outage, rate limit, temporary network failure, or another failure not caused by repository content;
   - **material decision/blocker** — requires a human product/architecture/security decision or credentials/permissions Codex cannot obtain.
6. For every in-scope implementation/repository failure, fix the root cause on the **same PR branch**, add or improve regression coverage when appropriate, rerun the relevant local validation/self-review, push the correction, and return to step 1.
7. For a likely transient CI/infrastructure failure, retry the failed job/run when permitted. If the same failure repeats and appears repository-related, treat it as an in-scope failure and repair it rather than repeatedly rerunning unchanged code.
8. Do not declare the PR ready, do not stop merely because a PR exists, and do not ask the human owner to initiate ordinary CI repair while any required in-scope check is red.
9. Continue the repair loop until **all required checks pass on the current PR head**.
10. Stop before green CI only when a genuine material decision, external infrastructure outage, or unavailable credential/permission prevents further progress. Report the exact blocker, evidence, and required human action.

### Post-PR review findings

If an independent GitHub PR review produces actionable P1/P2 findings while CI is running or after it is green, Codex must address those findings on the same PR branch, rerun the affected self-review/validation, push, and restart the CI repair loop for the new head. Green checks on an older commit do not satisfy readiness after review fixes.

### Post-PR completion criteria

Codex may report implementation complete only when:

- all required GitHub checks have run and passed on the current PR head;
- no known actionable P1/P2 review finding remains;
- the PR contains the required validation and review evidence;
- no material blocker or unresolved decision remains.

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
