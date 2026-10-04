import 'package:flutter/material.dart';

/// Theme-independent Butlerly type scale.
///
/// Butlerly prefers Times New Roman for editorial roles and intentionally keeps
/// Georgia out of the fallback chain. Times New Roman is not bundled as an app
/// asset, so platforms that do not ship it fall back through common serif
/// families. This preserves the requested preference without adding a licensed
/// proprietary font asset or a runtime font download. Functional UI copy stays
/// on the platform sans-serif for legibility and cross-platform familiarity.
abstract final class ButlerlyTypography {
  static const editorialFontFamily = 'Times New Roman';
  static const editorialFontFallback = <String>['Times', 'Noto Serif', 'serif'];
  static const financialAmountFeatures = [FontFeature.tabularFigures()];
  static const navigationLabelFontSize = 10.5;

  // Semantic system-sans roles used by dense operational surfaces. These are
  // intentionally separate from the editorial TextTheme so a screen can opt
  // into the platform-native reading voice without changing every surface.
  static TextStyle _systemSans(
    TextStyle base, {
    required double fontSize,
    required double height,
    required FontWeight fontWeight,
    double? letterSpacing,
    List<FontFeature>? fontFeatures,
  }) => TextStyle(
    color: base.color,
    fontSize: fontSize,
    height: height,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
    fontFeatures: fontFeatures,
    decoration: base.decoration,
    decorationColor: base.decorationColor,
    decorationStyle: base.decorationStyle,
    decorationThickness: base.decorationThickness,
  );

  static TextStyle pageHeroTitle(TextStyle base) => _systemSans(
    base,
    fontSize: 32,
    height: 1.12,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static TextStyle pageIntro(TextStyle base) =>
      _systemSans(base, fontSize: 16, height: 1.3, fontWeight: FontWeight.w400);

  static TextStyle brandTitle(TextStyle base) => _systemSans(
    base,
    fontSize: 20,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static TextStyle cardTitle(TextStyle base) => _systemSans(
    base,
    fontSize: 21,
    height: 1.18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.15,
  );

  /// Compact title role for dense dashboard cards.
  static TextStyle compactCardTitle(TextStyle base) => _systemSans(
    base,
    fontSize: 18,
    height: 1.2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
  );

  static TextStyle cardSubtitle(TextStyle base) =>
      _systemSans(base, fontSize: 14, height: 1.3, fontWeight: FontWeight.w400);

  static TextStyle cardAction(TextStyle base) =>
      _systemSans(base, fontSize: 14, height: 1.3, fontWeight: FontWeight.w600);

  static TextStyle metricLabel(TextStyle base) =>
      _systemSans(base, fontSize: 14, height: 1.3, fontWeight: FontWeight.w500);

  static TextStyle metricValue(TextStyle base) => _systemSans(
    base,
    fontSize: 24,
    height: 1.08,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    fontFeatures: financialAmountFeatures,
  );

  static TextStyle compactMetricValue(TextStyle base) => _systemSans(
    base,
    fontSize: 16,
    height: 1.08,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.35,
    fontFeatures: financialAmountFeatures,
  );

  static TextStyle metricChange(TextStyle base) =>
      _systemSans(base, fontSize: 14, height: 1.3, fontWeight: FontWeight.w600);

  static TextStyle rowTitle(TextStyle base) => _systemSans(
    base,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w600,
  );

  static TextStyle rowMetadata(TextStyle base) =>
      _systemSans(base, fontSize: 14, height: 1.3, fontWeight: FontWeight.w400);

  static TextStyle rowAmount(TextStyle base) => _systemSans(
    base,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
    fontFeatures: financialAmountFeatures,
  );

  /// Dense row roles shared by compact dashboard lists and transaction rows.
  /// These preserve the row hierarchy while matching the tighter reference
  /// scale used when several records share a card.
  static TextStyle denseRowTitle(TextStyle base) => _systemSans(
    base,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
  );

  static TextStyle denseRowAmount(TextStyle base) => _systemSans(
    base,
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    fontFeatures: financialAmountFeatures,
  );

  /// Compact category-summary roles. These are intentionally smaller than
  /// transaction-row roles so five category summaries can remain scannable in
  /// a dashboard card without changing the shared transaction hierarchy.
  static TextStyle compactRowTitle(TextStyle base) => _systemSans(
    base,
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w600,
  );

  static TextStyle compactRowAmount(TextStyle base) => _systemSans(
    base,
    fontSize: 14,
    height: 18 / 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    fontFeatures: financialAmountFeatures,
  );

  static TextStyle compactRowMetadata(TextStyle base) => _systemSans(
    base,
    fontSize: 13,
    height: 17 / 13,
    fontWeight: FontWeight.w400,
  );

  static TextStyle badgeLabel(TextStyle base) =>
      _systemSans(base, fontSize: 13, height: 1.2, fontWeight: FontWeight.w500);

  static TextStyle _editorial(TextStyle? base) =>
      (base ?? const TextStyle()).copyWith(
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

  static TextStyle editorialTitle(TextStyle base) =>
      _editorial(base).copyWith(fontWeight: FontWeight.w500);

  static TextStyle financialAmount(TextStyle base) => _editorial(base).copyWith(
    fontFeatures: financialAmountFeatures,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.8,
  );

  static TextStyle financialDetailAmount(TextStyle base) =>
      financialAmount(base).copyWith(fontSize: 38, height: 1.08);
}
