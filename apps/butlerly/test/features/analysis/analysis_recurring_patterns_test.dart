import 'package:butlerly/features/analysis/presentation/widgets/analysis_recurring_patterns.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders durable recurring status and change actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AnalysisRecurringPatterns(
            patterns: Future.value(
              ApplicationSuccess<List<RecurringPattern>>([
                _pattern.applyDecision(
                  RecurringPatternDecision(
                    id: 'decision-1',
                    patternKey: 'merchant|expense|USD||',
                    status: RecurringPatternDecisionStatus.confirmed,
                    cadence: RecurringPatternDecisionCadence.monthly,
                    intervalDays: 30,
                    expectedAmount: DecimalValue.fromParts(
                      coefficient: BigInt.from(1000),
                      scale: 2,
                    ),
                    createdAt: DateTime.utc(2026, 1, 1),
                    updatedAt: DateTime.utc(2026, 1, 2),
                  ),
                ),
              ]),
            ),
            masterData: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Confirm'), findsNothing);
    expect(find.widgetWithText(TextButton, 'Reject'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Correct'), findsOneWidget);
    expect(find.textContaining('Expected amount'), findsOneWidget);
    expect(find.textContaining('Next occurrence'), findsOneWidget);
  });

  testWidgets('keeps every recurring detection reachable for review', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: AnalysisRecurringPatterns(
              patterns: Future.value(
                ApplicationSuccess<List<RecurringPattern>>([
                  for (var index = 1; index <= 6; index++) _patternFor(index),
                ]),
              ),
              masterData: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Merchant 6'), findsOneWidget);
  });

  testWidgets('labels an unsupported next occurrence as unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AnalysisRecurringPatterns(
            patterns: Future.value(
              ApplicationSuccess<List<RecurringPattern>>([
                _patternFor(
                  7,
                  latestTransactionDate: '2026-03-01',
                  expectedNextDate: null,
                ),
              ]),
            ),
            masterData: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Next occurrence: Unavailable'), findsOneWidget);
  });
}

final _pattern = _patternFor(1);

RecurringPattern _patternFor(
  int index, {
  String? latestTransactionDate,
  String? expectedNextDate = '2026-04-01',
}) => RecurringPattern(
  id: 'recurring-$index',
  patternKey: 'merchant-$index|expense|USD||',
  transactionIds: [TransactionId('transaction-1')],
  direction: TransactionDirection.expense,
  currency: CurrencyCode('USD'),
  cadence: RecurringCadence.monthly,
  intervalDays: 30,
  amountMinimum: DecimalValue.parse('10'),
  amountMaximum: DecimalValue.parse('10'),
  expectedAmount: DecimalValue.parse('10'),
  confidence: .9,
  evidence: const ['3 canonical transactions'],
  status: RecurringPatternStatus.detected,
  counterparty: 'Merchant $index',
  latestTransactionDate: latestTransactionDate,
  expectedNextDate: expectedNextDate,
);
