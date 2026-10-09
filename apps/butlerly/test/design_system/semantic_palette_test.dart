import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
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

  test('light mode uses the four-level solid tonal palette', () {
    final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
    expect(colors.background, const Color(0xFFF2F3F9));
    expect(colors.cardSurface, const Color(0xFFEEF1F5));
    expect(colors.surface, const Color(0xFFE7EBF1));
    expect(colors.subtleSurface, const Color(0xFFE7EBF1));
    expect(colors.elevatedSurface, const Color(0xFFE0E5EC));
    expect(colors.primaryText, const Color(0xFF17191F));
    expect(colors.secondaryText, const Color(0xFF383838));
    expect(colors.tertiaryText, const Color(0xFF787E89));
    expect(colors.cardDivider, const Color(0xFFD8DDE6));
    expect(colors.border, const Color(0xFFD8DDE6));
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

  test('selected footer icons have one accessible color in both modes', () {
    for (final theme in ButlerlyColorTheme.values) {
      final light = AppTheme.lightFor(theme).extension<ButlerlySemanticColors>()!;
      final dark = AppTheme.darkFor(theme).extension<ButlerlySemanticColors>()!;

      expect(light.navigationSelectedIcon, dark.navigationSelectedIcon);
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

  testWidgets('light and dark cards use solid surfaces', (tester) async {
    Widget card() => const Scaffold(
      body: Center(child: ButlerlyCard(child: Text('Sample card'))),
    );

    for (final theme in [AppTheme.light, AppTheme.dark]) {
      await tester.pumpWidget(MaterialApp(theme: theme, home: card()));
      final widget = tester.widget<Card>(find.byType(Card).first);
      final colors = theme.extension<ButlerlySemanticColors>()!;
      expect(widget.color ?? theme.cardTheme.color, colors.cardSurface);
      expect(
        find.descendant(
          of: find.byType(Card).first,
          matching: find.byType(Ink),
        ),
        findsNothing,
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
