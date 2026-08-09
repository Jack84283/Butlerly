# IMP-0004 — Application Services

Status: Implemented locally

## Authoritative sources

- PRD-0003 — Finance MVP v1.0
- PRD-0004 — Domain Model v1.0
- DEV-0001 — Butlerly Codex Implementation Specification
- ENG-0106 — Application Service Standards
- ENG-0107 — Repository Standards

## Application services delivered

- Framework-independent application package with no Flutter or SQLite dependency
- Immutable transaction commands, queries, and presentation-safe DTOs
- Explicit success/failure results with domain and repository error mapping
- Create, update, get, list, search, filter, archive, restore, and permanent-delete transaction use cases
- Merchant, category, payment-source, and tag assignment workflows
- Evidence-to-transaction attachment workflow with relationship checks
- Save/list services for payment sources, merchants, categories, and tags
- Constructor-injected repository abstractions and application clock
- SQLite-backed local search across transaction, merchant, category, evidence, and extraction text
- Local filters for date, category, payment source, currency, direction, lifecycle state, and review state

## Architecture

- Presentation code receives immutable DTOs rather than persistence records.
- Application services depend only on finance-domain repository interfaces.
- SQLite query implementation remains in the database infrastructure package.
- Domain invariants remain in domain entities and value objects.
- Application validation covers workflow inputs such as valid date ranges and referenced-record existence.
- Updating original money removes stale normalized-money derivations instead of treating them as canonical.
- Archival is the normal reversible removal workflow; permanent deletion remains explicit.

## Verification coverage

- Manual transaction creation and provenance generation
- Canonical updates with provenance retention
- Query and filter delegation through repository abstractions
- Invalid date-range rejection
- Repository failure mapping
- Missing relationship-target handling
- Archive and restore lifecycle
- SQLite local text search and compound filtering

## Intentional limits

- UI integration belongs to IMP-0005 and later feature milestones.
- Receipt binary selection and local file storage belong to IMP-0009; this milestone links existing evidence records.
- Import orchestration belongs to IMP-0010.
- Backup and restore orchestration belongs to IMP-0011.
- Application services do not invoke AI or any network provider.

## Next milestone

IMP-0005 — Main Navigation and Home
