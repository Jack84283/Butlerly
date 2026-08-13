# Butlerly P0 Product Audit

Status: Active implementation audit

## Sources reviewed

- BL-0001 — Butlerly Company Constitution
- BL-0007 — User Bill of Rights
- MVP-0001 — Butlerly MVP Compass
- PRD-0001 through PRD-0008
- ARC-0202 — Presentation Architecture
- ARC-0203 — Application Layer
- ENG-0101, ENG-0104 through ENG-0107
- DEV-0001 — Butlerly Codex Implementation Specification
- UX-0003, UX-0005, and UX-0010
- Repository README and AGENTS.md

## Current implementation assessment

| P0 capability | Status | Evidence / gap |
| --- | --- | --- |
| Local workspace without account, network, or AI | Implemented | Local SQLite startup, account-free first use, device-safe preference defaults, and persisted preferences work without network or AI. |
| Finance domain and local persistence | Implemented | Domain invariants, SQLite schema v6, repositories, migrations, date-only transactions, and persisted locale/base-currency/IANA-timezone/AI-consent preferences exist. |
| Application service boundary | Implemented | Commands, queries, DTOs, result mapping, and repository-only application services exist. |
| Primary navigation and Home | Implemented in this slice | Product-authoritative Home, Transactions, Review, Search, and Settings destinations now have responsive shell support and truthful empty states. |
| Transaction CRUD and detail UI | Implemented active slice | Local list, create, detail, edit, archive, and permanent-delete UI is wired through application services. |
| Local list, detail, search, and filters UI | Implemented active slice | Local text, currency, direction, business-date range, category, payment-source, and review-state filters are available. |
| Review queue and resolution UI | Implemented active slice | Local active-issue queue, transaction drill-in, and explicit resolve/dismiss actions are wired through application services. |
| Evidence capture, attachment storage, retrieval UI | Implemented local slice | Receipt/photo/PDF selection, private local file storage, metadata linking, retrieval, deletion, transaction-delete cleanup, export, and erase-all cleanup are implemented. |
| Original currency, language, provenance, and normalization UI | Partially implemented | Transaction detail shows local provenance history and read-only reference conversions; original money remains canonical. Source-language values are preserved but not yet presented. |
| Business date, exact instant, and timezone model | Partially implemented | Schema v2 stores `transaction_date`, `occurred_at_utc`, and nullable `time_zone_id`; v1 legacy instants migrate to normalized UTC plus their approved UTC calendar date. Date-only imports and timezone preferences remain. |
| Privacy, consent, export, and deletion UI | Implemented local slice | Local JSON/evidence export and confirmed erase-all cover SQLite user data and evidence files. External-AI consent is explicit, off by default, and persisted locally. |
| Localization settings and translated UI resources | Implemented P0 slice | English, Simplified Chinese, and Spanish keys have complete coverage; locale switching affects UI labels, dates, and decimal formatting without modifying source content. Locale, base currency, and IANA timezone persist locally. |
| Privacy-safe logging | Implemented | Common financial values and user-entered fields are redacted before logging; redaction is tested. |

## Confirmed scope alignment

The documentation refresh resolves the previously recorded scope conflicts.

- PRD-0003, PRD-0004, PRD-0008, UX-0005, and UX-0010 now agree that core Finance V1 is account-free and local-first. Cross-device synchronization, device trust, pairing, and related conflict workflows are future/P2 work and must not be required for P0.
- PRD-0005 and UX-0010 now agree on the primary Finance V1 navigation: Home, Transactions, Review, Search, and Settings. Assistant remains optional and non-primary.

Implementation impact: the current navigation shell already conforms. No account, synchronization, pairing, or Assistant-primary-navigation implementation is authorized for the active P0 scope.

## P0 order from this point

1. IMP-0005 — Main Navigation and Home — complete local slice.
2. IMP-0006 — Transaction Management — completed local slice, including organization, retrieval, review, and migration hardening.
3. IMP-0007 — Account Management — active local payment-source slice.
4. Privacy, consent, export/delete, localization/preferences, date-only CSV import support, and P0 hardening — implemented local slice.
5. IMP-0009 — binary evidence selection, local file lifecycle, and storage — implemented local slice.

No P1, P2, or Deferred capability is included unless it becomes technically necessary for one of these P0 slices.
