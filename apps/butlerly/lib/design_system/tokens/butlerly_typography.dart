import 'package:flutter/material.dart';

/// Theme-independent Butlerly type scale. AppTheme supplies semantic colors
/// while this token owns reusable sizes, weights, and line heights.
abstract final class ButlerlyTypography {
  static const financialAmountFeatures = [FontFeature.tabularFigures()];
  static TextTheme apply(
    TextTheme base, {
    required Color primaryText,
    required Color secondaryText,
    required Color tertiaryText,
  }) => base.copyWith(
    displaySmall: base.displaySmall?.copyWith(
      fontSize: 32,
      height: 1.25,
      fontWeight: FontWeight.w600,
      color: primaryText,
    ),
    headlineLarge: base.headlineLarge?.copyWith(
      fontSize: 28,
      height: 34 / 28,
      fontWeight: FontWeight.w600,
      color: primaryText,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontSize: 22,
      height: 28 / 22,
      fontWeight: FontWeight.w600,
      color: primaryText,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 18,
      height: 24 / 18,
      fontWeight: FontWeight.w600,
      color: primaryText,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: primaryText,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.5,
      color: primaryText,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: 15,
      height: 1.4,
      color: secondaryText,
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 12,
      height: 17 / 12,
      color: tertiaryText,
    ),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 14,
      height: 20 / 14,
      fontWeight: FontWeight.w500,
      color: primaryText,
    ),
  );

  static TextStyle navigationLabel(
    TextStyle base, {
    required Color color,
    required bool selected,
  }) => base.copyWith(
    fontSize: 10.5,
    color: color,
    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
  );

  static TextStyle financialAmount(TextStyle base) => base.copyWith(
    fontFeatures: financialAmountFeatures,
    fontWeight: FontWeight.w700,
  );

  static TextStyle financialDetailAmount(TextStyle base) => base.copyWith(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    fontFeatures: financialAmountFeatures,
  );
}
