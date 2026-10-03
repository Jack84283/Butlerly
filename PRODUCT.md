# Product

<!-- impeccable:product-schema 1 -->

<!-- Product context below is derived from the current repository sources because no separate product interview answers were provided. Verify it if product strategy or audience details change. -->

## Platform

adaptive

## Users

People managing their personal finances who need a trustworthy, private, local-first way to record, review, search, import, and organize financial information without creating an account or depending on a cloud service.

## Product Purpose

Butlerly is a local-first, privacy-first personal operations assistant. Version 1 provides a trustworthy personal-finance experience with core data and workflows kept on the user's device. SQLite is the device system of record. Success means users can understand and act on their financial records reliably, including when offline, while retaining control over their data.

## Positioning

Butlerly combines a personal-finance workflow with an on-device, account-free operating model: core financial data and actions remain local, while AI is optional, assistive, and replaceable through provider abstractions. The product prioritizes user control and explainable financial workflows over cloud dependence or opaque automation.

## Operating Context

- The product is a smartphone-first, cross-platform Flutter application used across supported device environments.
- Core workflows include Home, Transactions, transaction entry and editing, Search, Review, Settings, payment sources, master data, import and export, receipt capture, statement capture, and recovery flows.
- Users may enter records manually or work with imported statements and captured receipts. Financial records are persisted locally and must survive reload, upgrade, and recovery paths.
- The product supports English, Spanish, and Simplified Chinese UI localization; user-entered and source/master data are not translated as application copy.
- The repository's approved design-system, UX, screen, and accessibility documents are the visual and interaction references for implemented surfaces.

## Capabilities and Constraints

- Core operation must be local-first, offline-capable, and account-free.
- SQLite on the user's device is the Version 1 system of record.
- The application must not require an account, network service, cloud database, or AI provider for core operation.
- AI is optional and assistive, and must remain behind provider abstractions.
- Financial meaning must remain explicit and trustworthy: transaction dates, financial periods, currencies, normalization, canonical transaction scope, signs, and persisted compatibility must not be silently changed.
- Domain logic remains independent of Flutter, SQLite, provider SDKs, and operating-system APIs.
- User control, privacy, recovery, migration compatibility, and non-destructive handling of derived findings are product constraints, not optional implementation details.
- Version 1 is limited to the approved personal-finance scope. Future Life OS modules and speculative platform systems are out of scope unless separately approved.

## Brand Commitments

- The product name is Butlerly.
- Existing Butlerly branding, the Butler Design System v1.0, approved UX specifications, approved screen references, and accessibility standards are authoritative assets and references.
- New work must preserve established product terminology, legal content, accessibility commitments, and the approved local-first/account-free product identity.

## Evidence on Hand

- `README.md` documents the local-first, privacy-first product purpose, Version 1 scope, repository boundaries, and non-requirements.
- `AGENTS.md` defines the Butlerly Company Constitution, product constraints, architecture boundaries, persistence requirements, and review rules.
- `design-qa.md` records current visual evidence, implemented flows, localization, accessibility-related checks, and remaining visual QA work.
- `docs/04 Design/` contains the Butler Design System, UX specifications, screen references, and accessibility standard.
- `docs/design-evidence/` contains implementation screenshots and comparison evidence.
- `apps/butlerly/assets/branding/` and `apps/butlerly/assets/legal/` contain approved branding and legal materials.
- The Flutter application and framework-independent domain, application, and database packages provide the current implementation evidence.

## Product Principles

1. Keep core financial work local, reliable, and usable offline.
2. Make financial records understandable, traceable, and safe to correct.
3. Preserve user ownership, privacy, and control over personal data.
4. Use AI only as an optional, explainable assistant; never make it a prerequisite for core workflows.
5. Treat accessibility, localization, recovery, and compatibility as part of product quality.

## Accessibility & Inclusion

Butlerly follows the approved accessibility standard in `docs/04 Design/UI Design/UX-0009 — Butlerly Accessibility Standard v1.0.pdf` and the related design-system guidance. Interfaces must remain usable across supported device sizes, localization variants, and appearance modes; must preserve readable wrapping and hit targets; and must not communicate financial meaning through color alone. Accessibility regressions, localization breakage, and small-screen overflow are product defects.
