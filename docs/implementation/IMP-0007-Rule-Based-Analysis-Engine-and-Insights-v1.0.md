# IMP-0007 — Rule-Based Analysis Engine & Insights

**Version:** 1.0  
**Source status:** Ready for implementation planning  
**Snapshot status:** Fixed repository task input; not Codex-ready until governing Draft analysis documents are approved  
**Source revision:** `AIroW34VvHRA9AywDFcaIUvG_cy8_WnUDT_bY7drkwneAh07xUCW4AJqXsqglJ-yOvZ4Sc3P-whbMAe_4LZcv9rhGh8FPDxfrHS-fkmC6w4`  
**Authority:** PRD-0003, PRD-0004, ANL-0001 through ANL-0004, ARC-0405

## 1. Objective

Implement Butlerly’s local, deterministic, declarative financial Analysis capability. It calculates reproducible metrics and findings from canonical events, isolates failures, exposes evidence and data quality, and remains independent of UI and optional AI.

## 2. Scope

V1 includes dataset builder, declarative schema and loader, validation, generic metric and comparison primitives, result models, orchestration, justified caching or finding persistence, invalidation, drill-down queries, and initial Analysis surfaces.

## 3. Out of Scope

V1 excludes investment or tax advice, credit scoring, predictive forecasting, prescriptive optimization, cloud-required analysis, general-purpose scripting, and authoritative AI conclusions. Advanced recurrence and anomaly rules remain disabled until deterministic parameters and fixtures exist.

## 4. Domain Types

Implement `AnalysisRuleDefinition`, `RuleIdentity`, `RuleVersion`, `RuleDefinitionHash`, `AnalysisContext`, `AnalysisPeriod`, `AnalysisFilter`, `CurrencyBasis`, `DatasetMode`, `AnalysisMetric`, `AnalysisFinding`, `DataQualityIssue`, `EvidenceReference`, `FindingLifecycle`, and `RuleExecutionResult`. These types do not depend on widgets, SQL rows, localized labels, or AI formats.

## 5. Dataset Builder

Construct input from canonical economic transactions under ANL-0003. Resolve reconciliation, duplicates, pending-to-posted replacement, transfers, refunds, splits, currency, timezone, and uncertainty before evaluation. Test dataset construction independently.

## 6. Rule Loading

Built-in rules are versioned data definitions. Validate schema, identity, primitives, semantic compatibility, dependencies, thresholds, and output. Invalid definitions are disabled with diagnostics without blocking valid rules.

## 7. Generic Primitives

Provide generic filters; sum, count, average, median, minimum, maximum, and distinct count; grouping; calendar and rolling periods; previous and rolling baselines; absolute and percentage change; comparisons; logical combinators; thresholds; severity mapping; and structured output. No rule-ID-specific branches.

## 8. Dependency Execution

Build a deterministic dependency graph. Metrics execute before dependent insights. Missing, invalid, cyclic, or failed dependencies create isolated unresolved outcomes. Order is stable and tested.

## 9. Initial Enabled Rules

Enable ANL-R001, R002, R003, R004, R010, R014, R020, R090, R091, and R092 first. Enable R021 and other insights after materiality thresholds are supplied and tested. Keep R040 through R042 disabled until recurrence tolerances and minimum observations are authoritative.

## 10. Persistence

Metrics are recomputed or cached and remain derived. Persist findings only for lifecycle history, notification, or reproducibility. Persist rule ID, version, definition hash, context, values, evidence, limitations, generation time, and lifecycle. Deleting derived results never deletes financial records.

## 11. Invalidation

Invalidate after changes to economic data, allocations, reconciliation, aliases, categories, payment sources, rates, preferences, rules, or configuration. Scope-aware invalidation is preferred; safe full invalidation is acceptable initially. Stale results are never silently current.

## 12. Application Interfaces

Provide calculate overview, spending breakdown, trend, list findings, inspect metric, inspect finding, acknowledge, dismiss, and refresh use cases. Return domain results or typed failures, never presentation strings.

## 13. Repository Boundaries

Repositories expose authoritative transaction data, rules, optional caches, findings, and evidence through domain-facing contracts. SQL optimization is allowed only with semantic equivalence and parity tests.

## 14. UI Integration

Overview, Spending, Trends, and Insights consume use cases. Widgets format results but never calculate totals, changes, thresholds, severity, or eligibility. Drill-down carries `AnalysisContext` or a stable result reference.

## 15. AI Boundary

Optional AI receives only structured authoritative results and permitted minimal context. It produces explanation only and cannot alter values, severity, rule state, lifecycle, or records.

## 16. Error Handling

Invalid definitions, rule failures, missing FX, insufficient history, unsupported configuration, and unavailable data are distinct typed outcomes. A failed rule cannot suppress unrelated results.

## 17. Performance

Keep overview responsive for a realistic local dataset. Optimize with indexes, bounded queries, invalidation, or caching only after correctness. Optimizations preserve deterministic equivalence and drill-down reconciliation.

## 18. Testing

Test every primitive and enabled rule; deterministic rule fixtures; ANL-0003 edge cases; dependencies, cycles, invalid schemas, and isolation; SQL parity; persistence and invalidation; timezone and FX behavior; and UI consumption without widget calculations.

