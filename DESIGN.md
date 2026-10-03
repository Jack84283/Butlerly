---
name: Butlerly
description: Quiet-premium, local-first personal finance for clear and confident daily decisions.
colors:
  brand-burgundy: "#7A1E3A"
  brand-deep: "#541127"
  interactive-rose: "#C76F8B"
  paper-light: "#F7F5F1"
  canvas-dark: "#0A0A0D"
  surface-light: "#FFFFFF"
  surface-dark: "#111114"
  elevated-dark: "#17171C"
  ink-light: "#19181A"
  ink-dark: "#F4F1EC"
  border-light: "#E2DDD7"
  border-dark: "#2F2F36"
  success: "#287A52"
  warning: "#916814"
  error: "#B5444C"
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
    backgroundColor: "{colors.brand-deep}"
    textColor: "#FFFFFF"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "12px 16px"
    height: "48px"
  button-secondary:
    backgroundColor: "transparent"
    textColor: "{colors.ink-light}"
    typography: "{typography.label}"
    rounded: "{rounded.md}"
    padding: "12px 16px"
    height: "48px"
  card:
    backgroundColor: "{colors.surface-light}"
    textColor: "{colors.ink-light}"
    rounded: "{rounded.md}"
    padding: "16px"
  input:
    backgroundColor: "#F1EEE8"
    textColor: "{colors.ink-light}"
    typography: "{typography.body}"
    rounded: "{rounded.md}"
    padding: "16px"
    height: "48px"
  navigation:
    backgroundColor: "{colors.paper-light}"
    textColor: "{colors.ink-light}"
    typography: "{typography.label}"
    height: "48px"
---

# Design System: Butlerly

<!-- Derived from the current Butlerly implementation and approved repository design references. The creative language should be confirmed if the product direction changes. -->

## Overview

**Creative North Star: "The Quiet Ledger"**

Butlerly's visual language treats personal finance as a calm, consequential practice rather than a dashboard spectacle. A quiet-premium neutral foundation gives financial information room to breathe, while a restrained burgundy accent marks actions, review states, and brand presence. The system is deliberately editorial in moments that ask users to interpret money, and deliberately platform-native in functional controls.

The experience is smartphone-first but width-driven rather than device-branded. Content stays readable inside a centered surface, navigation adapts across compact, medium, and wide layouts, and the same semantic color roles work in light and dark appearance. Depth comes primarily from tonal surfaces and fine borders; elevation is reserved for overlays and modal decisions.

**Key Characteristics:**
- Quiet-premium, editorial clarity for financial decisions.
- Serif hierarchy for editorial and financial emphasis; platform sans-serif for functional UI.
- Burgundy interaction language with stable semantic success, warning, error, and information colors.
- Flat, tonal surfaces with restrained borders and deliberate 6/12/18px geometry.
- Width-driven responsive behavior with 44px minimum touch targets and accessible text scaling.

## Colors

The palette is neutral-first and semantic. Butler Red is the default brand theme; Sky Blue and Green are supported accent themes while financial status colors remain stable and meaningful.

### Primary
- **Butler Burgundy** (`{colors.brand-burgundy}`): brand identity and default interactive emphasis.
- **Deep Burgundy** (`{colors.brand-deep}`): primary controls and high-contrast action surfaces.
- **Soft Rose** (`{colors.interactive-rose}`): selected, review, and dark-theme interactive emphasis.

### Neutral
- **Warm Paper** (`{colors.paper-light}`): light appearance background and navigation canvas.
- **Near-Black Canvas** (`{colors.canvas-dark}`): dark appearance background.
- **White Surface** (`{colors.surface-light}`): light appearance cards and content surfaces.
- **Dark Surface** (`{colors.surface-dark}`): dark appearance cards and content surfaces.
- **Raised Dark Surface** (`{colors.elevated-dark}`): dialogs, sheets, and elevated dark-theme content.
- **Light Ink** (`{colors.ink-light}`) and **Dark Ink** (`{colors.ink-dark}`): primary text by appearance.
- **Light Border** (`{colors.border-light}`) and **Dark Border** (`{colors.border-dark}`): dividers and control outlines.

### Semantic
- **Success** (`{colors.success}`), **Warning** (`{colors.warning}`), and **Error** (`{colors.error}`) communicate state and never replace text or other accessible cues.

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

Butlerly uses a width-driven responsive model: compact below 600px, medium from 600px to 1023px, and wide at 1024px and above. Compact screens use the bottom navigation shell; wide layouts can use an expanded or collapsed navigation rail. Content is centered inside a readable surface capped at 760px, with 12px content gutters and a spacing rhythm built from 4, 8, 12, 16, 24, 32, 48, and 64px steps. Page chrome may span the viewport, but the readable content surface remains visually distinct.

## Elevation & Depth

The system is flat by default. Cards use tonal separation and a fine border rather than a shadow; standard card elevation is zero. Overlay surfaces use restrained elevation only when a dialog, bottom sheet, or floating element needs to sit above the working surface. Dark appearance uses neutral tonal layering instead of glow or heavy contrast effects.

### Shadow Vocabulary
- **Base and card:** no shadow; separation comes from surface tone and border.
- **Overlay:** 4px semantic elevation for floating elements.
- **Modal:** 8px semantic elevation for dialogs and bottom sheets.

### Named Rules
**The Tonal Layer Rule.** Establish hierarchy with surface changes before adding elevation.

**The Calm Overlay Rule.** Motion and elevation should clarify a transition or decision, never compete with the financial content.

## Shapes

Controls use a compact 6px radius. Cards and inputs use a consistent 12px radius. Dialogs and bottom sheets use a softer 18px radius, while filters and selected tabs can use a full pill. Borders are quiet and semantic; clipping is used to keep interactive card surfaces coherent. Interactive targets are at least 44px, with 48px preferred for primary controls.

## Components

### Buttons
- **Shape:** 12px radius with a 48px preferred height.
- **Primary:** deep burgundy control surface with light text and 16px horizontal padding.
- **Secondary / Ghost:** transparent or outlined surface using semantic borders and the same control geometry.
- **Focus / Disabled:** preserve the minimum target and use semantic focus and muted disabled colors rather than changing geometry.

### Cards / Containers
- **Corner Style:** 12px radius.
- **Background:** semantic surface or subtle surface, selected by appearance and context.
- **Shadow Strategy:** zero elevation at rest; use tonal separation and a fine border.
- **Internal Padding:** 12px card padding by default, 16px for content-dense or decision-heavy cards.

### Inputs / Fields
- **Style:** filled subtle-surface background, 12px radius, and a quiet semantic border.
- **Focus:** interactive border with a 1.5px emphasis, without changing the field's size.
- **Error / Disabled:** semantic error or tertiary text roles with preserved labels and recovery guidance.

### Navigation
- **Compact:** labeled bottom navigation with a transparent selection indicator and semantic accent color.
- **Wide:** width-aware navigation rail with expanded and collapsed modes.
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
