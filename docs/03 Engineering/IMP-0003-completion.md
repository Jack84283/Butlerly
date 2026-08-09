# IMP-0003 — Local Persistence

Status: Implemented locally

## Authoritative sources

- PRD-0003 — Finance MVP v1.0
- PRD-0004 — Domain Model v1.0
- ARC-0301 — Data Architecture
- ARC-0302 — Storage Architecture
- ARC-0303 — Backup & Restore
- ADR-0003 — SQLite
- ENG-0107 — Repository Standards

## Persistence delivered

- Domain-owned repository interfaces with stable failure categories
- SQLite schema version 1 and deterministic initial migration
- Foreign-key enforcement and deliberate query indexes
- Explicit persistence mapping for exact decimal money and UTC timestamps
- Transaction aggregate repository with atomic child replacement
- PaymentSource, Merchant, Category, and Tag repositories
- Evidence, Extraction, AttachmentLink, and Suggestion persistence
- ReviewIssue, Provenance, ExchangeRate, and NormalizedMoney persistence
- Integrity-check and WAL-checkpoint hooks for a future consistent backup workflow
- Flutter application startup wired to the production Version 1 schema

## Verification coverage

- Migration and schema version
- Foreign-key activation
- SQLite integrity check
- Atomic rollback
- Full transaction aggregate round trip
- Unicode and source-language preservation
- Original and normalized currency preservation
- Controlled database failure mapping
- Archive and permanent-delete behavior
- Evidence linking and suggestion separation

## Intentional limits

- Attachment binary files remain outside SQLite; only metadata and relationships are stored.
- Full backup package creation and restore activation remain in IMP-0011.
- Search-oriented repository queries and application orchestration remain in IMP-0004.
- Database encryption requires a dedicated ADR and is not assumed by SQLite.

## Next milestone

IMP-0004 — Application Services
