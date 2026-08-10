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
| Local workspace without account, network, or AI | Partially implemented | Local SQLite startup and no account requirement are implemented. Preferences and a user-facing first-use flow are not. |
| Finance domain and local persistence | Implemented | Domain invariants, SQLite schema, repositories, migrations, and tests exist. |
| Application service boundary | Implemented | Commands, queries, DTOs, result mapping, and repository-only application services exist. |
| Primary navigation and Home | Implemented in this slice | Product-authoritative Home, Transactions, Review, Search, and Settings destinations now have responsive shell support and truthful empty states. |
| Transaction CRUD and detail UI | Implemented active slice | Local list, create, detail, edit, archive, and permanent-delete UI is wired through application services. |
| Local list, detail, search, and filters UI | Partially implemented | Transaction list/detail and local text, currency, direction, date-range, category, and review-state search filters are available. Payment-source filtering correctly awaits IMP-0007. |
| Review queue and resolution UI | Implemented active slice | Local active-issue queue, transaction drill-in, and explicit resolve/dismiss actions are wired through application services. |
| Evidence capture, attachment storage, retrieval UI | Deferred to IMP-0009 | Evidence metadata retrieval is available. Binary evidence selection, persistence, file lifecycle, and local storage are intentionally owned by IMP-0009. |
| Original currency, language, provenance, and normalization UI | Partially implemented | Transaction detail shows local provenance history and read-only reference conversions; original money remains canonical. Original-language presentation remains. |
| Privacy, consent, export, and deletion UI | Not implemented | Required P0 product controls are absent. |
| Localization settings and translated UI resources | Not implemented | English-only localization infrastructure exists; user preference and translation resources are absent. |
| Privacy-safe logging | Implemented | Common financial values and user-entered fields are redacted before logging; redaction is tested. |

## Confirmed scope alignment

The documentation refresh resolves the previously recorded scope conflicts.

- PRD-0003, PRD-0004, PRD-0008, UX-0005, and UX-0010 now agree that core Finance V1 is account-free and local-first. Cross-device synchronization, device trust, pairing, and related conflict workflows are future/P2 work and must not be required for P0.
- PRD-0005 and UX-0010 now agree on the primary Finance V1 navigation: Home, Transactions, Review, Search, and Settings. Assistant remains optional and non-primary.

Implementation impact: the current navigation shell already conforms. No account, synchronization, pairing, or Assistant-primary-navigation implementation is authorized for the active P0 scope.

## P0 order from this point

1. IMP-0005 — Main Navigation and Home — complete local slice.
2. IMP-0006 — Transaction Management — active; the offline lifecycle is implemented, with organization and retrieval presentation still pending.
3. Local search and filters UI.
4. Evidence capture/attachment and retrieval.
5. Review queue and explicit resolution workflows.
6. Privacy, consent, export/delete, localization, and P0 hardening.

No P1, P2, or Deferred capability is included unless it becomes technically necessary for one of these P0 slices.
