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

  test('light mode uses the darker gray-blue semantic palette', () {
    final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
    expect(colors.background, const Color(0xFFE6E9EF));
    expect(colors.cardSurface, const Color(0xFFD6DBE3));
    expect(colors.surface, const Color(0xFFC8CED8));
    expect(colors.elevatedSurface, const Color(0xFFBCC4CF));
    expect(colors.primaryText, const Color(0xFF14171D));
    expect(colors.secondaryText, const Color(0xFF4B5563));
    expect(colors.tertiaryText, const Color(0xFF6B7280));
    expect(colors.cardDivider, const Color(0xFFAEB6C2));
    expect(colors.border, const Color(0xFFAEB6C2));
    expect(colors.brand, const Color(0xFF7A1E3A));
  });

  testWidgets('light cards have a subtle gradient; dark cards remain flat', (
    tester,
  ) async {
    Widget card() => const Scaffold(
      body: Center(child: ButlerlyCard(child: Text('Sample card'))),
    );

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: card()));
    var ink = tester.widget<Ink>(find.byType(Ink).first);
    expect(
      (ink.decoration! as BoxDecoration).gradient,
      ButlerlySurfaceGradients.lightCard,
    );

    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: card()));
    ink = tester.widget<Ink>(find.byType(Ink).first);
    expect(ink.decoration, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('light canvas uses a gradient; dark canvas stays flat', (
    tester,
  ) async {
    Widget canvas() => const Scaffold(
      body: ButlerlyContentCanvas(
        canvasKey: ValueKey('test-canvas'),
        child: SizedBox.expand(),
      ),
    );

    await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: canvas()));
    var decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey('test-canvas')),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    expect(
      (decorated.decoration as BoxDecoration).gradient,
      ButlerlySurfaceGradients.lightPage,
    );

    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: canvas()));
    decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byKey(const ValueKey('test-canvas')),
        matching: find.byType(DecoratedBox),
      ).first,
    );
    expect((decorated.decoration as BoxDecoration).gradient, isNull);
    expect(tester.takeException(), isNull);
  });
}
