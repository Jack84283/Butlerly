import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('possible duplicate indicator is accessible and navigable', (
    tester,
  ) async {
    var openedReview = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyRecordRow(
            title: 'Coffee',
            amount: '25.00',
            currency: 'USD',
            possibleDuplicate: true,
            possibleDuplicateLabel: 'Possible duplicate',
            onPossibleDuplicateTap: () => openedReview = true,
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('Possible duplicate'), findsOneWidget);
    expect(find.byTooltip('Possible duplicate'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.warning_amber_rounded));
    expect(openedReview, isTrue);
  });

  testWidgets('non-duplicate rows do not render the indicator', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: ButlerlyRecordRow(
            title: 'Coffee',
            amount: '25.00',
            currency: 'USD',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
  });
}
