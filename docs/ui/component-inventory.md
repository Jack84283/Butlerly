# Butlerly component and token inventory

Status: audit-only inventory for [Issue #386](https://github.com/Jack84283/Butlerly/issues/386)

The inventory distinguishes existing canonical building blocks from repeated product compositions. A repeated widget is a consolidation candidate, not an automatic extraction: native platform behavior, semantics, responsive composition, and localization must remain intact.

## Foundation and theme inventory

| Layer | Current source | Current role | Audit note |
| --- | --- | --- | --- |
| Semantic colors | `apps/butlerly/lib/design_system/theme/butlerly_semantic_colors.dart` | Light/dark surface, text, border, brand, interaction, status, selection, review roles | Strong foundation; light baseline is unresolved against Issue #386. |
| Theme assembly | `apps/butlerly/lib/app/theme/app_theme.dart` | Material theme, button styles, dialog/sheet/navigation defaults | Button geometry is 32px here while `DESIGN.md` documents 48px preferred. |
| Spacing/radius/sizing | `apps/butlerly/lib/design_system/tokens/butlerly_tokens.dart` | 4–64 spacing, 6/12/18/full radii, 44/48 targets, breakpoints, nav sizes | Good centralization; feature-local dimensions remain. |
| Button geometry | `apps/butlerly/lib/design_system/tokens/butlerly_button.dart` | Shared visual height, widths, padding, icon target | Needs a clarified visual-vs-hit-area contract. |
| Typography | `apps/butlerly/lib/design_system/tokens/butlerly_typography.dart` | Editorial and platform-sans roles, financial tabular figures | Role set exists; verify all feature pages consume it consistently. |
| Responsive resolution | `apps/butlerly/lib/design_system/theme/butlerly_responsive_design_tokens.dart` | Width-driven mode and mode-specific Home/row geometry | Canonicalize all feature breakpoint decisions through this resolver. |
| Chart/category colors | `apps/butlerly/lib/design_system/tokens/butlerly_tokens.dart`, `apps/butlerly/lib/design_system/tokens/butlerly_category_colors.dart` | Stable categorical palette and category identity colors | Separate stable category identity from arbitrary series/insight presentation. |

## Existing shared components

| Component/family | Source | Likely canonical consumers | Contract to preserve |
| --- | --- | --- | --- |
| Page/header/content surface | `apps/butlerly/lib/design_system/components/butlerly_components.dart`, `apps/butlerly/lib/design_system/components/butlerly_content_surface.dart`, `apps/butlerly/lib/design_system/components/butlerly_responsive_body.dart` | Most feature pages | Width mode, readable max width, page gutter, safe areas, localized title/actions. |
| Cards and card headers | `apps/butlerly/lib/design_system/components/butlerly_components.dart` | Home, Analysis, Review, feature lists | 16px card radius, semantic card surface, compact/data-dense padding, no decorative outline. |
| Action groups/items | `apps/butlerly/lib/design_system/components/butlerly_action_group.dart` | Add, Tools, More/settings | One clear action, icon/title/subtitle semantics, responsive composition. |
| Button styles and action-group primitives | `apps/butlerly/lib/design_system/tokens/butlerly_button.dart`, `apps/butlerly/lib/design_system/components/butlerly_components.dart` (`ButlerlyButtonBar`), `apps/butlerly/lib/design_system/components/butlerly_action_group.dart` | Shared primary/secondary/tertiary/destructive actions | Full-pill geometry, localized wrapping, focus/disabled/error states, and the 44px minimum target required by the current design contract; runtime geometry needs verification. A unified `ButlerlyButton` widget is proposed, not currently present. |
| Selectors and form fields | `apps/butlerly/lib/design_system/components/butlerly_components.dart`, `apps/butlerly/lib/design_system/components/butlerly_transaction_controls.dart`, `apps/butlerly/lib/design_system/components/butlerly_compact_section_selector.dart`, `apps/butlerly/lib/design_system/components/butlerly_month_picker.dart` | Transaction editors, filters, period selection, master-data forms | `ButlerlySelectField` and domain selectors preserve IDs/values while localizing labels; verify text-field, dropdown, clear/create, focus, and error states consistently. |
| Modal sheet | `apps/butlerly/lib/design_system/components/butlerly_modal_sheet.dart` | Selectors, filters, editors, confirmations | Safe-area-aware surface, 18px shape, scrollable content, explicit cancel/escape. |
| Month/period selection | `apps/butlerly/lib/design_system/components/butlerly_month_picker.dart`, `apps/butlerly/lib/features/analysis/presentation/widgets/analysis_period_selector.dart` | Home, Analysis, transaction contexts | Existing month-selector behavior and financial-period semantics must remain stable. |
| Compact section navigation | `apps/butlerly/lib/design_system/components/butlerly_compact_section_selector.dart` | Master Data, Review | Section navigation is distinct from financial-period selection; preserve localized labels, selected state, and keyboard/touch semantics. |
| Dialogs and confirmations | No dedicated Butlerly dialog widget is present in the current source; Material dialog defaults are assembled in `apps/butlerly/lib/app/theme/app_theme.dart` | Destructive confirmations, legal/read-only notices, recovery decisions | Treat as an inventory gap, not an implementation claim; future work should define a shared dialog contract only after auditing existing confirmation behavior and escape/recovery paths. |
| Transaction rows/controls | `apps/butlerly/lib/design_system/components/butlerly_transaction_controls.dart`, `apps/butlerly/lib/design_system/components/butlerly_transaction_inner_card.dart`, `apps/butlerly/lib/design_system/components/butlerly_components.dart` | Home, Transactions, Search, Review | Shared amount/date/direction semantics and mode-resolved typography. |
| Category/payment-source identity | `apps/butlerly/lib/design_system/components/butlerly_category_icon.dart`, `apps/butlerly/lib/design_system/components/butlerly_payment_source_icon.dart` | Rows, editors, tables, analysis | Identity must not rely on color alone; accessible names remain localized. |
| Visualization primitives | `apps/butlerly/lib/design_system/components/butlerly_visualization_primitives.dart` | Home/Analysis/Insights | Textual summaries, stable colors, unavailable/insufficient-data states. |
| Desktop tables | `apps/butlerly/lib/design_system/components/butlerly_desktop_table_body.dart`, `apps/butlerly/lib/design_system/components/butlerly_desktop_transaction_table.dart` | Transactions, payment settlements, tools | Desktop composition with explicit minimum-width behavior; current narrow fallback is horizontal scroll, while a stacked/detail alternative is a proposed Phase 3 follow-up. |

## Duplication and consolidation candidates

| Candidate | Current implementations | Evidence | Priority | Recommendation |
| --- | --- | --- | --- | --- |
| Analysis breakdown card | `apps/butlerly/lib/features/analysis/presentation/widgets/analysis_category_breakdown.dart`, `apps/butlerly/lib/features/analysis/presentation/widgets/analysis_subcategory_breakdown.dart`, `apps/butlerly/lib/features/analysis/presentation/widgets/analysis_merchant_breakdown.dart` | Same card/header/empty state/44px metric row and desktop placeholder loop | P2 | One data-driven breakdown component with dimension and drill-through policy parameters. |
| Desktop action tile | `_DesktopAddActionCard` in `apps/butlerly/lib/features/foundation/presentation/add_page.dart`; `_ToolPanel` in `apps/butlerly/lib/features/tools/presentation/tools_page.dart` | Same icon/spacer/title/subtitle/arrow layout and raw 148px height | P2 | Shared `ButlerlyActionTile`; preserve Add and Tools route semantics via data. |
| Desktop surface/metric | `_DesktopPanel` and `_DesktopMetric` in `apps/butlerly/lib/features/desktop/presentation/desktop_home_page.dart`; `_DeviceDesktopSummaryMetric` in `apps/butlerly/lib/features/foundation/presentation/home_page.dart` | Desktop Home owns parallel panel/metric compositions for roles already represented by cards and summary metrics | P2 | Canonicalize surface, metric typography, colors, spacing, and number formatting while retaining desktop-specific layout. |
| Wide shell | Active `DesktopPrimaryShell` in `apps/butlerly/lib/app/shell/adaptive_shell.dart`; legacy `WidePrimaryShell` in `apps/butlerly/lib/app/shell/wide/wide_primary_shell.dart` | Two implementations expose different navigation structure and callback contracts | P3 | Keep one active shell and archive/consolidate the other after confirming routing ownership. |
| Month selector | `apps/butlerly/lib/design_system/components/butlerly_month_picker.dart`; device Home and desktop Home callers | Shared widget exists, but desktop caller passes a different current-month boundary and permits a future arrow | P1 | Keep one financial-period boundary contract and test both callers. |
| Card variants | `ButlerlyCardVariant.standard/dashboard` in `apps/butlerly/lib/design_system/components/butlerly_components.dart` | `dashboard` is accepted but currently renders the same shell as `standard` | P3 | Remove or document the API; avoid silently ignored visual semantics. |
| Local-only protection banner | `_DesktopMoreProtectionBanner` in `apps/butlerly/lib/features/foundation/presentation/settings_page.dart`; privacy banner in `apps/butlerly/lib/features/foundation/presentation/privacy_data_page.dart` | Same copy purpose, shield icon, green tone, repeated raw colors | P2 | Shared trust/status banner with semantic tone and localized copy. |
| Status/insight colors | `apps/butlerly/lib/features/desktop/presentation/desktop_home_page.dart`, `apps/butlerly/lib/app/shell/shared/primary_bottom_navigation.dart`, feature pages | Raw gold/green/red/blue values sit beside semantic status and chart palettes | P2 | Route through named semantic roles; maintain financial meaning independently from brand hue. |
| Tables and width policy | Payment settlements, rules, insights, desktop transactions | Local 920/1000px minimums and local column widths | P2 | Central table layout policy with explicit wide-only and stacked/detail variants. |
| Buttons and controls | A source scan finds multiple library files containing raw Material controls; shared primitives coexist with page-local `styleFrom`/padding/size | Reproducible scan: `rg -l 'styleFrom|FilledButton|OutlinedButton|TextButton|IconButton|DropdownButton|DropdownMenu|TextField|Checkbox|Radio|Switch' apps/butlerly/lib --glob '*.dart'` | P2 | Catalog allowed primitives and add an exception rule; migrate only after visual/semantic parity. |

## Token audit summary

### Current canonical values found in code

| Token group | Current code evidence | Audit interpretation |
| --- | --- | --- |
| Spacing | 4, 8, 12, 16, 24, 32, 48, 64 in `ButlerlySpacing` | Good base scale; retain compact aliases but avoid adding aliases without a semantic role. |
| Radius | 6, 12, 18, full, card16, sheet/dialog18 | Good role coverage; reconcile external design references before changing values. |
| Touch targets | minimum44, preferred48 | Correct direction; verify actual hit boxes for text controls, not only icon buttons. |
| Responsive modes | Current resolver: Compact `<801`, Medium `<1024`, Wide `>=1024`; tablet-landscape promotion | Good central resolver, but `<801` conflicts with the separate `<600` contract in `DESIGN.md`; resolve before migration. |
| Page/content widths | 12px gutter, readable 760px, state 520px | Good starting point; table-specific widths need a shared policy. |
| Buttons | visual height32, min width120, 12px horizontal/4px vertical padding | Must be reconciled with documented 48px preferred primary control. |
| Cards | 16px radius, 16px padding, 12px card gap, nested 8px/4px geometry | Strongest existing component contract; use as migration anchor. Clarify or remove the currently equivalent `dashboard` variant. |
| Light surfaces | code `#F6F7F8`/`#FFFFFF`; issue `#F2F3F9`/`#FDFDFD` | Decision required before implementation. |
| Dark surfaces | issue dark background `#030405`, card `#141516`; code has additional semantic layers | Preserve issue’s approved direction while documenting the role mapping. |

## Recommended catalog structure

Use a Flutter-native catalog rather than a new runtime dependency in the audit PR:

1. `design_system/foundations`: semantic theme, typography, spacing, shape, elevation, motion, icon and layout tokens.
2. `design_system/primitives`: surface, text role, divider, icon-label, badge, progress, empty/error/loading state.
3. `design_system/controls`: button variants, text/amount/date/search fields, select, toggle, checkbox/radio, month selector, menu/disclosure.
4. `design_system/patterns`: navigation items, action tiles, transaction rows, analysis breakdown, trust/status banner, offline/error/undo banners, table/detail pair.
5. `design_system/previews`: focused widget previews or a small internal preview route, with each component shown in light/dark, Compact/Medium/Wide, English/Chinese, and large-text fixtures.

The first implementation PR should not extract every `Card` or Material control. It should establish contracts for the high-reuse candidates above, migrate one reference screen, and add tests before expanding.
