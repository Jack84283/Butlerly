---
name: Butlerly
description: Quiet-premium, local-first personal finance for clear and confident daily decisions.
colors:
  brand-burgundy: "#7A1E3A"
  brand-deep: "#541127"
  interactive-rose: "#C76F8B"
  paper-light: "#F6F7F8"
  canvas-dark: "#030405"
  surface-light: "#FFFFFF"
  surface-dark: "#1F2123"
  dashboard-dark: "#141516"
  elevated-dark: "#292B2D"
  sheet-dark: "#1B1D1F"
  subtle-light: "#F2F3F5"
  ink-light: "#14171D"
  ink-dark: "#FFFFFF"
  border-light: "#D8DDE6"
  border-dark: "#282C30"
  secondary-light: "#4B5563"
  secondary-dark: "#B4B4B4"
  tertiary-light: "#6B7280"
  tertiary-dark: "#9A9A9A"
  success-light: "#287A52"
  success-dark: "#4DBA7A"
  warning-light: "#916814"
  warning-dark: "#D4A85B"
  error-light: "#B5444C"
  error-dark: "#E16C72"
  info-light: "#356F9F"
  info-dark: "#6DA7D8"
typography:
  display:
    fontFamily: "Times New Roman, Times, Noto Serif, serif"
    fontSize: "36px"
    fontWeight: 500
    lineHeight: 1.12
    letterSpacing: "-0.35px"
  headline:
    fontFamily: "Times New Roman, Times, Noto Serif, serif"
    fontSize: "30px"
    fontWeight: 500
    lineHeight: 1.2
  title:
    fontFamily: "Times New Roman, Times, Noto Serif, serif"
    fontSize: "20px"
    fontWeight: 500
    lineHeight: 1.3
  body:
    fontFamily: "platform sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.45
  label:
    fontFamily: "platform sans-serif"
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.43
rounded:
  sm: "6px"
  md: "12px"
  lg: "18px"
  card: "16px"
  pill: "999px"
spacing:
  micro: "4px"
  compact: "8px"
  small: "12px"
  standard: "16px"
  section: "24px"
  large: "32px"
  major: "48px"
  structural: "64px"
components:
  button-primary:
    backgroundColor: "semantic controlPrimary (deep burgundy in light, soft rose in dark)"
    textColor: "contrasting text color for controlPrimary"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "12px 16px"
    height: "48px"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.ink-light}"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "12px 16px"
    height: "48px"
  card:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.ink-light}"
    rounded: "{rounded.card}"
    padding: "16px"
  input:
    backgroundColor: "{colors.subtle-light}"
    textColor: "{colors.ink-light}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "16px"
    height: "48px"
  navigation:
    backgroundColor: "semantic footerSurface"
    textColor: "{colors.ink-light}"
    typography: "{typography.label}"
    height: "56px"
---

<!-- Current design guidance. Keep aligned with approved redesign decisions and Flutter implementation status. -->
# Design System: Butlerly

<!-- Design decisions are tracked here; refer to Flutter tokens and tests for implementation status. -->

## Overview

**Creative North Star: "The Quiet Ledger"**

Butlerly's visual language treats personal finance as a calm, consequential practice rather than a dashboard spectacle. A quiet-premium neutral foundation gives financial information room to breathe, while a restrained burgundy accent marks actions, review states, and brand presence. The system is deliberately editorial in moments that ask users to interpret money, and deliberately platform-native in functional controls.

The experience is smartphone-first but width-driven rather than device-branded. Content stays readable inside a centered surface, navigation adapts across compact, medium, and wide layouts, and the same semantic color roles work in light and dark appearance. Depth comes primarily from tonal surfaces and fine borders; elevation is reserved for overlays and modal decisions.

**Key Characteristics:**
- Quiet-premium, editorial clarity for financial decisions.
- Serif hierarchy for editorial and financial emphasis; platform sans-serif for functional UI.
- Burgundy interaction language with stable semantic success, warning, error, and information colors.
- Cool light neutrals and near-black dark surfaces with restrained borders and deliberate 6/12/16/18px geometry.
- Width-driven responsive behavior with 44px minimum touch targets and accessible text scaling.

