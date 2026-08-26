Implement the approved GitHub issue supplied with this task.

Follow AGENTS.md and read every authoritative repository document linked by the issue. Work until all acceptance criteria are implemented and verified.

Required status behavior:

1. As soon as this task is actually picked up for execution, and before making implementation changes, post a short comment on the originating GitHub issue confirming that Codex Cloud has started work. Use a concise status such as: `Codex Cloud picked up this issue and started implementation.` Include the task branch name when it is already known.
2. Do not post this acknowledgement merely because an `@codex` delegation comment exists; post it only after the task has actually started executing.
3. If a material decision blocks completion, post the structured needs-decision report to the originating issue as soon as the blocker is identified.
4. When a pull request is created or updated, ensure the issue can identify the PR from the issue/PR linkage and final report.

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
