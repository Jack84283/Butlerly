import 'dart:io';

import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = RestrictedRuleParser();
  const validator = RuleDefinitionValidator();

  AnalysisRuleDefinition loadRule(String path) {
    final source = File(path).readAsStringSync();
    final parsed = parser.parse(source);
    expect(parsed.isValid, isTrue, reason: parsed.diagnostics.toString());
    final validated = validator.validate(parsed.document!);
    expect(validated.diagnostics, isEmpty, reason: validated.diagnostics.toString());
    expect(validated.definition, isNotNull);
    return validated.definition!;
  }

  final expenseRule = loadRule('assets/analysis_rules/metrics/ANL-R001.yaml');
  final incomeRule = loadRule('assets/analysis_rules/metrics/ANL-R002.yaml');
  final savingsRule = loadRule('assets/analysis_rules/insights/ANL-R029.yaml');
  final definitions = [expenseRule, incomeRule, savingsRule];

  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-09-01',
      endDate: '2026-09-10',
      timeZoneId: 'America/Los_Angeles',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: CurrencyCode('USD'),
    periodType: 'selected_period',
  );

  AnalysisEconomicTransaction transaction(
    String id,
    String amount,
    TransactionDirection direction, {
    required String date,
  }) => AnalysisEconomicTransaction(
    id: TransactionId(id),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode('USD'),
    ),
    normalizedMoney: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode('USD'),
    ),
    direction: direction,
    transactionDate: date,
  );

  AnalysisDataset dataset({
    required String currentIncome,
    required String currentExpense,
    String? baselineIncome,
    String? baselineExpense,
  }) {
    final current = [
      transaction(
        'current-income',
        currentIncome,
        TransactionDirection.income,
        date: '2026-09-05',
      ),
      transaction(
        'current-expense',
        currentExpense,
        TransactionDirection.expense,
        date: '2026-09-06',
      ),
    ];
    final baseline = baselineIncome == null || baselineExpense == null
        ? <AnalysisEconomicTransaction>[]
        : [
            transaction(
              'baseline-income',
              baselineIncome,
              TransactionDirection.income,
              date: '2026-08-05',
            ),
            transaction(
              'baseline-expense',
              baselineExpense,
              TransactionDirection.expense,
              date: '2026-08-06',
            ),
          ];
    return AnalysisDataset(
      context: context,
      transactions: current,
      primaryTransactionsByPeriod: {'selected_period': current},
      baselineTransactions: baseline,
      baselineTransactionsByPeriod: {'selected_period': baseline},
    );
  }

  RuleExecutionResult savingsResult(AnalysisDataset source) =>
      const AnalysisRuleEngine()
          .execute(dataset: source, definitions: definitions)
          .firstWhere((result) => result.rule.identity.value == 'ANL-R029');

  test('bundled R029 requires 20 percent when prior savings are positive', () {
    final below = savingsResult(
      dataset(
        currentIncome: '1020',
        currentExpense: '800',
        baselineIncome: '1000',
        baselineExpense: '800',
      ),
    );
    expect(below.comparison?.baselineValue, DecimalValue.parse('200'));
    expect(below.comparison?.percentageChange, DecimalValue.parse('10'));
    expect(below.finding, isNull);

    final boundary = savingsResult(
      dataset(
        currentIncome: '1040',
        currentExpense: '800',
        baselineIncome: '1000',
        baselineExpense: '800',
      ),
    );
    expect(boundary.comparison?.percentageChange, DecimalValue.parse('20'));
    expect(boundary.finding, isNotNull);
  });

  test('bundled R029 treats zero to positive savings as improvement', () {
    final result = savingsResult(
      dataset(
        currentIncome: '1000',
        currentExpense: '900',
        baselineIncome: '1000',
        baselineExpense: '1000',
      ),
    );
    expect(result.comparison?.baselineValue, DecimalValue.parse('0'));
    expect(result.comparison?.percentageChange, isNull);
    expect(result.finding, isNotNull);
  });

  test('bundled R029 treats a smaller deficit as improvement', () {
    final result = savingsResult(
      dataset(
        currentIncome: '900',
        currentExpense: '1000',
        baselineIncome: '800',
        baselineExpense: '1000',
      ),
    );
    expect(result.comparison?.baselineValue, DecimalValue.parse('-200'));
    expect(result.comparison?.currentValue, DecimalValue.parse('-100'));
    expect(result.finding, isNotNull);
  });

  test('bundled R029 treats deficit to surplus as improvement', () {
    final result = savingsResult(
      dataset(
        currentIncome: '1100',
        currentExpense: '1000',
        baselineIncome: '800',
        baselineExpense: '1000',
      ),
    );
    expect(result.comparison?.baselineValue, DecimalValue.parse('-200'));
    expect(result.comparison?.currentValue, DecimalValue.parse('100'));
    expect(result.finding, isNotNull);
  });
}