## Colors

The palette is neutral-first and semantic. Butler Red is the default brand theme; Sky Blue and Green are supported accent themes while financial status colors remain stable and meaningful.

### Primary
- **Butler Burgundy** (`{colors.brand-burgundy}`): brand identity and default interactive emphasis.
- **Deep Burgundy** (`{colors.brand-deep}`): primary controls and high-contrast action surfaces.
- **Soft Rose** (`{colors.interactive-rose}`): selected, review, and dark-theme interactive emphasis.

### Neutral
- **Cool Light Canvas** (`{colors.paper-light}`): light appearance background and navigation canvas.
- **Near-Black Canvas** (`{colors.canvas-dark}`): dark appearance background.
- **White Surface** (`{colors.surface-light}`): light appearance cards and content surfaces.
- **Dark Surface** (`{colors.surface-dark}`): dark appearance sheets and content surfaces.
- **Dashboard Dark** (`{colors.dashboard-dark}`): dark appearance cards and dashboard surfaces.
- **Raised Dark Surface** (`{colors.elevated-dark}`): dialogs and elevated dark-theme content.
- **Sheet Dark** (`{colors.sheet-dark}`) and **Subtle Light** (`{colors.subtle-light}`): modal, navigation, and filled-control surfaces.
- **Light Ink** (`{colors.ink-light}`) and **Dark Ink** (`{colors.ink-dark}`): primary text by appearance.
- **Light Border** (`{colors.border-light}`) and **Dark Border** (`{colors.border-dark}`): dividers and control outlines.

### Semantic
- **Success** (`{colors.success-light}` / `{colors.success-dark}`), **Warning** (`{colors.warning-light}` / `{colors.warning-dark}`), **Error** (`{colors.error-light}` / `{colors.error-dark}`), and **Info** (`{colors.info-light}` / `{colors.info-dark}`) communicate state and never replace text or other accessible cues.

### Named Rules
**The Rare Accent Rule.** Burgundy is an intentional signal for action, selection, and brand—not a background texture applied to every surface.

**The Meaningful Color Rule.** Financial status colors remain semantically stable across accent themes and are never the sole carrier of meaning.

## Typography

**Display Font:** Times New Roman (with Times, Noto Serif, and serif fallbacks)
**Body Font:** Platform sans-serif
**Label/Mono Font:** Platform sans-serif for labels; tabular figures for financial amounts.

**Character:** Editorial serif type gives totals, headings, and financial amounts a composed, human register. Functional copy stays on the platform sans-serif to preserve legibility, familiarity, and cross-platform behavior.

### Hierarchy
- **Display** (500, 36px, 1.12): major editorial or summary emphasis.
- **Headline** (500, 30px, 1.2): page-level titles and high-level financial context.
- **Title** (500, 20px, 1.3): section headings and meaningful component titles.
- **Body** (400, 16px, 1.45): primary explanatory and transactional content.
- **Label** (500, 14px, 1.43): controls, actions, and compact metadata; navigation labels use a smaller 10.5px role.

### Named Rules
**The Editorial-Functional Split.** Use the serif for interpretation and financial emphasis; use the platform sans-serif for controls, labels, and operational copy.

**The Ledger Figures Rule.** Financial amounts use tabular figures and a restrained editorial treatment so columns and comparisons remain easy to scan.

## Layout

Butlerly uses a width-driven responsive model: compact below 801 logical pixels, medium from 801 to 1023 logical pixels, and wide at 1024 logical pixels and above. Qualifying tablet landscape viewports are promoted to wide even below 1024 logical pixels. Compact screens use the bottom navigation shell; wide layouts can use an expanded or collapsed navigation rail. Content is centered inside a readable surface capped at 760px, with 12px content gutters and a spacing rhythm built from 4, 8, 12, 16, 24, 32, 48, and 64px steps. Page chrome may span the viewport, but the readable content surface remains visually distinct.

## Elevation & Depth

The system is tonal by default. Cards use a low, consistent 2px elevation with neutral surface separation; overlays use restrained elevation only when a dialog, bottom sheet, or floating element needs to sit above the working surface. Dark appearance uses near-black and charcoal tonal layering instead of glow or heavy contrast effects.

