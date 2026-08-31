import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supports all appearance and color-theme combinations', () {
    for (final colorTheme in ButlerlyColorTheme.values) {
      final light = AppTheme.lightFor(colorTheme);
      final dark = AppTheme.darkFor(colorTheme);
      final lightColors = light.extension<ButlerlySemanticColors>()!;
      final darkColors = dark.extension<ButlerlySemanticColors>()!;

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(lightColors.interactive, isNotNull);
      expect(darkColors.interactive, isNotNull);
    }
  });

  test('color themes produce distinct interactive palettes', () {
    final red = AppTheme.lightFor(
      ButlerlyColorTheme.butlerRed,
    ).extension<ButlerlySemanticColors>()!;
    final blue = AppTheme.lightFor(
      ButlerlyColorTheme.skyBlue,
    ).extension<ButlerlySemanticColors>()!;
    final green = AppTheme.lightFor(
      ButlerlyColorTheme.green,
    ).extension<ButlerlySemanticColors>()!;

    expect(red.interactive, isNot(blue.interactive));
    expect(red.interactive, isNot(green.interactive));
    expect(blue.interactive, isNot(green.interactive));
  });

  test('search hints use the centralized secondary text style', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final colors = theme.extension<ButlerlySemanticColors>()!;
      expect(
        theme.searchBarTheme.hintStyle?.resolve({})?.color,
        colors.secondaryText,
      );
    }
  });

  test('dark and light semantic interactive colors meet text contrast', () {
    for (final colorTheme in ButlerlyColorTheme.values) {
      for (final theme in [
        AppTheme.lightFor(colorTheme),
        AppTheme.darkFor(colorTheme),
      ]) {
        final colors = theme.extension<ButlerlySemanticColors>()!;
        expect(
          _contrast(colors.interactive, colors.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$colorTheme ${theme.brightness} navigation label',
        );
        final chipSurface = Color.alphaBlend(
          colors.review.withValues(alpha: .14),
          colors.surface,
        );
        expect(
          _contrast(colors.review, chipSurface),
          greaterThanOrEqualTo(4.5),
          reason: '$colorTheme ${theme.brightness} review chip',
        );
      }
    }
  });
}

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + .05) / (darker + .05);
}
