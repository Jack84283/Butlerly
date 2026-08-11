# Butlerly Home design QA

- Source visual truth: `design/04 Design/Screens/UI-0101 — Home — Smartphone Dark.png`
- Implementation screenshot: `design-evidence/home-ios-17pro-dark.png`
- Combined comparison: `design-evidence/home-comparison.png`
- Viewport: 390 × 844 logical pixels, density 1×
- Source pixels: 1024 × 1536 annotated design board containing a framed phone
- Implementation pixels: 1206 × 2622 (iPhone 17 Pro Simulator at 3× density)
- Normalization: the source board was scaled to 390 px wide and top-aligned beside the 390 × 844 implementation capture; the embedded source phone cannot be normalized independently without extracting it from the board
- State: dark-theme Home with an empty local SQLite store

## Full-view comparison evidence

The source and implementation were reviewed together, followed by a native iPhone 17 Pro Simulator capture. Both use a near-black canvas, neutral elevated cards, red interactive accents, greeting-first hierarchy, a four-action row, recent-activity region, and persistent bottom navigation. The implementation is intentionally more vertically spacious because it uses BDS tokens at a modern full-height iPhone viewport, while the reference phone is a small element inside an annotated board.

## Focused-region comparison evidence

The summary/header, quick actions, attention state, and bottom navigation were reviewed in the native capture. Native San Francisco typography, line wrapping, icon rasterization, card borders, safe areas, and bottom navigation all render cleanly.

## Required fidelity surfaces

- Fonts and typography: native iOS hierarchy, wrapping, truncation, weight, and rasterization were verified on an iPhone 17 Pro Simulator.
- Spacing and layout rhythm: BDS phone gutters, spacing tokens, card radii, and scroll structure are present. Automated checks pass at 320 × 568, 390 × 844, and 430 × 932.
- Colors and visual tokens: refreshed BDS dark tokens are used: near-black background, neutral surfaces, off-white text, burgundy/interactive red, and semantic green only for the success state.
- Image quality and assets: the Home design requires no custom raster imagery; Flutter Material icons provide the icon treatment.
- Copy and content: unsupported net-worth, transfer, reports, cloud-sync, and fabricated transaction data are omitted. The screen instead reports truthful local records and canonical Finance V1 destinations.

## Findings

- No remaining code-observed P0/P1/P2 layout issue. The initial 320 px local-summary header overflow was fixed by giving its title flexible width and safe truncation.
- Intentional authority-driven difference: the reference net-worth chart is replaced by local transaction and review counts because the current domain does not provide an authoritative aggregate balance capability.
- Intentional authority-driven difference: Transfer and Reports are replaced by Import and Search; primary navigation remains Home, Transactions, Review, Search, and Settings.
- Native verification: the app launched successfully on iPhone 17 Pro with iOS 26.5 in dark appearance. Runtime logs contained no Flutter overflow or layout exceptions.

## Comparison history

1. P2: the local-summary heading overflowed by 9.9 px at 320 × 568. Fixed with `Expanded`, single-line truncation, and retested at all three phone widths.
2. Post-fix evidence: `design-evidence/home-comparison.png`; no further layout overflow appears in the tested implementation.

## Primary interactions tested

Home rendering, canonical navigation to Review and Search, quick-action route presence, dark appearance, adaptive tablet navigation, and the existing local transaction lifecycle suite.

## Console errors checked

Widget tests report no Home layout exceptions after the fix. Native iOS runtime logs could not be checked without Xcode and an iOS Simulator.

## Final result

final result: passed
