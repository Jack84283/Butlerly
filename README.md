# Butlerly

Butlerly is a local-first, privacy-first personal operations assistant. Version 1 begins with a trustworthy personal-finance experience while keeping user data, control, and core workflows on the device.

## Repository layout

- `apps/butlerly` — cross-platform Flutter application
- `packages/butlerly_finance_domain` — framework-independent Finance V1 domain model
- `packages/butlerly_finance_application` — framework-independent commands, queries, DTOs, and use cases
- `packages/butlerly_database` — SQLite schema, migrations, mappings, and repositories
- `docs` — implementation and architecture notes maintained with the code
- `.github/workflows` — continuous integration

Shared packages will be introduced under `packages/` only when a current capability needs a stable reusable boundary. This avoids speculative abstractions while preserving the ENG-0101 monorepo model.

## Development

Requirements:

- The exact Flutter and Dart versions declared in `tool/toolchain.env`

The repository pin is authoritative for contributors, Codex, and GitHub Actions.
Setup verifies the installed SDKs and prints both expected and actual versions.
Run the canonical validation pipeline from anywhere in the checkout:

```sh
./tool/setup.sh
./tool/validate.sh
```

`tool/validate.sh` owns formatting, analysis, package and Flutter tests, and the
web build. CI calls the same scripts and separately retains the iOS simulator
build. `tool/check_toolchain_consistency.sh` prevents CI and local configuration
from silently drifting apart.

The application does not require an account, network service, cloud database, or AI provider for core operation.
