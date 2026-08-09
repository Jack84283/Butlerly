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
| Transaction CRUD and detail UI | Not implemented | Application services exist; presentation flows are next. |
| Local list, detail, search, and filters UI | Not implemented | SQLite query support exists; presentation flows are next. |
| Review queue and resolution UI | Not implemented | ReviewIssue persistence exists; list/resolution application services and presentation are next. |
| Evidence capture, attachment storage, retrieval UI | Not implemented | Evidence metadata and links exist; local binary-file strategy and user flows are next. |
| Original currency, language, provenance, and normalization UI | Not implemented | Domain/persistence protect these values; presentation is absent. |
| Privacy, consent, export, and deletion UI | Not implemented | Required P0 product controls are absent. |
| Localization settings and translated UI resources | Not implemented | English-only localization infrastructure exists; user preference and translation resources are absent. |
| Privacy-safe logging | Partial | Logging is centralized, but it needs explicit redaction tests before finance content reaches UI workflows. |

## Document conflicts requiring product review

### C-001 — Account and synchronization priority

- PRD-0003, PRD-0004, and PRD-0008 require core Version 1 operation without an account; PRD-0008 marks cross-device synchronization P2 and backup/restore P1.
- UX-0005 and UX-0010 label authentication, trusted devices, Apple synchronization, and related recovery flows P0.

Implementation impact: account, device trust, synchronization, and Apple-specific flows are not being implemented while this conflict remains unresolved. The current app preserves local, account-free operation.

### C-002 — Primary navigation terminology and scope

- PRD-0005 defines the top-level destinations as Home, Transactions, Review, Search, and Settings.
- UX-0005 and UX-0010 define primary shells using Home, Inbox, Records, Assistant, and Settings.

Implementation impact: the navigation shell follows PRD-0005 because product requirements take precedence over UX specifications. The lower-priority terminology remains unresolved for any future assistant or inbox presentation.

## P0 order from this point

1. Main navigation and Home — in progress; this slice establishes it.
2. Transaction management UI — create, list, detail, edit, archive/delete.
3. Local search and filters UI.
4. Evidence capture/attachment and retrieval.
5. Review queue and explicit resolution workflows.
6. Privacy, consent, export/delete, localization, and P0 hardening.

No P1, P2, or Deferred capability is included unless it becomes technically necessary for one of these P0 slices.
