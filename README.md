# Butlerly

Butlerly is a local-first, privacy-first personal operations assistant. Version 1 begins with a trustworthy personal-finance experience while keeping user data, control, and core workflows on the device.

## Repository layout

- `apps/butlerly` — cross-platform Flutter application
- `packages/butlerly_finance_domain` — framework-independent Finance V1 domain model
- `packages/butlerly_database` — SQLite schema, migrations, mappings, and repositories
- `docs` — implementation and architecture notes maintained with the code
- `.github/workflows` — continuous integration

Shared packages will be introduced under `packages/` only when a current capability needs a stable reusable boundary. This avoids speculative abstractions while preserving the ENG-0101 monorepo model.

## Development

Requirements:

- Flutter 3.44 or a compatible stable release
- Dart 3.12 or a compatible release

Run the validation pipeline:

```sh
cd apps/butlerly
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
```

Validate the finance domain independently:

```sh
cd packages/butlerly_finance_domain
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze
dart test
```

Validate local persistence:

```sh
cd packages/butlerly_database
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

The application does not require an account, network service, cloud database, or AI provider for core operation.
