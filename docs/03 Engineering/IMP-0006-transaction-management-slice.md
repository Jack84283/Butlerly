# IMP-0006 — Transaction Management

Status: Active P0 vertical slice implemented locally

## Scope delivered

- Local transaction list with loading, empty, and safe retry states
- Manual transaction creation with amount, currency, direction, date, and optional description
- Canonical transaction detail
- Edit flow through application services
- Reversible archive and explicit permanent-delete confirmation
- SQLite-backed persistence wired through the application-service boundary
- Widget test covering create → detail → edit → archive → permanent delete
- Privacy-safe logging redaction and test before financial fields reach presentation

## Architecture

Flutter presentation calls `FinanceServices`, which composes IMP-0004 application use cases over the SQLite transaction repository. Presentation code does not query SQLite directly.

## Intentional limits

- Merchant, category, tag, payment-source, evidence, provenance, and normalized-currency presentation remain in later parts of IMP-0006/IMP-0008/IMP-0009 as applicable.
- Search/filter user interface and Review resolution remain P0 work not delivered by this slice.
- No synchronization, account, device-trust, or Assistant-navigation functionality was added.

## Verification

- Logging redaction unit test
- Transaction lifecycle widget test
- Flutter analysis and test suite

## Next step

Continue IMP-0006 with local search/filter UI and transaction organization presentation, while preserving the existing offline architecture.
