Repair the failing CI checks on the supplied Butlerly pull request branch.

Read AGENTS.md, the PR, its linked issue, review conversations, and failing check output. Fix only failures caused by or relevant to the pull request. Preserve the approved requirements and persisted-data meaning.

Run ./tool/validate.sh and any affected platform build. Push fixes to the existing branch. Do not create a second pull request.

Stop and report needs-decision if the only apparent fix would change approved financial semantics, migration meaning, privacy, security, or destructive behavior.
