import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/theme/butlerly_surface_gradients.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dark mode uses the refined near-black semantic palette', () {
    final colors = AppTheme.dark.extension<ButlerlySemanticColors>()!;
    expect(colors.background, const Color(0xFF030405));
    expect(colors.cardSurface, const Color(0xFF141516));
    expect(colors.surface, const Color(0xFF282B30));
    expect(colors.elevatedSurface, const Color(0xFF2F3339));
    expect(colors.primaryText, const Color(0xFFF6F7F8));
    expect(colors.secondaryText, const Color(0xFFB9BDC7));
    expect(colors.tertiaryText, const Color(0xFF8D939E));
    expect(colors.cardDivider, const Color(0xFF2A2E34));
    expect(colors.border, const Color(0xFF626974));
  });

  test('light mode matches the approved darker gray-blue palette', () {
    final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
    expect(colors.background, const Color(0xFFE6E9EF));
    expect(colors.cardSurface, const Color(0xFFD6DBE3));
    expect(colors.surface, const Color(0xFFC8CED8));
    expect(colors.subtleSurface, const Color(0xFFC8CED8));
    expect(colors.elevatedSurface, const Color(0xFFBCC4CF));
    expect(colors.primaryText, const Color(0xFF14171D));
    expect(colors.secondaryText, const Color(0xFF4B5563));
    expect(colors.tertiaryText, const Color(0xFF6B7280));
    expect(colors.cardDivider, const Color(0xFFAEB6C2));
    expect(colors.border, const Color(0xFFAEB6C2));
    expect(colors.brand, const Color(0xFF7A1E3A));
    expect(
      colors.background.computeLuminance(),
      greaterThan(colors.cardSurface.computeLuminance()),
    );
    expect(
      colors.cardSurface.computeLuminance(),
      greaterThan(colors.surface.computeLuminance()),
    );
    expect(
      colors.surface.computeLuminance(),
      greaterThan(colors.elevatedSurface.computeLuminance()),
    );
  });

  test('footer icon accents have accessible contrast in both modes', () {
    for (final theme in ButlerlyColorTheme.values) {
      final lightTheme = AppTheme.lightFor(theme);
      final darkTheme = AppTheme.darkFor(theme);
      final light = lightTheme.extension<ButlerlySemanticColors>()!;
      final dark = darkTheme.extension<ButlerlySemanticColors>()!;

      if (theme == ButlerlyColorTheme.butlerRed) {
        expect(light.navigationSelectedIcon, const Color(0xFF7A1E3A));
        expect(dark.navigationSelectedIcon, const Color(0xFFBD6384));
      }
      expect(
        _contrast(light.navigationSelectedIcon, light.elevatedSurface),
        greaterThanOrEqualTo(3),
      );
      expect(
        _contrast(dark.navigationSelectedIcon, dark.elevatedSurface),
        greaterThanOrEqualTo(3),
      );
    }
  });

  testWidgets('light cards use gradients and dark cards remain flat', (
    tester,
  ) async {
    Widget card() => const Scaffold(
      body: Center(child: ButlerlyCard(child: Text('Sample card'))),
    );

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(MaterialApp(theme: theme, home: card()));
      final widget = tester.widget<Card>(find.byType(Card).first);
      final colors = theme.extension<ButlerlySemanticColors>()!;
      expect(widget.color ?? theme.cardTheme.color, colors.cardSurface);
      final ink = tester.widget<Ink>(
        find.descendant(
          of: find.byType(Card).first,
          matching: find.byType(Ink),
        ).first,
      );
      final gradient = (ink.decoration as BoxDecoration?)?.gradient;
      expect(
        gradient,
        theme.brightness == Brightness.light
            ? ButlerlySurfaceGradients.lightCard
            : null,
      );
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
