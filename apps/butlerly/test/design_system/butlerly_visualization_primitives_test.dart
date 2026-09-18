import 'package:butlerly/design_system/components/butlerly_visualization_primitives.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(
    Widget child, {
    double textScale = 1,
    double width = 320,
  }) => MaterialApp(
    theme: ThemeData(extensions: const [ButlerlySemanticColors.light]),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: SingleChildScrollView(child: SizedBox(width: width, child: child)),
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
    var tapped = -1;
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
          onDatumTap: (index) => tapped = index,
        ),
        width: 600,
      ),
    );
    await tester.pumpAndSettle();

    final chart = find.byType(CustomPaint).first;
    expect(tester.getCenter(chart).dx, closeTo(300, 1));
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('600.00 USD'), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('400.00 USD'), findsOneWidget);

    await tester.tap(find.text('Food'));
    expect(tapped, 0);
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
