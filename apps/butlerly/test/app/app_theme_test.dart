import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/theme/butlerly_button_palette.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_button.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('button styles use capsule geometry and theme-aware role surfaces', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final colors = theme.extension<ButlerlySemanticColors>()!;
      final palette = ButlerlyButtonPalette.resolve(
        colors: colors,
        brightness: theme.brightness,
      );
      final expectedShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ButlerlyRadius.full),
      );

      expect(ButlerlyButtonTokens.radius, ButlerlyRadius.full);
      expect(ButlerlyButtonTokens.height, 32);
      expect(ButlerlyButtonTokens.minimumWidth, 120);
      expect(ButlerlyButtonTokens.iconSize, 18);
      for (final buttonStyle in [
        theme.filledButtonTheme.style!,
        theme.outlinedButtonTheme.style!,
        theme.textButtonTheme.style!,
      ]) {
        expect(buttonStyle.minimumSize?.resolve({}), const Size(120, 32));
        expect(
          buttonStyle.padding?.resolve({}),
          const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        );
        expect(buttonStyle.textStyle?.resolve({})?.fontSize, 14);
      }
      expect(
        theme.iconButtonTheme.style?.minimumSize?.resolve({}),
        const Size(32, 32),
      );
      expect(
        theme.iconButtonTheme.style?.backgroundColor?.resolve({}),
        colors.subtleSurface,
      );
      expect(
        theme.iconButtonTheme.style?.tapTargetSize,
        MaterialTapTargetSize.padded,
      );
      expect(theme.iconButtonTheme.style?.iconSize?.resolve({}), 18);
      expect(theme.filledButtonTheme.style?.shape?.resolve({}), expectedShape);
      expect(
        theme.outlinedButtonTheme.style?.shape?.resolve({}),
        expectedShape,
      );
      expect(theme.textButtonTheme.style?.shape?.resolve({}), expectedShape);
      expect(
        theme.outlinedButtonTheme.style?.backgroundColor?.resolve({}),
        palette.secondaryFill,
      );
      expect(
        theme.outlinedButtonTheme.style?.foregroundColor?.resolve({}),
        palette.secondaryText,
      );
      expect(
        theme.outlinedButtonTheme.style?.side?.resolve({}),
        BorderSide(color: palette.secondaryBorder),
      );
      expect(
        theme.textButtonTheme.style?.backgroundColor?.resolve({}),
        palette.tertiaryFill,
      );
      expect(
        theme.textButtonTheme.style?.foregroundColor?.resolve({}),
        palette.tertiaryText,
      );
      expect(theme.textButtonTheme.style?.side?.resolve({}), BorderSide.none);
      expect(
        theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
        palette.primaryFill,
      );
    }
  });

  test('dark secondary text meets contrast on raised surfaces', () {
    final theme = AppTheme.dark;
    final colors = theme.extension<ButlerlySemanticColors>()!;
    final buttonStyle = theme.textButtonTheme.style!;
    final buttonText = buttonStyle.foregroundColor!.resolve({})!;
    final bodySmallText = theme.textTheme.bodySmall!.color!;

    expect(
      _contrast(colors.primaryText, colors.cardSurface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(buttonText, colors.cardSurface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(bodySmallText, colors.cardSurface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('supports all appearance and color-theme combinations', () {
    for (final colorTheme in ButlerlyColorTheme.values) {
      final light = AppTheme.lightFor(colorTheme);
      final dark = AppTheme.darkFor(colorTheme);
      final navy = AppTheme.navyFor(colorTheme);
      final lightColors = light.extension<ButlerlySemanticColors>()!;
      final darkColors = dark.extension<ButlerlySemanticColors>()!;
      final navyColors = navy.extension<ButlerlySemanticColors>()!;

      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(navy.brightness, Brightness.dark);
      expect(navyColors.background, const Color(0xFF0C1118));
      expect(lightColors.interactive, isNotNull);
      expect(darkColors.interactive, isNotNull);
    }
  });

  test('Butler Red uses red accents in Light, Dark and Navy', () {
    const selectedRed = Color(0xFFCF7F9A);
    final light = AppTheme.lightFor(ButlerlyColorTheme.butlerRed);
    final dark = AppTheme.darkFor(ButlerlyColorTheme.butlerRed);
    final navy = AppTheme.navyFor(ButlerlyColorTheme.butlerRed);
    final lightColors = light.extension<ButlerlySemanticColors>()!;
    final darkColors = dark.extension<ButlerlySemanticColors>()!;
    final navyColors = navy.extension<ButlerlySemanticColors>()!;

    // The Light palette previously filled primary buttons blue.
    expect(lightColors.controlPrimary, const Color(0xFF7A1E3A));
    expect(lightColors.interactive, const Color(0xFF7A1E3A));
    expect(lightColors.focusRing, const Color(0xFF7A1E3A));
    expect(light.colorScheme.primary, lightColors.controlPrimary);

    // Dark previously used a white selected accent instead of Butler Red.
    expect(darkColors.interactive, selectedRed);
    expect(darkColors.navigationSelectedIcon, selectedRed);
    expect(darkColors.focusRing, selectedRed);

    // Navy keeps the same dark background but does not force blue controls.
    expect(navyColors.background, const Color(0xFF0C1118));
    expect(navyColors.interactive, selectedRed);
    expect(navyColors.navigationSelectedIcon, selectedRed);
    expect(navyColors.focusRing, selectedRed);
    expect(navyColors.controlPrimary, const Color(0xFF813353));
    expect(navy.colorScheme.primary, navyColors.controlPrimary);
    expect(navy.colorScheme.onPrimary, Colors.white);
    expect(navyColors.selection, const Color(0xFF2F1723));

    // Financial status colors are semantic, not replaceable brand accents.
    for (final (theme, blue) in [
      (light, AppTheme.lightFor(ButlerlyColorTheme.skyBlue)),
      (dark, AppTheme.darkFor(ButlerlyColorTheme.skyBlue)),
      (navy, AppTheme.navyFor(ButlerlyColorTheme.skyBlue)),
    ]) {
      final colors = theme.extension<ButlerlySemanticColors>()!;
      final blueColors = blue.extension<ButlerlySemanticColors>()!;
      expect(colors.success, blueColors.success);
      expect(colors.warning, blueColors.warning);
      expect(colors.error, blueColors.error);
      expect(colors.info, blueColors.info);
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
        ButlerlyTypography.homeGreetingTitle(base.headlineLarge!),
        ButlerlyTypography.pageIntro(base.bodyLarge!),
        ButlerlyTypography.cardTitle(base.titleLarge!),
        ButlerlyTypography.compactCardTitle(base.titleLarge!),
        ButlerlyTypography.cardSubtitle(base.bodySmall!),
        ButlerlyTypography.cardAction(base.labelLarge!),
        ButlerlyTypography.metricLabel(base.labelLarge!),
        ButlerlyTypography.homeSummaryMetricLabel(base.labelLarge!),
        ButlerlyTypography.metricValue(base.titleLarge!),
        ButlerlyTypography.homeSummaryMetricValue(base.titleLarge!),
        ButlerlyTypography.metricChange(base.bodySmall!),
        ButlerlyTypography.compactMetricChange(base.bodySmall!),
        ButlerlyTypography.homeSummaryMetricChange(base.bodySmall!),
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
        (
          role: ButlerlyTypography.homeGreetingTitle(base.headlineLarge!),
          size: 24,
        ),
        (role: ButlerlyTypography.pageIntro(base.bodyLarge!), size: 16),
        (role: ButlerlyTypography.brandTitle(base.headlineLarge!), size: 20),
        (role: ButlerlyTypography.cardTitle(base.titleLarge!), size: 18),
        (role: ButlerlyTypography.compactCardTitle(base.titleLarge!), size: 16),
        (role: ButlerlyTypography.cardSubtitle(base.bodySmall!), size: 14),
        (role: ButlerlyTypography.cardAction(base.labelLarge!), size: 14),
        (role: ButlerlyTypography.metricLabel(base.labelLarge!), size: 14),
        (
          role: ButlerlyTypography.homeSummaryMetricLabel(base.labelLarge!),
          size: 13,
        ),
        (role: ButlerlyTypography.metricValue(base.titleLarge!), size: 24),
        (
          role: ButlerlyTypography.homeSummaryMetricValue(base.titleLarge!),
          size: 14,
        ),
        (role: ButlerlyTypography.metricChange(base.bodySmall!), size: 14),
        (
          role: ButlerlyTypography.compactMetricChange(base.bodySmall!),
          size: 12,
        ),
        (
          role: ButlerlyTypography.homeSummaryMetricChange(base.bodySmall!),
          size: 11,
        ),
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
      expect(ButlerlyTypography.cardTitle(base.titleLarge!).fontSize, 18);
      expect(
        ButlerlyTypography.compactCardTitle(base.titleLarge!).fontSize,
        16,
      );
      expect(
        ButlerlyTypography.compactMetricValue(base.titleLarge!).fontSize,
        15,
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
        AppTheme.navyFor(colorTheme),
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
