# Butlerly Flutter app

Butlerly is the local-first, account-free personal finance application in this monorepo. This is an active Flutter application, not the default starter project.

## Setup and validation

From the repository root, run `./tool/setup.sh` and `./tool/validate.sh`. The supported Flutter and Dart versions are pinned in `tool/toolchain.env`.

The authoritative project guides are the repository-root `AGENTS.md`, `PRODUCT.md`, and `DESIGN.md`. Platform launch and packaging instructions live alongside their deploy scripts in `apps/butlerly/scripts/deploy/`.

Core operation uses on-device SQLite and works without a cloud account or optional AI service.