### Shadow Vocabulary
- **Base:** no elevation; separation comes from surface tone and border.
- **Card:** 2px semantic elevation for dashboard and transaction cards.
- **Overlay:** 4px semantic elevation for floating elements.
- **Modal:** 8px semantic elevation for dialogs and bottom sheets.

### Named Rules
**The Tonal Layer Rule.** Establish hierarchy with surface changes before adding elevation; reserve the 2px card lift for scannable content groups.

**The Calm Overlay Rule.** Motion and elevation should clarify a transition or decision, never compete with the financial content.

## Shapes

Controls use a compact 6px radius for compact icon controls and a full pill for shared buttons. Cards use a 16px radius; inputs use a 12px radius. Dialogs and bottom sheets use a softer 18px radius, while filters and selected tabs can use a full pill. Borders are quiet and semantic; clipping is used to keep interactive card surfaces coherent. Interactive targets are at least 44px, with 48px preferred for primary controls.

## Components

### Buttons
- **Shape:** full pill radius with a 48px preferred height.
- **Primary:** deep burgundy with light text in light mode; soft rose with contrast-aware dark text in dark mode, with the existing 16px horizontal padding.
- **Secondary / Ghost:** transparent or outlined surface using semantic borders and the same control geometry.
- **Focus / Disabled:** preserve the minimum target and use semantic focus and muted disabled colors rather than changing geometry.

### Cards / Containers
- **Corner Style:** 16px radius (current `ButlerlyRadius.card`).
- **Background:** `dashboardSurface` / `cardSurface` from `ButlerlySemanticColors`, selected by appearance.
- **Shadow Strategy:** 2px card elevation at rest; use tonal separation and no decorative outline.
- **Internal Padding:** use `ButlerlySpacing.cardPadding` (16px) for standard cards; the shared `ButlerlyTransactionInnerCard` applies `ButlerlySpacing.micro` (4px) of internal padding. Parent widgets determine outer gutters and list spacing.

### Inputs / Fields
- **Style:** filled subtle-surface background, 12px radius, and a quiet semantic border; exact surface follows the active appearance.
- **Focus:** interactive border with a 1.5px emphasis, without changing the field's size.
- **Error / Disabled:** semantic error or tertiary text roles with preserved labels and recovery guidance.

### Navigation
- **Compact and medium:** labeled bottom navigation with five primary destinations: Home, Transactions, Add, Tools, and More. Add is the primary capture/action destination; Tools and More group operational and configuration surfaces.
- **Wide:** width-aware navigation rail with expanded and collapsed modes; expanded width is 248px and collapsed width is 72px.
- **States:** selected navigation uses the interactive role; unselected navigation uses secondary text and icon roles.

### Bottom Sheets and Dialogs
- **Shape:** 18px top corners for sheets and 18px corners for dialogs.
- **Behavior:** safe-area aware, scrollable when needed, with a clear title-to-content-to-action rhythm and an explicit escape path.

### Transaction Rows
- **Structure:** category identity, merchant/title, metadata, and a tabular financial amount arranged for rapid scanning.
- **Behavior:** preserve semantic labels, stable row height, and clear separation between records without relying on color alone.

## Do's and Don'ts

### Do:
- **Do** use semantic color roles from `ButlerlySemanticColors` instead of feature-local colors.
- **Do** preserve the width-driven compact, medium, and wide layout modes.
- **Do** keep interactive targets at least 44px and prefer 48px for primary controls.
- **Do** use the existing spacing and radius tokens rather than introducing one-off dimensions.
- **Do** verify light, dark, localized, and large-text states before considering a surface complete.

### Don't:
- **Don't** use color alone to communicate financial status, review state, or errors.
- **Don't** replace the editorial/functional typography split with one generic font everywhere.
- **Don't** add heavy shadows, gradients, or decorative effects that compete with financial comprehension.
- **Don't** introduce a new navigation or modal pattern when the shared components already cover the behavior.
- **Don't** treat a desktop-width layout as a scaled-up phone screen; use the existing adaptive shell and readable surface.


## Centralized responsive design tokens

