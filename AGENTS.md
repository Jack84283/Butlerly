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

## Required verification

For each implementation task, format code, run static analysis, run relevant tests, and build affected targets where the local toolchain permits it. Report any check that could not be executed.
