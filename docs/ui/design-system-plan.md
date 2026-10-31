# Butlerly design-system proposal and migration plan

Status: proposal only; no production UI changes are part of Issue #386.

This proposal consolidates the existing Butlerly direction. It is not a redesign. Values that conflict with the Issue #386 baseline remain decision-gated.

## Guardrails

- Keep core operation local-first, offline-capable, and account-free.
- Keep the existing Home / Transactions / Add / Tools / More primary navigation and approved month-selector semantics: financial months use `transaction_date`, the persisted financial IANA timezone, and independently resolved primary/baseline windows; future months remain unavailable.
- Correct the desktop month-selector discrepancy through that resolved financial-period contract without changing the approved financial meaning or deriving a boundary from wall-clock `DateTime.now()`.
- Preserve compact, data-dense presentation and native platform conventions.
- Resolve the light/dark theme baseline before any implementation PR: Issue #386 says light `#F2F3F9`/`#FDFDFD` and dark `#030405`/`#141516`; current repository code/docs/tests are not fully aligned with those values.
- Do not change financial meaning, source evidence, status semantics, privacy copy, or recovery behavior while consolidating UI.
- Any component extraction must preserve localized text expansion, screen-reader semantics, keyboard/pointer paths, large text, reduced motion, safe areas, and offline/error recovery.

## Proposed token model

Use semantic tokens with a single implementation resolver. Feature code may request a role; it should not decide raw colors, breakpoints, or reusable dimensions.

### Foundations

| Group | Proposed contract | Current source/next step |
| --- | --- | --- |
| Color | `color.background`, `color.surface.card`, `color.surface.elevated`, `color.text.primary/secondary/tertiary`, `color.border`, `color.interactive`, `color.success/warning/error/info`, `color.review`, `color.category.*` | Keep `ButlerlySemanticColors`; resolve the Issue #386 conflict first and remove page-owned semantic-like colors. |
| Typography | `display`, `pageTitle`, `sectionTitle`, `body`, `bodyStrong`, `label`, `caption`, `amount`, `rowTitle`, `rowMetadata`, `navigationLabel` | Keep `ButlerlyTypography` and responsive role wrappers; verify feature adoption and platform fallback behavior. |
| Spacing | `micro=4`, `compact=8`, `small=12`, `standard=16`, `section=24`, `large=32`, `major=48`, `structural=64` | Keep `ButlerlySpacing`; add aliases only when they describe a semantic relationship. |
| Shape | `control=6`, `input=12`, `card=16`, `sheet/dialog=18`, `pill=full` | Keep `ButlerlyRadius`; document any component-specific exception. |
| Size | min target44, preferred primary target48, icon24, nav56, readable width760, state width520 | Keep `ButlerlySize`; define visual size separately from hit target. |
| Layout | width-driven Compact/Medium/Wide; tablet-landscape promotion is a documented exception | Keep `ButlerlyLayout`; keep the competing breakpoint prose decision-gated until the human choice is recorded, then align all consumers. |
| Elevation | base0, card2, overlay4, modal8 | Keep tonal layering; do not add decorative shadows during migration. |
| Motion | fast120, standard200, deliberate300; respect reduced-motion settings | Keep `ButlerlyMotion`; add state-transition tests where motion conveys progress or recovery. |

### Component contracts

Each reusable widget should document:

- semantic purpose and when not to use it;
- visual tokens and theme roles;
- minimum hit target and focus behavior;
- enabled, pressed, focused, disabled, loading, success, warning, error, empty, offline, and unavailable states where applicable;
- localized label and large-text behavior;
- Compact/Medium/Wide composition;
- keyboard, pointer, touch, and screen-reader semantics;
- a stable key/test contract and a golden/preview fixture.

## Responsive conventions

Use available width, not device name or orientation, as the primary presentation input. Continue using `MediaQuery.sizeOf` and `LayoutBuilder` where local constraints matter.

| Mode | Composition | Rules |
| --- | --- | --- |
| Compact (current resolver `<801`; alternate documented contract `<600`) | Single column, labeled bottom navigation, prominent Add/Capture, sheets for short decisions | Decision-gated breakpoint. Preserve one-handed priority, 12px page gutter, readable wrapping, and 44px targets until the approved threshold is resolved. |
| Medium (current resolver `801–1023`; alternate documented contract `600–1023`) | Compact shell with centered constrained content | Decision-gated breakpoint. Do not stretch compact content to the full viewport; keep bottom navigation unless the approved shell contract changes. |
| Wide `>=1024` | Persistent expandable/collapsible left navigation, reused page implementations | Resolve 168px vs 248px rail contract before implementation; avoid speculative multi-pane redesign. |
| Tablet landscape exception | Wide mode when the existing `tabletLandscape` predicate is true | Test by available width and shortest side; do not use device identity as a general breakpoint. |

The current resolver and the conflicting `<600` prose in `DESIGN.md` are both recorded here rather than silently resolved. Phase 0 must obtain the approved threshold before changing documentation, implementation, or boundary tests. Responsive tests should cover boundary widths just below/at/above each approved threshold, window resizing, rotation, safe areas, keyboard appearance, large text, and localized expansion. `Expanded`/`Flexible` and max-width constraints should be preferred over fixed page widths.

