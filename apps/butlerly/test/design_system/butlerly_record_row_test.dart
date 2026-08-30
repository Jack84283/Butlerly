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

  testWidgets('common item renders compact three-line expense metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyTransactionListItem(
            title: 'Safeway Store',
            subtitle: 'Food & Dining · Groceries · Personal',
            meta: 'Aug 14, 2026',
            amount: '42.19',
            currency: 'USD',
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(find.text('42.19 USD'), findsOneWidget);
    expect(find.text('Safeway Store'), findsOneWidget);
    expect(find.text('Food & Dining · Groceries · Personal'), findsOneWidget);
    expect(find.text('Aug 14, 2026'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('income uses upward direction and list dividers omit the last', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyTransactionList(
            children: const [
              ButlerlyTransactionListItem(
                title: 'Salary',
                amount: '100.00',
                currency: 'USD',
                isIncome: true,
              ),
              ButlerlyTransactionListItem(
                title: 'Coffee',
                amount: '4.00',
                currency: 'USD',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
  });
}
