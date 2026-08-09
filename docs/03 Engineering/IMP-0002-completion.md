# IMP-0002 — Finance Domain Foundation

Status: Implemented locally

## Authoritative sources

- PRD-0003 — Finance MVP v1.0
- PRD-0004 — Domain Model v1.0
- ARC-0204 — Domain Layer
- ARC-0301 — Data Architecture

## Domain delivered

- Butlerly-owned typed identifiers
- Exact base-10 decimal, currency, Money, ExchangeRate, and NormalizedMoney values
- Transaction aggregate with explicit timing, direction, source, lifecycle, provenance, review state, and optional organization references
- Account/PaymentSource, Merchant, Category, and Tag entities
- EvidenceItem, Extraction, and AttachmentLink separation
- Suggestion lifecycle that cannot directly mutate canonical transaction values
- ReviewIssue lifecycle and exception-first derived review state
- Provenance validation for imported, scanned, extracted, and AI-derived information
- Framework-boundary test preventing Flutter, SQLite, network, and platform dependencies

## Protected invariants

- Stable Butlerly identity is independent of external provider IDs.
- Every Money value includes currency.
- Original money remains separate from derived normalization.
- Machine output remains a suggestion or extraction until explicit acceptance.
- Review attention is driven by active ReviewIssues.
- Evidence originals and derived extraction values remain separate.
- Core domain construction requires no network, cloud identity, AI, database, or UI framework.

## Assumptions and limits

- Currency codes accept 3–8 uppercase alphanumeric characters so the domain is not limited to three-letter fiat codes.
- Decimal values preserve arbitrary base-10 precision; product-specific rounding policies remain deferred.
- Permanent deletion and duplicate merge workflows remain deferred to their approved application-service milestones.
- Repository interfaces and SQLite mappings belong to IMP-0003.

## Next milestone

IMP-0003 — Local Persistence
