# Butlerly smartphone UI design QA

Last updated: 2026-08-11

## Scope and authority

- Primary design-system reference: `docs/04 Design/BDS-0000 — Butler Design System v1.0.pdf`
- UX references: `docs/04 Design/UI Design/`
- Approved screen references: `docs/04 Design/Screens/`
- Primary Home reference: `docs/04 Design/Screens/UI-0101 — Home — Smartphone Dark.png`
- Historical Home implementation capture: `docs/design-evidence/home-ios-17pro-dark.png`
- Historical Home comparison: `docs/design-evidence/home-comparison.png`
- Scope verified here: smartphone-first Flutter UI, with Home as the primary visual-fidelity target and functional checks covering the currently implemented Finance V1 flows.

The generated screen images remain visual references rather than independent product requirements. Where imagery conflicts with Finance V1, the implementation follows the approved local-first, offline-capable, account-free architecture and canonical Home, Transactions, Review, Search, and Settings navigation.

## Current verification environment

- Host: macOS 26.6.1 (25G76), Apple silicon.
- Active simulator: iPhone 17, iOS 26.5, identifier `393FBCAF-0CA9-4B94-B0D4-FDD771488AF4`.
- Native simulator output: 1206 × 2622 pixels, corresponding to 402 × 874 logical pixels at 3× density.
- Latest native smoke check: the running app rendered the Payment Sources screen in light appearance with correct safe areas, navigation, typography, floating action placement, and no visible overflow.
- The filename `home-ios-17pro-dark.png` is retained as historical evidence. It is not the current simulator identity and should not be used to claim that the latest build was verified on an iPhone 17 Pro.

## Home visual fidelity

The historical Home comparison uses a 390 × 844 logical reference viewport. The 1024 × 1536 source is an annotated design board containing a framed phone, so its embedded phone cannot be normalized independently without extracting it from the board.

The implemented Home preserves the approved hierarchy and visual language: near-black canvas in dark appearance, neutral elevated cards, off-white primary text, burgundy/red interactive accents, greeting-first hierarchy, quick actions, attention state, recent transactions, and persistent canonical navigation.

Intentional authority-driven differences remain:

- The reference net-worth chart is replaced by truthful local transaction and review counts because the current domain does not provide an authoritative aggregate-balance capability.
- Transfer and Reports are replaced by Finance V1 actions and destinations such as Import and Search.
- Cloud synchronization, account state, and misleading remote status are omitted.

## Design-system alignment

- Typography uses the platform-native Flutter/iOS hierarchy with tested wrapping and truncation.
- Layout uses centralized BDS spacing, radius, surface, and control tokens rather than feature-local raw styling.
- Automated Home layout checks cover 320 × 568, 390 × 844, and 430 × 932 logical viewports.
- The previous 320-pixel Home summary overflow was fixed with flexible width and single-line truncation.
- Card surfaces use the current semantic elevated-surface tokens: lighter neutral cards in dark/system-dark appearance and darker neutral cards in light appearance.
- Semantic green is reserved for meaningful success state; financial meaning is not communicated through color alone.
- The launch delay is 3000 ms, as currently approved.

## Current functional UI coverage

- New and edited transactions notify dependent screens, so Home and Transactions refresh without restarting the app.
- Transaction dates use the canonical transaction calendar date consistently across Home, lists, detail, and editor views.
- Transaction rows and detail resolve merchant, category, and tag identifiers to user-visible master-data names.
- Initial merchant, category, and tag records are stored through the local persistence architecture.
- Organize Transaction selects only predefined master data, supports adding and removing assigned tags, and returns to the prior transaction context after saving.
- Transaction Detail and its organize, payment-source, archive, delete, evidence, and status UI use application localization.
- Simplified Chinese is available alongside English and Spanish. Butlerly-authored UI changes language; user-entered and source/master data remain unchanged.
- Add Payment Source uses `ButlerlySpacing.small` between the name and type inputs, matching Organize Transaction field rhythm.
- Dark, light, and system appearance selection remain supported.

## Interaction and automated verification

Coverage includes:

- launch/welcome and canonical navigation;
- Home rendering and responsive overflow checks;
- dark appearance and Simplified Chinese switching;
- create, edit, archive, restore, and permanently delete transaction behavior;
- Home refresh after transaction changes outside the Home route;
- merchant, category, and tag display and organization;
- canonical date presentation across transaction screens;
- local search and category filtering;
- review resolution;
- payment-source creation and archive behavior;
- Chinese Transaction Detail and Organize Transaction rendering.

Latest checks:

- `dart format lib test`: passed.
- `flutter analyze`: passed with no issues.
- Full Flutter suite: 26 tests passed.
- Focused transaction/payment-source suite after the latest dialog-spacing change: 12 tests passed.
- The search-filter test currently emits two non-fatal missed-tap warnings; the suite still passes. These warnings should be cleaned up so they cannot conceal a future hit-target regression.

## Native runtime observations

- The app launches and hot-restarts successfully on the active iPhone 17 Simulator.
- The local SQLite database initializes successfully after restart.
- No Flutter overflow or layout exception was observed in the attached runtime output during the latest checks.
- The current live simulator was inspected in light appearance on Payment Sources. The historical dark Home comparison remains the available checked-in visual artifact; a new full dark-screen capture set has not yet been recorded for every implemented screen.

## Remaining visual QA work

- Refresh checked-in evidence using filenames that identify the actual simulator model and OS version.
- Capture current dark-theme native evidence for Transaction Detail, Organize Transaction, Add Payment Source, and localized Chinese states.
- Perform and record screen-by-screen comparison for the remaining approved smartphone references; current evidence is strongest for Home.
- Add targeted small-screen dialog tests where localized labels can expand vertically.
- Replace the two non-fatal search-filter missed-tap warnings with deterministic interaction helpers.

## Result

Current implementation and automated checks: passed.

Full visual sign-off for every approved smartphone reference: pending the remaining native capture and comparison work listed above.