## Accessibility and localization requirements

The component gate should encode the UX-0005 state and accessibility requirements, plus the repository's checked-in accessibility contract, rather than treating accessibility as a later pass:

- every icon-only control has a localized accessible name and a visible focus/hover path where relevant;
- status is never conveyed by color alone; amounts retain sign/label/context;
- primary touch targets are at least 44×44 logical points, with 48 preferred for primary actions;
- text reflows at supported accessibility scales; fixed-height text containers and critical truncation are prohibited;
- focus order and focus return are deterministic after sheets, dialogs, async updates, errors, and recovery;
- errors announce what happened, what is safe, what to do next, and whether retry is safe;
- loading, empty, offline, degraded, permission, conflict, deleted, and revoked states have durable textual equivalents;
- UI-authored strings and semantics are localized; imported/source data preserves its original language/script;
- dates, times, amounts, currencies, and numbers follow locale; financial source amounts remain authoritative;
- reduced motion and keyboard/pointer alternatives are supported where the platform exposes them.

## Preview and regression strategy

Do not add a preview dependency in this audit PR. In the first implementation PR, choose one of:

1. an internal Flutter preview route under `design_system/previews`, or
2. an approved Widgetbook-style package after dependency review.

Every canonical component should have:

- widget tests for semantics, interaction, state transitions, and target size;
- golden fixtures for Compact/Medium/Wide where composition changes;
- light and dark themes;
- English, Spanish, and Chinese fixtures where text length or script matters;
- normal and large text scales;
- loading, empty, offline, unavailable, error, and recovery variants where the pattern supports them.

Existing PNG assets are useful baseline anchors, but they are not currently exercised by a `matchesGoldenFile` test:

- `apps/butlerly/test/app/goldens/home_dark_390x844.png`
- `apps/butlerly/test/features/analysis/goldens/analysis_empty_390x844.png`

Future golden tests must be reviewed alongside semantic tests; a matching image is not evidence that focus order, localization, or recovery behavior is correct.

## Phased migration roadmap

### Phase 0 — baseline decision and contract repair

Follow-up issue: resolve the Issue #386 `needs-decision` comment.

Implementation PR:

- reconcile the active light palette;
- reconcile the active dark palette and its documented surface roles;
- reconcile button visual/hit-area contract;
- reconcile wide rail width;
- resolve the conflicting `<801` versus `<600` breakpoint authority before changing the statement;
- reconcile the financial-period boundary, persisted timezone, and independently resolved windows used by both Home compositions;
- update semantic palette, `DESIGN.md`, contract tests, goldens, and screenshots together;
- add boundary tests for all responsive thresholds.

Exit criteria: one source of truth for both appearance modes and financial periods, no conflicting contract prose, and current-head tests prove the chosen values.

### Phase 1 — high-reuse trust and data patterns

Implementation PRs:

- `LocalOnlyProtectionBanner`;
- `AnalysisBreakdownCard`;
- shared offline/error/undo/unavailable state surfaces;
- semantic status and insight roles.

Exit criteria: Settings, Privacy/Data, Analysis, Home, Review, and Insights use the same patterns in both themes and selected locales, with state and semantics tests.

### Phase 2 — action and navigation patterns

Implementation PRs:

- `ButlerlyActionTile` for Add/Tools and comparable More destinations;
- button variants and field/select contracts;
- navigation item/rail/bottom-nav contract;
- shared month/period selector contract that uses the resolved financial boundary and persisted timezone.

Exit criteria: primary shell and creation/tool destinations have no equivalent page-local visual implementations without a documented exception.

### Phase 3 — table/detail and capture/review patterns

Implementation PRs:

- table width and stacked/detail policy;
- transaction row/detail and filter controls;
- capture/import progress, source preview, duplicate/conflict, and recovery patterns.

Exit criteria: narrow, medium, and wide compositions share semantics and state taxonomy; large text has a non-horizontal-scroll alternative for normal reading.

### Phase 4 — screen migration and governance

Migrate one screen family at a time: Home → Transactions/Search/Review → Add/Capture/Import → Tools/Analysis/Insights → More/Privacy/Legal.

Each PR must include a source-to-test traceability table, before/after screenshots for the changed surface, widget/golden/semantic tests, and an explicit exception list.

## Rules that prevent future drift

1. New reusable visual values require a token or a documented algorithmic exception.
2. New components must be added to the catalog with purpose, states, semantics, responsive variants, and test fixtures.
3. A feature page may bypass a canonical component only when the interaction contract differs; the reason belongs beside the code and in the inventory.
4. Every new screen is checked at 320×568, 390×844, 430×932, a medium width, a wide width, light/dark, Chinese, and large text when applicable.
5. The review checklist must include UX-0005 state coverage, the checked-in accessibility contract, localization expansion, offline/recovery, and visual evidence.
6. Do not use `INSERT OR IGNORE`-style thinking for design authority: changing an existing token requires updating downstream consumers, tests, screenshots, and the current documentation in one reviewed change.
7. Avoid a lint that bans all raw colors or all fixed dimensions. First classify intentional chart, contrast, platform, and algorithmic values; enforce semantic ownership for reusable values.
