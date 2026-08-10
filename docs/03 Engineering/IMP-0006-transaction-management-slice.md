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
- Local text search with currency, direction, date-range, category, and review-state filters
- Explicit local merchant, category, and tag creation/assignment from transaction detail
- Search results open the same canonical local transaction detail
- Review-state indicator on transaction detail and a local Review queue for active issues
- Explicit local resolve and dismiss actions for review issues
- Transaction record-history presentation from canonical provenance, plus local evidence-metadata retrieval
- Read-only normalized-currency reference presentation that keeps original transaction money canonical

## Architecture

Flutter presentation calls `FinanceServices`, which composes IMP-0004 application use cases over the SQLite transaction repository. Presentation code does not query SQLite directly.

## Intentional limits

- Payment-source filtering and management belong to IMP-0007. Evidence, provenance, and normalized-currency presentation remain in later P0 work.
- Binary evidence selection, persistence, file lifecycle, and local file storage belong to IMP-0009 and are explicitly out of scope for this slice.
- No synchronization, account, device-trust, or Assistant-navigation functionality was added.

## Scope resolution

IMP-0006 previously described binary evidence capture as remaining P0 work, while IMP-0004 assigned receipt binary selection and local file storage to IMP-0009. The product decision resolves this inconsistency: IMP-0009 owns binary evidence selection, persistence, file lifecycle, and local file storage. IMP-0006 may present canonical provenance and evidence metadata only.

## Verification

- Logging redaction unit test
- Application-service test for listing and resolving review issues
- Transaction lifecycle, category-filtered local-search, and review-resolution widget tests
- Flutter analysis and test suite

## Next step

Complete any remaining transaction failure/recovery coverage while preserving the existing offline architecture. Begin IMP-0007 before adding payment-source filtering.
