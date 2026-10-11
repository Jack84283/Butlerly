# Butlerly Flutter app

This directory contains Butlerly's local-first, account-free Flutter application. It supports phone, tablet and desktop layouts, with English, Spanish and Simplified Chinese interfaces. Core features work without cloud services or optional AI providers.

## Setup and validation

From the repository root, run `./tool/setup.sh` and `./tool/validate.sh`. Required Flutter/Dart versions are pinned in `tool/toolchain.env`.

Source code is under `lib/`. Finance domain, application and SQLite persistence live in the shared packages under `../../packages/`.

For current product and UI specifications use repository-root `AGENTS.md`, `PRODUCT.md`, and `DESIGN.md`; actual implementation tokens and widgets live under `lib/design_system/`. Deployment instructions are next to the platform scripts in `scripts/deploy/`.
