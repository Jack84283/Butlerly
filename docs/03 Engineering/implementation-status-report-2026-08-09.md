# Butlerly Implementation Status Report

Date: 2026-08-10

## Executive summary

Butlerly has a sound local-first Finance V1 foundation: a pure domain model, SQLite persistence, application-service layer, responsive product-authoritative navigation, and an offline transaction-management vertical slice.

The scoped Finance V1 P0 implementation is feature-complete in the local slice. Remaining release work is manual smartphone visual/accessibility review on an unlocked host and any defects found by that review.

## Delivery status

| Milestone | Status | Delivered |
| --- | --- | --- |
| IMP-0001 — Application Foundation | Complete | Flutter shell, themes, adaptive navigation infrastructure, local database startup, logging, and tests. |
| IMP-0002 — Domain Foundation | Complete | Finance entities, value objects, stable IDs, provenance, review, suggestions, currency normalization, and domain-boundary tests. |
| IMP-0003 — Local Persistence | Complete | SQLite versioned schema, migrations, repository adapters, mappings, integrity checks, and persistence tests. |
| IMP-0004 — Application Services | Complete | Framework-independent commands, queries, DTOs, result/failure mapping, transaction workflows, relationship assignments, and local query support. |
| IMP-0005 — Main Navigation and Home | Complete local slice | Responsive Home, Transactions, Review, Search, and Settings destinations with local-first, truthful empty states. |
| IMP-0006 — Transaction Management | Complete local slice | Offline lifecycle, organization, search/filter, review, provenance/evidence metadata, normalized references, and schema-v2 business-date migration hardening. |
| IMP-0007 — Account Management | Active local slice | Local payment-source lifecycle, transaction assignment, display-name resolution, and filtering; no user-account or sync scope. |

## Architecture review

The implementation follows the intended dependency direction:

```text
Flutter presentation → application services → finance domain ← SQLite infrastructure
```

- The finance domain has no Flutter, SQLite, network, or platform dependencies.
- Application services use repository interfaces and do not import database infrastructure.
- SQLite remains the on-device system of record.
- The app starts without an account, network service, cloud database, or AI provider.
- Original values, source language, provenance, and suggestions are modeled distinctly from confirmed transaction state.

## P0 capability review

| Capability | Current state |
| --- | --- |
| Offline/account-free local workspace | Partially complete: local storage and account-free startup exist; first-use preferences do not. |
| Domain, persistence, and application boundaries | Complete. |
| Primary navigation and Home | Complete local slice. |
| Transaction create/list/detail/edit/archive/delete UI | Implemented in the active IMP-0006 vertical slice. |
| Local search/filter UI | Implemented: text, currency, direction, date range, category, payment source, and review state. |
| Review queue and resolution UI | Implemented: local queue, drill-in, explicit resolve/dismiss. |
| Evidence capture, local binary storage, attachment retrieval | Implemented: receipt/photo/PDF selection, private local bytes, metadata links, retrieval, deletion, export, and erase-all cleanup. |
| Currency/provenance/source-language UI | Partially implemented: provenance and reference conversions display; stored source-language values remain unmodified but are not yet presented. |
| Business date/exact instant/timezone | Partially implemented: schema v2 has `transaction_date`, `occurred_at_utc`, and `time_zone_id`; v1 migration normalizes legacy instants to UTC and uses the approved UTC calendar-date backfill. |
| Consent, privacy/data controls, export, deletion | Implemented local slice: reviewable export/erase scopes, explicit destructive confirmation, SQLite/evidence cleanup, and external-AI consent off by default. |
| Localized UI and preferences | Implemented P0 slice: complete English, Simplified Chinese, and Spanish key coverage; localized UI dates/decimals; persisted locale, base currency, canonical IANA timezone, AI consent, and first-use completion. |
| Privacy-safe logging validation | Implemented: application messages redact common financial values and user-entered fields; redaction is tested. |

## Governing-document alignment

The documentation refresh resolved the previously recorded conflicts.

- PRD-0003, PRD-0004, PRD-0008, UX-0005, and UX-0010 now consistently require an account-free, local-first Finance V1. Cross-device synchronization, device trust, pairing, and related conflict workflows are future/P2 work.
- PRD-0005 and UX-0010 now consistently define Home, Transactions, Review, Search, and Settings as the primary Finance V1 navigation. Assistant is optional and non-primary.

The current implementation already follows these decisions, so no account, synchronization, pairing, or primary Assistant navigation was added.

## Verification

Latest recorded validation completed on 2026-08-10:

| Area | Result |
| --- | --- |
| Finance domain | Format clean, analysis clean, 17 tests passed. |
| SQLite database | Format clean, analysis clean, 9 tests passed, including v1→v2 migration coverage. |
| Finance application services | Format clean, analysis clean, 11 tests passed. |
| Flutter app | Format clean, analysis clean, 10 tests passed. |
| Flutter web | Build succeeded. |

Total automated tests: 47 passed.

## Repository status

- Branch: `main`
- Current commit: `2512bb1 Harden transaction date migration`
- Working tree: clean at the time of review

## Recommended next step

Continue P0 hardening with the remaining scoped behavior:

1. Privacy, consent, local export/delete controls, and persisted preferences.
2. Locale-aware presentation, UI language resources, timezone preference, and date-only imports.
3. IMP-0009 binary evidence selection, local storage, and file lifecycle.

Do not introduce P1, P2, or Deferred functionality while completing this slice.