All styling decisions must use a named semantic role rather than layout or theme checks scattered across pages. **Layout mode chooses the scale and geometry; theme chooses semantic colors; components consume those resolved tokens.**

- **Mode resolution:** `ButlerlyResponsiveDesignTokens.of(context)` selects Compact, Medium, or Wide, including tablet landscape behavior. It exposes the `homeTypography`, `homeColors`, `geometry`, and `colors` roles. New screens should use the same resolver rather than repeating breakpoint checks inside every widget.
- **Theme colors:** `ButlerlySemanticColors.palette` remains the source of truth for light/dark appearance and Butler Red, Sky Blue, and Green accents. Avoid literal light/dark colors inside feature widgets.
- **Font sizes and hierarchy:** `ButlerlyTypography` provides canonical TextStyle roles. The responsive Home typography roles use these styles while choosing size by mode: for example Compact greeting 20, card title 14, amount 20; Medium greeting 24, card title 16, amount 24; desktop toolbar greeting 16 and card title 16. Font family, weight, color, and accessibility text scaling remain in the normal theme and semantic roles.
- **Spacing and shape:** `ButlerlySpacing`, `ButlerlyRadius`, `ButlerlySize`, and `ButlerlyGeometryTokens` centrally define page gutters, card padding, inner-card padding/gutters, card gaps, section spacing, and component dimensions. Current Home geometry preserves the approved 12 logical-pixel page gutter and inter-card gap; changes must be made in token definitions, not copied as new constants through feature screens.
- **Scoped typography changes:** Only **Compact Home** uses the smaller Home headline, greeting, summary, chart, and card typography tokens. **Transaction rows** use one responsive shared component across **all pages**: in Compact mode, title and amount are 14px, metadata 13px, and badge 11px; Medium and Wide preserve their existing 15px/14px/12px row typography. Row geometry, touch targets, color semantics, and shared component behavior remain unchanged. Desktop Home is not restyled by this migration.
- **Migration status:** Home consumes mode-resolved typography and shared summary color tokens, and transaction rows use mode-resolved typography across pages. Other feature-specific styling is **not yet fully migrated**. Subsequent migrations require separate approval, with comparison tests in Compact, Medium, Wide, light, dark, and large-text states.

The implementation source is `apps/butlerly/lib/design_system/theme/butlerly_responsive_design_tokens.dart`. Keep design documentation, screen implementations, and tests aligned; do not create screen-specific overrides without an explicit design-system role.

## Implementation token authority (October 2026)

For current UI implementation, use `apps/butlerly/lib/design_system/theme/butlerly_semantic_colors.dart` for light/dark color roles, `apps/butlerly/lib/design_system/tokens/butlerly_tokens.dart` and `butlerly_button.dart` for radius/spacing/navigation/button geometry, `apps/butlerly/lib/design_system/tokens/butlerly_typography.dart` for type roles, and shared components under `apps/butlerly/lib/design_system/components/`. `DESIGN.md` is the current design authority; these code tokens and widgets are implementation evidence that must remain aligned with it. Historical visual references and retired redesign targets are not active requirements.

Current defaults include light background `#F6F7F8`, light card `#FFFFFF`, dark background `#030405`, dark dashboard card `#141516`, 16px card radius, 12px page gutter, pill-shaped shared buttons, and 56px minimum navigation bar height (navigation can grow to accommodate localized labels). Accent themes may replace brand roles while financial semantic colors remain stable.

### Exact implemented semantic surfaces

These values are read from `apps/butlerly/lib/design_system/theme/butlerly_semantic_colors.dart` and supplement the implementation contract below.

| Role | Light | Dark |
| --- | --- | --- |
| Page background | `#F6F7F8` | `#030405` |
| General surface | `#F0F2F5` | `#1F2123` |
| Dashboard/card surface | `#FFFFFF` | `#141516` |
| Elevated surface | `#F0F2F5` | `#292B2D` |
| Bottom navigation surface | `#F2F3F5` | `#141516` |
| Primary text | `#14171D` | `#FFFFFF` |
| Divider/border | `#D8DDE6` | `#282C30` |

