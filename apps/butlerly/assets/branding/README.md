# Butlerly Brand Assets

This folder contains the canonical Butlerly folded **B** brand mark and approved icon treatments.

## Canonical mark

`butlerly_mark.svg` is the master standalone mark. The geometry represents a single folded, dimensional ribbon/sheet forming a **B**. Its material treatment is translucent champagne with a dark/black internal fold to preserve the intended light-through depth.

The geometry of the folded B must remain identical across approved variants. Background and contrast compensation may change; the core silhouette and fold must not.

## Approved treatments

- `app_icon_warm_black.svg` — **primary app icon**. Warm black `#12120F` with the champagne folded B. Use for the shipping iOS/Android app icon and store identity.
- `app_icon_charcoal.svg` — secondary large-format/marketing treatment on charcoal `#262623`.
- `app_icon_butlerly_red.svg` — secondary Butlerly-red brand treatment on `#8B0000`; do not introduce red into the B's internal fold/shadow.
- `app_icon_white.svg` — light-background alternate on `#F5F5F5`.
- `butlerly_mark.svg` — transparent standalone brand mark for in-product and branded-material use.

## In-product usage

Use the transparent folded B for splash/launch, first-run welcome, About, selected empty/initial states, exported reports, and a future Butlerly Insight/assistant identity when Butlerly itself is speaking.

Do **not** repeatedly use the rounded-square app icon inside normal product UI. Do not use either mark for navigation tabs, transaction/category/payment icons, ordinary dialogs, or routine list rows.

The app icon and brand mark are related but not interchangeable: the app icon is the folded B on its designated background; the brand mark is the standalone folded B.

## Production note

These SVG files are canonical scalable design sources. Platform-specific raster/adaptive icon sets should be generated from `app_icon_warm_black.svg` without changing its B geometry. Android foreground extraction should use the same mark geometry with the warm-black background as the adaptive-icon background. iOS production rasterization should preserve the same composition and avoid adding another rounded-rectangle mask inside the platform mask.
