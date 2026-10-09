import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dark mode matches the approved navy background specification', () {
    final colors = AppTheme.dark.extension<ButlerlySemanticColors>()!;
    expect(colors.background, const Color(0xFF0B162A));
    expect(colors.cardSurface, const Color(0xFF1A2336));
    expect(colors.surface, const Color(0xFF1F2534));
    expect(colors.elevatedSurface, const Color(0xFF2A2D40));
    expect(colors.subtleSurface, const Color(0xFF0B162A));
    expect(colors.overlaySurface, const Color(0xFF1F2534));
    expect(colors.sheetSurface, const Color(0xFF121A2B));
    expect(colors.footerSurface, const Color(0xFF121A2B));
    expect(colors.primaryText, const Color(0xFFF6F7F8));
    expect(colors.secondaryText, const Color(0xFFB9BDC7));
    expect(colors.tertiaryText, const Color(0xFF8D939E));
    expect(colors.cardDivider, const Color(0xFF383C44));
    expect(colors.border, const Color(0xFF383C44));
  });

  test('light mode matches the approved off-white background specification', () {
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
