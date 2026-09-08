# Butlerly App Icon

The approved V1 mark combines a geometric **B** and bow tie:

- deep burgundy background: `#720018`
- warm ivory B and knot: `#F6F0E7`
- Butlerly-red bow tie: `#B51F3B`

`butlerly_mark.svg` is the transparent canonical vector. The B is exactly three shapes: a 140 px vertical bar, a 120 px right-facing semicircle, and a 160 px right-facing semicircle. The bar width is `(120 + 160) / 2`, the bowl gap is 20 px, and the B bounding box is 240 × 388 px (`height / width ≈ 1.618`).

`app_icon_burgundy.svg` is the primary shipping composition. The pure-black, charcoal, red, and white files are supporting treatments derived from the same geometry and proportions. They contain no gradients, texture, border, shadow, or additional icon mask.

The platform PNGs are generated from `app_icon_burgundy.svg` by:

```sh
./tool/generate_butlerly_brand_assets.sh
```

The script uses the installed macOS SVG renderer and `sips`; it does not redraw or trace the mark. Android adaptive-icon foreground/background resources are kept separate so the launcher can apply its own mask.

Do not repeatedly use the rounded-square app icon inside the application. The transparent mark is for branded surfaces only and must not be used as a category, merchant, payment-source, or navigation icon.
