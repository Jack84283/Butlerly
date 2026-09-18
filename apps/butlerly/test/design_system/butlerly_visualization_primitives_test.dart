import 'package:butlerly/design_system/components/butlerly_visualization_primitives.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child, {double textScale = 1}) => MaterialApp(
    theme: ThemeData(extensions: const [ButlerlySemanticColors.light]),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(body: SizedBox(width: 320, child: child)),
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
            ButlerlyChartDatum(label: 'Jan', value: 10),
            ButlerlyChartDatum(label: 'Feb', value: 20),
          ],
          valueLabel: (value) => '$value USD',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Jan: 10.0 USD, Feb: 20.0 USD'), findsOneWidget);
  });
}
