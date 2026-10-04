import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
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

  test('editorial typography prefers Times New Roman with serif fallbacks', () {
    expect(ButlerlyTypography.editorialFontFamily, 'Times New Roman');
    expect(ButlerlyTypography.editorialFontFallback, const [
      'Times',
      'Noto Serif',
      'serif',
    ]);
    expect(
      <String>[
        ButlerlyTypography.editorialFontFamily,
        ...ButlerlyTypography.editorialFontFallback,
      ],
      isNot(contains('Georgia')),
      reason:
          'Georgia must not reappear as a fallback because its numerals are the reason Butlerly prefers Times New Roman.',
    );
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      expect(
        theme.textTheme.displaySmall?.fontFamily,
        ButlerlyTypography.editorialFontFamily,
      );
      expect(
        theme.textTheme.displaySmall?.fontFamilyFallback,
        ButlerlyTypography.editorialFontFallback,
      );
    }
  });

  test(
    'semantic operational typography uses platform sans and ledger figures',
    () {
      final base = AppTheme.light.textTheme;
      final roles = [
        ButlerlyTypography.pageHeroTitle(base.headlineLarge!),
        ButlerlyTypography.pageIntro(base.bodyLarge!),
        ButlerlyTypography.cardTitle(base.titleLarge!),
        ButlerlyTypography.compactCardTitle(base.titleLarge!),
        ButlerlyTypography.cardSubtitle(base.bodySmall!),
        ButlerlyTypography.cardAction(base.labelLarge!),
        ButlerlyTypography.metricLabel(base.labelLarge!),
        ButlerlyTypography.metricValue(base.titleLarge!),
        ButlerlyTypography.metricChange(base.bodySmall!),
        ButlerlyTypography.rowTitle(base.bodyLarge!),
        ButlerlyTypography.rowMetadata(base.bodySmall!),
        ButlerlyTypography.rowAmount(base.titleMedium!),
        ButlerlyTypography.badgeLabel(base.bodySmall!),
      ];

      for (final role in roles) {
        expect(role.fontFamily, isNull);
        expect(role.fontFamilyFallback, isNull);
      }
      final roleSizes = <({TextStyle role, double size})>[
        (role: ButlerlyTypography.pageHeroTitle(base.headlineLarge!), size: 32),
        (role: ButlerlyTypography.pageIntro(base.bodyLarge!), size: 16),
        (role: ButlerlyTypography.brandTitle(base.headlineLarge!), size: 20),
        (role: ButlerlyTypography.cardTitle(base.titleLarge!), size: 21),
        (role: ButlerlyTypography.compactCardTitle(base.titleLarge!), size: 18),
        (role: ButlerlyTypography.cardSubtitle(base.bodySmall!), size: 14),
        (role: ButlerlyTypography.cardAction(base.labelLarge!), size: 14),
        (role: ButlerlyTypography.metricLabel(base.labelLarge!), size: 14),
        (role: ButlerlyTypography.metricValue(base.titleLarge!), size: 24),
        (role: ButlerlyTypography.metricChange(base.bodySmall!), size: 14),
        (role: ButlerlyTypography.rowTitle(base.bodyLarge!), size: 16),
        (role: ButlerlyTypography.rowMetadata(base.bodySmall!), size: 14),
        (role: ButlerlyTypography.rowAmount(base.titleMedium!), size: 16),
        (role: ButlerlyTypography.badgeLabel(base.bodySmall!), size: 13),
      ];
      for (final spec in roleSizes) {
        expect(spec.role.fontSize, spec.size);
      }
      expect(
        ButlerlyTypography.metricValue(base.titleLarge!).fontFeatures,
        isNotEmpty,
      );
      expect(
        ButlerlyTypography.rowAmount(base.titleMedium!).fontFeatures,
        isNotEmpty,
      );
      expect(ButlerlyTypography.cardTitle(base.titleLarge!).fontSize, 21);
      expect(
        ButlerlyTypography.compactCardTitle(base.titleLarge!).fontSize,
        18,
      );
      expect(
        ButlerlyTypography.compactMetricValue(base.titleLarge!).fontSize,
        16,
      );
      expect(ButlerlyTypography.metricValue(base.titleLarge!).fontSize, 24);
    },
  );

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
          _contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
          greaterThanOrEqualTo(4.5),
          reason: '$colorTheme ${theme.brightness} filled control',
        );
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
        expect(
          _contrast(theme.colorScheme.secondary, theme.colorScheme.onSecondary),
          greaterThanOrEqualTo(4.5),
          reason: '$colorTheme ${theme.brightness} secondary control',
        );
        expect(
          _contrast(theme.colorScheme.tertiary, theme.colorScheme.onTertiary),
          greaterThanOrEqualTo(4.5),
          reason: '$colorTheme ${theme.brightness} tertiary control',
        );
        expect(
          _contrast(theme.colorScheme.error, theme.colorScheme.onError),
          greaterThanOrEqualTo(4.5),
          reason: '$colorTheme ${theme.brightness} error control',
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
