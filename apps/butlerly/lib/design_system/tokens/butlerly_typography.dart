import 'package:flutter/material.dart';

/// Theme-independent Butlerly type scale.
///
/// Butlerly uses Times New Roman as its preferred editorial serif. Platforms
/// that do not provide it fall back through common serif families while
/// functional UI copy intentionally stays on the platform sans-serif for
/// legibility and cross-platform familiarity.
abstract final class ButlerlyTypography {
  static const editorialFontFamily = 'Times New Roman';
  static const editorialFontFallback = <String>[
    'Times',
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

  /// Applies only the editorial font family and fallback stack.
  ///
  /// This is intended for existing component styles that must retain their
  /// current size, weight, color, height, and spacing while adopting the
  /// Butlerly editorial serif.
  static TextStyle editorialText(TextStyle base) => base.copyWith(
    fontFamily: editorialFontFamily,
    fontFamilyFallback: editorialFontFallback,
  );

  static TextTheme apply(
    TextTheme base, {
    required Color primaryText,
    required Color secondaryText,
    required Color bodySmallText,
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
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 12,
      height: 17 / 12,
      color: bodySmallText,
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