The compact navigation uses the existing `PrimaryBottomNavigation` component and is not a top-of-page navigation switch. Its nominal 56px height can expand to accommodate localized labels and safe areas. The selected icon receives the semantic `navigationSelectedIcon` color.

## Current implementation contract (October 2026)

The following statements describe the current shipped direction. Runtime code, shared tokens, and tests should remain aligned with them.

- **Colors:** use the semantic light/dark palettes above. The default dark mode is a near-black canvas with charcoal dashboard, sheet, and elevated surfaces; the default light mode is a cool gray canvas with white dashboard cards.
- **Cards:** use shared components, 16px outer card radius, 16px standard card padding, 4px internal padding in `ButlerlyTransactionInnerCard` (outer gutters are caller-controlled), 2px card elevation, and no decorative outline.
- **Buttons:** use the shared primary, secondary, tertiary, destructive, compact, and segmented variants. Shared buttons use full-pill geometry, 16px horizontal padding, 12px vertical padding, and a preferred 48px height.
- **Navigation:** compact and medium layouts expose Home, Transactions, Add, Tools, and More. Wide layouts use the same destinations in a 248px expanded or 72px collapsed rail. Add remains a first-class capture action; Review, Analysis, Insights, payment settlements, master data, and rules are reached through Tools or contextual routes.
- **Bottom sheets:** use the shared sheet container with 18px top corners, safe-area-aware padding, semantic surfaces, and explicit escape paths. Selection and filter sheets should use shared controls rather than feature-local variants.
- **Typography:** use the editorial serif roles for high-level interpretation and financial emphasis, and platform sans-serif roles for functional controls, labels, dense rows, and operational copy. Financial amounts use tabular figures.
- **Interaction details:** preserve localized full dates in Add/Edit Transaction, the textual image-view action in Transaction Detail, and right-aligned Review decisions, import restoration actions, and Create New Payment Source actions.
- **Page composition:** keep Analysis headings inside their cards and preserve the shared content spacing across Home, Review, Insights, and Analysis.
- **Analysis reporting:** the existing Analysis page remains the periodic-report surface. Category, subcategory, merchant, and recurring-pattern sections use the same shared cards, spacing, typography, localization, and responsive behavior; recurring patterns are clearly presented as detected/derived information and never visually merge with actual totals. A next-occurrence date is shown only when cadence and amount evidence support it; otherwise the shared recurring card says the prediction is unavailable.
- **Analysis evidence states:** breakdown drill-through is driven by the metric's evidence transaction IDs, including occurrence-only and older records; when IDs are present, route/list date defaults must not narrow that evidence set. When a grouped amount cannot be normalized to the selected currency, show the shared localized unavailable state instead of a zero-valued amount.
- **Analysis quality states:** valid empty periods remain explicit zero/no-spending states, while unavailable summary/category amounts use the same localized unavailable treatment. Unavailable breakdown rows are non-interactive until evidence is available; malformed duplicate decisions remain visible as data-quality limitations.
- **Review duplicate states:** Possible Duplicates uses the existing Review cards, buttons, spacing, typography, and semantic colors for both canonical transaction groups and pending statement-row candidates. Statement evidence remains visible with the matched transaction, source text, and explicit Link, Create New, Skip, and Review Later actions; stale resolved groups reopen in the same surface after duplicate-key edits and expose a localized **Clear stale duplicate relationship** repair action instead of ordinary Keep Both/Consolidate controls. The repair retires obsolete derived metadata without changing transactions, provenance, source evidence, or valid groups that share a member. Incomplete transaction-only groups expose the existing repair action instead of presenting an unusable decision card. A duplicate resolution or stale-relationship repair invalidates materialized Analysis/Insights results before the next read; stale or incomplete repair context survives local backup/restore.
- **Calendar day summary:** the selected-day amount displays the canonical calendar expense metric and its localized unavailable state when normalization is insufficient; it does not sum raw drill-through rows, whose currencies and directions may differ.
- **Responsive and accessible behavior:** preserve compact `<600px`, medium `600–1023px`, and wide `>=1024px` modes; keep a 44px minimum touch target, prefer 48px for primary controls, and verify light, dark, localized, and large-text states.
