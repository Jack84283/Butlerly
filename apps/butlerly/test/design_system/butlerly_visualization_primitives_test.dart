import 'package:butlerly/design_system/components/butlerly_visualization_primitives.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chart palette provides at least 40 unique colors', () {
    expect(
      ButlerlyChartColors.categoryPalette.length,
      greaterThanOrEqualTo(40),
    );
    expect(
      ButlerlyChartColors.categoryPalette.toSet().length,
      ButlerlyChartColors.categoryPalette.length,
    );
  });

  test('existing category IDs keep their legacy base colors', () {
    expect(ButlerlyChartColors.category('food'), const Color(0xFF5E3C99));
    expect(ButlerlyChartColors.category('housing'), const Color(0xFFB35806));
    expect(ButlerlyChartColors.category('category-1'), const Color(0xFF009E73));
    expect(
      ButlerlyChartColors.category('uncategorized'),
      const Color(0xFF7570B3),
    );
    expect(ButlerlyChartColors.category('other'), const Color(0xFF1B9E77));
  });

  test('multi-category collision mapping stays within legacy palette', () {
    final assigned = ButlerlyChartColors.forCategories([
      'collision-15',
      'collision-26',
    ]);

    expect(assigned['collision-15'], const Color(0xFF4D9221));
    expect(assigned['collision-26'], const Color(0xFF0072B2));
  });

  test('donut color resolver removes duplicate and near-duplicate colors', () {
    const repeated = Color(0xFF0072B2);
    const nearRepeated = Color(0xFF0173B3);
    final resolved = ButlerlyChartColors.distinctSeriesColors([
      repeated,
      repeated,
      nearRepeated,
      null,
      null,
      null,
    ]);

    expect(resolved.toSet().length, resolved.length);
    expect(resolved.first, repeated);
    expect(resolved[1], isNot(repeated));
    expect(resolved[2], isNot(nearRepeated));
  });

  test('donut color resolver keeps 40 slices unique', () {
    final resolved = ButlerlyChartColors.distinctSeriesColors(
      List<Color?>.filled(40, null),
    );
    expect(resolved.length, 40);
    expect(resolved.toSet().length, 40);
  });

  Widget app(Widget child, {double textScale = 1, double width = 320}) =>
      MaterialApp(
        theme: ThemeData(extensions: const [ButlerlySemanticColors.light]),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(width: width, child: child),
            ),
          ),
        ),
      );

  testWidgets('donut stacks safely at narrow width and large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        ButlerlyDonutVisualization(
          density: ButlerlyVisualizationDensity.regular,
          data: const [
            ButlerlyChartDatum(label: 'Food & Dining', value: 60),
            ButlerlyChartDatum(label: 'Housing', value: 40),
          ],
          valueLabel: (value, total) => '${value / total * 100}%',
        ),
        textScale: 3,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Food & Dining'), findsOneWidget);
    expect(find.text('Housing'), findsOneWidget);
  });

  testWidgets('donut can force centered chart with detail rows below', (
    tester,
  ) async {
    ButlerlyChartDatum? tapped;
    await tester.pumpWidget(
      app(
        ButlerlyDonutVisualization(
          density: ButlerlyVisualizationDensity.regular,
          legendBelow: true,
          data: const [
            ButlerlyChartDatum(
              label: 'Food',
              value: 60,
              valueLabel: '600.00 USD',
            ),
            ButlerlyChartDatum(
              label: 'Rent',
              value: 40,
              valueLabel: '400.00 USD',
            ),
          ],
          valueLabel: (value, total) => '${value / total * 100}%',
          onDatumTap: (datum) => tapped = datum,
        ),
        width: 600,
      ),
    );
    await tester.pumpAndSettle();

    final chart = find.byKey(const ValueKey('butlerly-donut-chart'));
    final visualization = find.byType(ButlerlyDonutVisualization);
    expect(
      tester.getCenter(chart).dx,
      closeTo(tester.getCenter(visualization).dx, 1),
    );
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('600.00 USD'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('400.00 USD'), findsOneWidget);

    await tester.tap(find.text('Food'));
    expect(tapped?.label, 'Food');
  });

  testWidgets('donut keeps a single positive datum visible', (tester) async {
    await tester.pumpWidget(
      app(
        ButlerlyDonutVisualization(
          data: const [
            ButlerlyChartDatum(
              label: 'Dining',
              value: 100,
              valueLabel: '100 USD',
            ),
          ],
          valueLabel: (value, total) => '${value / total * 100}%',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dining'), findsOneWidget);
    expect(find.text('100 USD'), findsOneWidget);
    expect(find.bySemanticsLabel('Dining: 100 USD'), findsOneWidget);
  });

  testWidgets('horizontal value row stacks without overflow at large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const ButlerlyHorizontalValueRow(
          label: 'Previous equivalent period',
          valueLabel: '12,345.67 USD',
          fraction: .75,
          color: Colors.blue,
        ),
        textScale: 3,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Previous equivalent period'), findsOneWidget);
    expect(find.text('12,345.67 USD'), findsOneWidget);
  });

  testWidgets('trend exposes a textual semantic alternative', (tester) async {
    await tester.pumpWidget(
      app(
        ButlerlyTrendVisualization(
          data: const [
            ButlerlyChartDatum(label: 'Jan', value: 10, valueLabel: '10.0 USD'),
            ButlerlyChartDatum(label: 'Feb', value: 20, valueLabel: '20.0 USD'),
          ],
          valueLabel: (value) => '$value USD',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel('Jan: 10.0 USD, Feb: 20.0 USD'),
      findsOneWidget,
    );
  });
}
