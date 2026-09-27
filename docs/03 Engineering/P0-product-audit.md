# Butlerly Current Implementation Alignment

Status: Active current-state audit

## Purpose

This document records the current Finance V1 implementation shape that active documentation must match. It intentionally avoids stale commit IDs, schema-version snapshots, historical test counts, and superseded navigation models.

## Current product model

Butlerly Finance V1 is local-first and account-free for core operation. The application remains usable without a network connection, cloud synchronization, or AI provider.

## Current primary navigation

The implemented primary navigation is:

1. Home
2. Transactions
3. Add
4. Tools
5. More

Review and Search are secondary workflows and are not primary phone-navigation destinations.

## Current destination ownership

### Home
Financial overview, recent activity, and entry context.

### Transactions
Canonical transaction list and transaction-focused workflows.

### Add
Primary acquisition destination for:
- manual transaction entry;
- receipt capture;
- statement capture;
- local-file import;
- Payment Sources.

### Tools
Primary utility, review, analysis, and management destination for:
- Review;
- Analysis;
- Insights;
- Payment Settlements;
- Master Data;
- Rules.

### More
Primary preferences/settings destination for:
- Appearance;
- Language;
- Base Currency;
- Timezone;
- Privacy & Data;
- optional AI controls;
- Legal & Licenses.

Master Data and Rules do not belong under More.

## Current implementation capabilities

The repository currently contains production paths for:

- local-first startup and persisted preferences;
- transaction create/list/detail/edit/archive/permanent-delete;
- persistent merchant/category/tag master data;
- payment sources and transaction assignment;
- user rule management;
- local search and filtering;
- review and duplicate-review workflows;
- analysis and insights;
- payment settlements;
- receipt/evidence capture and local storage;
- statement capture and intake;
- CSV/local import;
- reconciliation;
- local export;
- backup and restore;
- erase-all data controls;
- localization for English, Simplified Chinese, and Spanish;
- privacy-safe logging;
- responsive smartphone/tablet/desktop presentation;
- automated domain, application, database, widget, Android smoke, iOS build, and iOS integration validation, including production-path persistence coverage for Master Data, Rules, Payment Settlements, and statement confirmation.

## Architecture alignment

The intended dependency direction remains:

```text
Flutter presentation -> application services -> finance domain
                                      ^
                                      |
                         SQLite/local adapters
```

The domain layer remains independent of Flutter and SQLite. Application services depend on domain abstractions. Persistence and local-file implementations are composed at the application boundary.

## Documentation alignment rules

Active documentation must describe the current implementation directly.

Do not retain:
- superseded primary-navigation alternatives;
- stale schema versions;
- old commit IDs as current baselines;
- obsolete test-count snapshots;
- old implementation priorities that have already been completed;
- duplicate IMP identifiers;
- “earlier text is overridden by this later section” patterns.

When implementation changes are approved, update the relevant active document and remove the obsolete statement.

## Current known engineering debt

The following remain engineering-quality concerns rather than product-scope gaps:

- keep large screens/controllers maintainable when they next change;
- continue reducing broad service-locator/facade coupling where useful;
- keep timestamp/clock injection deterministic in code paths that still use direct current-time access;
- maintain and extend production-path integration coverage as critical workflows evolve;
- continue native-platform verification for camera/OCR, file pickers, share sheets, backup/restore, and platform builds.

These items do not authorize broad refactoring or UI redesign.

## Acceptance

Documentation is aligned when an engineer or Codex can read the active Product, UX, Engineering, and implementation guidance without encountering a second obsolete definition of current Butlerly behavior.
