import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_button_palette.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dark mode uses near-black canvas and layered neutral surfaces', () {
    final colors = AppTheme.dark.extension<ButlerlySemanticColors>()!;
    expect(colors.background, const Color(0xFF0D0D0D));
    expect(colors.cardSurface, const Color(0xFF111111));
    expect(colors.surface, const Color(0xFF111111));
    expect(colors.elevatedSurface, const Color(0xFF292B2D));
    expect(colors.subtleSurface, const Color(0xFF1E1E1E));
    expect(colors.overlaySurface, const Color(0xFF1E1E1E));
    expect(colors.sheetSurface, const Color(0xFF1E1E1E));
    expect(colors.footerSurface, const Color(0xFF111111));
    expect(colors.primaryText, const Color(0xFFFFFFFF));
    expect(colors.secondaryText, const Color(0xFFB4B4B4));
    expect(colors.tertiaryText, const Color(0xFF9A9A9A));
    expect(colors.cardDivider, const Color(0xFF282C30));
    expect(colors.border, const Color(0xFF282C30));
    expect(
      _contrast(colors.secondaryText, colors.cardSurface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      _contrast(colors.tertiaryText, colors.elevatedSurface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test(
    'light mode matches the approved off-white background specification',
    () {
      final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
      expect(colors.background, const Color(0xFFF6F7F8));
      expect(colors.cardSurface, const Color(0xFFFFFFFF));
      expect(colors.surface, const Color(0xFFF0F2F5));
      expect(colors.elevatedSurface, const Color(0xFFF0F2F5));
      expect(colors.subtleSurface, const Color(0xFFF2F3F5));
      expect(colors.overlaySurface, const Color(0xFFFFFFFF));
      expect(colors.sheetSurface, const Color(0xFFF2F3F5));
      expect(colors.footerSurface, const Color(0xFFF2F3F5));
      expect(colors.primaryText, const Color(0xFF14171D));
      expect(colors.secondaryText, const Color(0xFF4B5563));
      expect(colors.tertiaryText, const Color(0xFF6B7280));
      expect(colors.cardDivider, const Color(0xFFD8DDE6));
      expect(colors.border, const Color(0xFFD8DDE6));
      expect(colors.brand, const Color(0xFF7A1E3A));
      expect(
        colors.cardSurface.computeLuminance(),
        greaterThan(colors.background.computeLuminance()),
      );
      expect(
        colors.background.computeLuminance(),
        greaterThan(colors.elevatedSurface.computeLuminance()),
      );
    },
  );

  test('shared controls use the approved light and dark color roles', () {
    expect(
      ButlerlySemanticColors.light.controlPrimary,
      const Color(0xFF541127),
    );
    expect(ButlerlySemanticColors.dark.controlPrimary, const Color(0xFFC76F8B));

    for (final colorTheme in ButlerlyColorTheme.values) {
      for (final theme in [
        AppTheme.lightFor(colorTheme),
        AppTheme.darkFor(colorTheme),
      ]) {
        final colors = theme.extension<ButlerlySemanticColors>()!;
        final buttons = ButlerlyButtonPalette.resolve(
          colors: colors,
          brightness: theme.brightness,
        );
        final dark = theme.brightness == Brightness.dark;
        expect(buttons.primaryFill, colors.controlPrimary);
        expect(buttons.secondaryFill, colors.cardSurface);
        expect(buttons.secondaryBorder, colors.border);
        expect(buttons.secondaryText, colors.primaryText);
        expect(
          buttons.tertiaryFill,
          dark ? colors.elevatedSurface : colors.subtleSurface,
        );
        expect(buttons.chipFill, buttons.tertiaryFill);
        expect(buttons.chipBorder, colors.border);
        expect(
          buttons.segmentFill,
          dark ? colors.surface : colors.subtleSurface,
        );
        expect(buttons.segmentBorder, colors.border);
        expect(
          _contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
  });

  test('light text and secondary actions use distinct contrasted surfaces', () {
    for (final palette in ButlerlyColorTheme.values) {
      final theme = AppTheme.lightFor(palette);
      final colors = theme.extension<ButlerlySemanticColors>()!;
      final buttons = ButlerlyButtonPalette.resolve(
        colors: colors,
        brightness: theme.brightness,
      );
      expect(
        theme.textButtonTheme.style?.backgroundColor?.resolve({}),
        buttons.tertiaryFill,
      );
      expect(
        theme.outlinedButtonTheme.style?.backgroundColor?.resolve({}),
        buttons.secondaryFill,
      );
      expect(buttons.tertiaryFill, isNot(buttons.secondaryFill));
      expect(theme.textButtonTheme.style?.side?.resolve({}), BorderSide.none);
      expect(
        theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
        theme.colorScheme.primary,
      );
    }
  });

  test('dialogs, sheets, snackbars and pages use the dedicated colors', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final colors = theme.extension<ButlerlySemanticColors>()!;
      expect(theme.scaffoldBackgroundColor, colors.background);
      expect(theme.cardTheme.color, colors.cardSurface);
      expect(theme.dialogTheme.backgroundColor, colors.overlaySurface);
      expect(theme.bottomSheetTheme.backgroundColor, colors.sheetSurface);
      expect(theme.bottomSheetTheme.modalBackgroundColor, colors.sheetSurface);
      expect(theme.snackBarTheme.backgroundColor, colors.overlaySurface);
    }
  });

  test('semantic surface roles survive theme overrides and interpolation', () {
    const custom = Color(0xFF345678);
    final dark = ButlerlySemanticColors.dark;
    final light = ButlerlySemanticColors.light;
    expect(dark.copyWith(footerSurface: custom).footerSurface, custom);
    expect(dark.copyWith(sheetSurface: custom).sheetSurface, custom);
    expect(dark.copyWith(overlaySurface: custom).overlaySurface, custom);
    expect(dark.lerp(light, 0).sheetSurface, dark.sheetSurface);
    expect(dark.lerp(light, 1).overlaySurface, light.overlaySurface);
    expect(dark.lerp(light, 1).footerSurface, light.footerSurface);
  });

  test('footer icon accents have accessible contrast in both modes', () {
    for (final theme in ButlerlyColorTheme.values) {
      final lightTheme = AppTheme.lightFor(theme);
      final darkTheme = AppTheme.darkFor(theme);
      final light = lightTheme.extension<ButlerlySemanticColors>()!;
      final dark = darkTheme.extension<ButlerlySemanticColors>()!;
      expect(
        _contrast(light.navigationSelectedIcon, light.footerSurface),
        greaterThanOrEqualTo(3),
      );
      expect(
        _contrast(dark.navigationSelectedIcon, dark.footerSurface),
        greaterThanOrEqualTo(3),
      );
    }
  });

  testWidgets('cards use solid fills in light and dark mode', (tester) async {
    Widget card() => const Scaffold(
      body: Center(child: ButlerlyCard(child: Text('Sample card'))),
    );

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(MaterialApp(theme: theme, home: card()));
      await tester.pumpAndSettle();
      final widget = tester.widget<Card>(find.byType(Card).first);
      final colors = theme.extension<ButlerlySemanticColors>()!;
      expect(widget.color ?? theme.cardTheme.color, colors.cardSurface);
      final ink = tester.widget<Ink>(
        find
            .descendant(of: find.byType(Card).first, matching: find.byType(Ink))
            .first,
      );
      expect((ink.decoration as BoxDecoration?)?.gradient, isNull);
      expect(tester.takeException(), isNull);
    }
  });
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final light = a > b ? a : b;
  final dark = a > b ? b : a;
  return (light + 0.05) / (dark + 0.05);
}
