Implement the approved GitHub issue supplied with this task.

Follow AGENTS.md and read every authoritative repository document linked by the issue. Work until all acceptance criteria are implemented and verified.

Required status behavior:

1. As soon as this task is actually picked up for execution, and before making implementation changes, post a short comment on the originating GitHub issue confirming that Codex Cloud has started work. Use a concise status such as: `Codex Cloud picked up this issue and started implementation.` Include the task branch name when it is already known.
2. Do not post this acknowledgement merely because an `@codex` delegation comment exists; post it only after the task has actually started executing.
3. For long-running work, keep the originating issue visibly updated while execution continues. Post a concise progress comment at meaningful milestones such as repository inspection complete, implementation phase complete, validation started, validation fixes in progress, or PR preparation started.
4. If no meaningful milestone has produced an update for roughly 20–30 minutes while the task is still actively running, post a lightweight status comment confirming that work is still in progress. Include the current phase and whether any decision/blocker is required. Exact wall-clock timing is best-effort; do not interrupt critical work merely to meet a timestamp.
5. Avoid noisy duplicate comments. Do not post more frequently than needed, and do not repeat an unchanged status unless approximately 20–30 minutes have passed without another useful update.
6. Suggested progress format: `Codex Cloud status: still working. Current phase: <phase>. Completed: <brief milestone>. Blockers/decisions: none.` Adjust the wording when a blocker exists.
7. If a material decision blocks completion, post the structured needs-decision report to the originating issue as soon as the blocker is identified; do not wait for the next periodic update.
8. When validation starts, post a status update. If validation requires substantial fixes, post another update describing the affected area without dumping raw logs.
9. When a pull request is created or updated, ensure the issue can identify the PR from the issue/PR linkage and final report.
10. The final issue/PR report replaces further periodic updates and must clearly state completion, validation results, branch, PR, and unresolved decisions.

Required completion behavior:

1. Inspect the current implementation and persisted compatibility constraints.
2. Map each acceptance criterion to code and tests.
3. Implement all in-scope work without rule-specific shortcuts.
4. Run ./tool/validate.sh.
5. Fix all in-scope failures.
6. Review the complete diff against main.
7. Commit and push the task branch.
8. Create or update the pull request.
9. Include requirement-to-test traceability in the PR description.

Do not stop after an intermediate increment. Do not leave a known in-scope defect for a future task.

If a material product, financial, migration, privacy, security, or destructive decision is missing, continue unaffected work and return a structured needs-decision report. Do not guess.

The final report must include the implementation summary, changed files, requirement-to-test mapping, checks executed and results, unresolved decisions, branch, and pull request.
