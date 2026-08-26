Review the pull request against AGENTS.md, its linked approved documents, and the base branch.

Prioritize correctness, persisted compatibility, financial meaning, privacy, security, destructive behavior, missing production-path tests, and discrepancies between parsed and persisted declarative definitions.

Report only actionable findings. For each finding include severity, affected file and behavior, reproduction or reasoning, and the smallest safe correction. If no consequential finding exists, state that clearly.

## Status behavior for @codex PR work

When an `@codex` request on a pull request asks Codex Cloud to review findings, address findings, or perform another PR follow-up task:

1. As soon as the PR task is actually picked up for execution, post a concise top-level PR conversation comment confirming pickup, for example: `Codex Cloud picked up these PR findings and started work on branch <branch>.`
2. Do not treat the original `@codex` comment as proof that execution has started. The pickup comment is posted only after Codex Cloud actually begins the task.
3. For long-running PR work, post concise milestone updates when useful, such as review complete, fixes in progress, implementation fixes complete, validation started, validation fixes in progress, or PR update preparation started.
4. If roughly 20–30 minutes pass during active work without another useful milestone update, post a best-effort `still working` status with the current phase and whether a blocker or decision is required. Avoid noisy duplicate comments.
5. When validation begins, post a status update. If substantial fixes are required, post another concise update describing the affected area rather than raw logs.
6. When the requested PR work is complete, post a final top-level PR comment stating what was addressed, validation results, branch, whether the PR was updated, and any unresolved decisions/findings.
7. If a material decision blocks the requested PR work, post the structured needs-decision report promptly.
8. Status reporting is observability, not an implementation dependency. If posting any status comment fails because of permissions, API availability, or another tooling problem, record the failure when possible and CONTINUE the requested review/fix/validation work. Never stop PR work solely because a status comment could not be posted.

When the task is review-only, do not modify code unless the `@codex` request explicitly asks for fixes. When the task asks to address findings, fix all in-scope findings on the existing PR branch, run the required validation, push the branch, and update the existing PR rather than creating a second PR.