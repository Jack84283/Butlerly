import 'package:flutter/material.dart';

/// Theme-independent Butlerly type scale.
///
/// Phase 1 uses a platform editorial serif for brand/display roles while the
/// product font decision remains open. Functional UI copy intentionally stays
/// on the platform sans-serif for legibility and cross-platform familiarity.
abstract final class ButlerlyTypography {
  static const editorialFontFamily = 'Georgia';
  static const editorialFontFallback = <String>[
    'Times New Roman',
    'Noto Serif',
    'serif',
  ];
  static const financialAmountFeatures = [FontFeature.tabularFigures()];
  static const navigationLabelFontSize = 10.5;

  static TextStyle _editorial(TextStyle? base) => (base ?? const TextStyle())
      .copyWith(
        fontFamily: editorialFontFamily,
        fontFamilyFallback: editorialFontFallback,
        letterSpacing: -0.35,
      );

  static TextTheme apply(
    TextTheme base, {
    required Color primaryText,
    required Color secondaryText,
    required Color tertiaryText,
  }) => base.copyWith(
    displaySmall: _editorial(base.displaySmall).copyWith(
      fontSize: 36,
      height: 1.12,
      fontWeight: FontWeight.w500,
      color: primaryText,
    ),
    headlineLarge: _editorial(base.headlineLarge).copyWith(
      fontSize: 30,
      height: 36 / 30,
      fontWeight: FontWeight.w500,
      color: primaryText,
    ),
    headlineMedium: _editorial(base.headlineMedium).copyWith(
      fontSize: 24,
      height: 30 / 24,
      fontWeight: FontWeight.w500,
      color: primaryText,
    ),
    titleLarge: _editorial(base.titleLarge).copyWith(
      fontSize: 20,
      height: 26 / 20,
      fontWeight: FontWeight.w500,
      color: primaryText,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 16,
      height: 1.45,
      fontWeight: FontWeight.w600,
      color: primaryText,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: primaryText,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.45,
      color: secondaryText,
    ),
    // bodySmall is still normal readable copy at 12 px, so it must use the
    // contrast-safe secondary text role. Tertiary text remains available for
    // decorative affordances such as chevrons and non-essential icons.
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 12,
      height: 17 / 12,
      color: secondaryText,
    ),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      color: primaryText,
    ),
    labelMedium: base.labelMedium?.copyWith(
      letterSpacing: 0.5,
      fontWeight: FontWeight.w500,
      color: secondaryText,
    ),
  );

  static TextStyle navigationLabel(
    TextStyle base, {
    required Color color,
    required bool selected,
  }) => base.copyWith(
    fontSize: navigationLabelFontSize,
    color: color,
    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
  );

  /// Uses the compact body geometry with an explicit semantic color supplied
  /// by the caller. Kept for contexts that need to opt into a stronger role.
  static TextStyle readableSmall(
    TextStyle base, {
    required Color color,
  }) => base.copyWith(color: color);

  static TextStyle editorialTitle(TextStyle base) => _editorial(base).copyWith(
    fontWeight: FontWeight.w500,
  );

  static TextStyle financialAmount(TextStyle base) => _editorial(base).copyWith(
    fontFeatures: financialAmountFeatures,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.8,
  );

  static TextStyle financialDetailAmount(TextStyle base) =>
      financialAmount(base).copyWith(fontSize: 38, height: 1.08);
}
