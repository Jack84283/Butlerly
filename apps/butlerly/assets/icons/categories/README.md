# Butlerly category icons

Canonical category glyph assets for Butlerly.

- SVG viewBox: `0 0 24 24`
- Standard glyph rendering: 24×24 dp
- Standard colored container: 40×40 dp
- Glyph color: supplied by the UI component, normally white on the category background
- Category background color is **not** baked into SVG assets
- Built-in category identity is theme-independent
- Custom user-defined categories use `custom.svg`

The UI should render these through a shared `ButlerlyCategoryIcon` component rather than placing raw SVGs directly in feature pages.