## 19. Delivery Sequence

1. Domain types, schema, fixtures, and dataset builder.
2. Validation, primitives, dependency execution, and structured results.
3. Initial rules and drill-down.
4. Persistence and invalidation.
5. Overview, Spending, Trends, and data-quality states.
6. Additional insights after definition acceptance.

## 20. Definition of Done

Identical inputs produce identical structured results; reconciled sources count once; transfers, refunds, splits, pending records, FX gaps, and partial periods follow ANL-0003; rules contain no UI or AI logic; the engine contains no rule-specific behavior; failures isolate; results are explainable and drillable; stale results are not current; and tests pass offline.

## 21. YAML Asset Layout

Built-in rule definitions SHALL be stored as version-controlled Flutter assets under `assets/analysis_rules`. The recommended hierarchy separates catalog metadata, metrics, insights, and data-quality definitions. Each file contains one rule definition unless ANL-0005 explicitly permits a catalog wrapper.

YAML is an authoring and distribution format only. Runtime evaluation SHALL use validated immutable Dart `AnalysisRuleDefinition` objects. The implementation SHALL use a restricted safe parser, reject duplicate keys and unsupported YAML features, validate against ANL-0005, perform semantic and dependency validation, canonicalize the definition, calculate a stable definition hash, and install the result before activation.

## 22. SQLite Rule Registry

Implement `analysis_rule_definitions` with a composite primary key of `rule_id` and `rule_version`. Required fields include `schema_version`, `source_type`, enabled eligibility, `definition_yaml` or an equivalent lossless installed representation, `canonical_definition`, `definition_hash`, `validation_status`, `validation_error`, `installed_at`, and `retired_at`.

Implement `analysis_rule_activations` keyed by `rule_id` with `active_rule_version`, `enabled`, and `updated_at`. Store user configuration separately from immutable definitions with an explicit configuration schema/version. Built-in automatic-rule activation cannot be disabled through ordinary user settings.

Seeding and upgrades are idempotent. New versions are installed alongside historical versions. Findings retain the rule ID, version, and definition hash that produced them.

## 23. Initial Eleven Rules

The initial rollout enables ANL-R001, R002, R003, R004, R010, R014, R016, R020, R090, R091, and R092.

R001, R002, R003, R004, R010, R014, and R016 are automatic core metrics. R090, R091, and R092 are automatic data-quality rules. R020 is enabled by default and may be hidden or disabled as an optional insight presentation. Notification preference is independent of rule execution.

The engine SHALL contain no switch, if statement, class registry, SQL branch, or widget branch keyed to these rule IDs. Each rule executes through generic primitives and declarative dependencies.

## 24. Dashboard and Calendar Delivery

Add Analysis Dashboard use cases and presentation models for summary metrics, spending trend, category spending, findings, and data-quality limitations. Charts consume structured rule results and expose transaction drill-down and accessible alternatives.

Add a month-calendar use case backed by ANL-R016. It returns daily activity for the selected financial month, including financial date, transaction count, expense total, income total, currency basis, data quality, and supporting transaction references.

The calendar defaults to month view, marks dates with eligible transactions, distinguishes today and selected date, supports month navigation, and preserves context. Selecting a date queries the standard transaction list using `transaction_date` and the persisted financial timezone. Selecting a transaction opens its normal detail/evidence flow. A date with no transactions returns an empty result, not an error.

V1 uses a simple activity marker and optional readable transaction count. Spending heat-map behavior is deferred. Calendar accessibility cannot rely on color alone.

## 25. Rule Controls and Execution Triggers

Settings distinguish Automatic Calculations, Optional Insights, and Notifications. Automatic core and data-quality rules are displayed as always on. Optional insights may be enabled or disabled. Users do not edit YAML in V1.

Rule evaluation is triggered by required dashboard, calendar, insight, or drill-down queries and by invalidation after relevant data or configuration changes. It is not implemented as an uncontrolled continuous background loop.

Automatic evaluation remains silent in the interaction sense: it does not interrupt the user, request confirmation, require network access, or modify authoritative financial data. Material data-quality limitations appear with the affected result. Notifications are off by default unless a separate accepted requirement states otherwise.

## 26. Extended Acceptance

Implementation is not complete until bundled YAML rules seed idempotently into SQLite; invalid definitions fail in isolation; activation and configuration are separate from immutable definitions; all eleven initial rules execute without rule-specific logic; dashboard values reconcile to drill-down; calendar highlights reconcile to ANL-R016; selecting a date returns the correct timezone-resolved transaction list; accessibility and empty states are covered; and adding a rule using existing primitives requires no application-logic or schema change.

---

## Snapshot governance note

This file is a fixed implementation snapshot copied from the editable Google Drive source. Under `AGENTS.md`, Codex implementation must not begin while governing inputs remain Draft/Proposed/Superseded/Pending Decision. At snapshot time, ANL-0001 and ANL-0002 are still marked **Draft for V1 implementation**, so an implementation issue referencing this snapshot must remain blocked until those statuses are formally accepted or the governing source set is otherwise resolved.