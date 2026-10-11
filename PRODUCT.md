# Product

<!-- impeccable:product-schema 1 -->

<!-- Current product guide. Keep aligned with AGENTS.md, DESIGN.md and shipping code. -->
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
- `DESIGN.md` is the current visual and interaction specification; implementation status is verified against Flutter code and tests.

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
- Current Butlerly branding, `DESIGN.md`, and implemented accessibility standards guide new work; superseded visual mockups are not authoritative.
- New work must preserve established product terminology, legal content, accessibility commitments, and the approved local-first/account-free product identity.

## Evidence on Hand

- `README.md` documents the local-first, privacy-first product purpose, Version 1 scope, repository boundaries, and non-requirements.
- `AGENTS.md` defines the Butlerly Company Constitution, product constraints, architecture boundaries, persistence requirements, and review rules.
- Historical visual QA results remain accessible through Git history; current UI behavior and validation should be established from the implementation and tests.
- `DESIGN.md` is the maintained design reference; current widgets and shared Flutter design tokens are implementation evidence.
- UI verification relies on current widget tests and fresh captures, not retained obsolete screenshots.
- `apps/butlerly/assets/branding/` and `apps/butlerly/assets/legal/` contain approved branding and legal materials.
- The Flutter application and framework-independent domain, application, and database packages provide the current implementation evidence.

## Product Principles

1. Keep core financial work local, reliable, and usable offline.
2. Make financial records understandable, traceable, and safe to correct.
3. Preserve user ownership, privacy, and control over personal data.
4. Use AI only as an optional, explainable assistant; never make it a prerequisite for core workflows.
5. Treat accessibility, localization, recovery, and compatibility as part of product quality.

## Accessibility & Inclusion

Butlerly follows the accessibility expectations maintained in `DESIGN.md` and enforced by relevant UI tests. Interfaces must remain usable across supported device sizes, localization variants, and appearance modes; must preserve readable wrapping and hit targets; and must not communicate financial meaning through color alone. Accessibility regressions, localization breakage, and small-screen overflow are product defects.


## Current finance implementation invariants

- Transaction creation, editing, archive/restore, search, and review run locally through application services and SQLite repositories; presentation must not query SQLite directly.
- Payment sources are local financial instruments (account, card, cash, wallet, other), not cloud identities; their assignment and filtering must preserve stored references.
- Receipts and other evidence are stored in an app-owned private directory using opaque filenames, with links and metadata in SQLite. Archival retains linked evidence; permanent deletion and erase-all remove both linked metadata and files. Exports include supporting evidence with structured finance data.
- Extraction and attachment are distinct: attaching a file never means extraction succeeded. Original transaction values, provenance, and user corrections remain authoritative.
- Financial and data-loss semantics must be verified against current implementation and tests, rather than reconstructed from retired milestone reports.

### Finance V1 release-readiness invariants

- Historical Analysis, Insights, calendars, reports, and exports use the canonical economic history of Active and Archived transactions. Permanently deleted records, receipt-side records already linked to a payment, and noncanonical duplicate members are excluded; Review, Uncategorized, reconciliation candidates, and duplicate candidate generation remain Active-only.
- Duplicate decisions are durable and explainable: Keep Both counts every member, Consolidated counts the selected representative, and unresolved or stale decisions count one deterministic representative while exposing a data-quality issue. The decision is applied consistently across analysis surfaces and survives reload and restore because the source decision remains in SQLite.
- Recurring recognition is local and deterministic. A pattern is derived from at least three canonical historical records using merchant/counterparty, cadence, amount, currency, direction, and context evidence; same-day records with no positive interval are not recurring evidence. Patterns and optional next occurrences are separate from actual transaction totals, start as reviewable detections, and support explicit confirmation, rejection, and correction.
- Periodic reports reuse the Analysis/Insights rule engine for selected and comparison windows, income, expenses, net, categories, subcategories, merchants, changes, drill-through, and quality limitations. Derived recurring predictions remain a separate section.
- Statement acquisition remains exception-first: evidence and provenance stay attached, rows are inspectable and correctable, valid rows can be confirmed as a batch, low-confidence rows become Review exceptions, duplicate checks precede persistence, and resume is idempotent.
- Analysis drill-through uses evidence transaction IDs as the authoritative filter, including occurrence-only records. Valid empty periods remain explicit zero/no-spending states; grouped metrics with insufficient currency normalization remain visibly unavailable rather than presenting a zero amount that could be mistaken for a real total.
- Calendar day summaries use the canonical calendar expense metric, including its currency-normalization availability; they never reconstruct totals by summing raw mixed-currency or income rows in the presentation layer.
- Malformed persisted duplicate decisions are treated as data-quality exceptions: historical analysis uses one deterministic representative and exposes the repair-needed state instead of silently treating the damaged decision as healthy.
