import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final usd = CurrencyCode('USD');
  final eur = CurrencyCode('EUR');
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-10-01',
      endDate: '2026-10-31',
      timeZoneId: 'America/Los_Angeles',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: usd,
    periodType: 'selected_period',
  );

  Budget budget(String scope, String? scopeId, {String currency = 'USD'}) =>
      Budget(
        id: '$scope-${scopeId ?? 'all'}',
        scope: scope,
        scopeId: scopeId,
        currency: currency,
        amount: '150.00',
      );

  AnalysisEconomicTransaction row(
    String id,
    String amount, {
    TransactionDirection direction = TransactionDirection.expense,
    String currency = 'USD',
    String date = '2026-10-18',
    String? merchant,
    String? category,
    String? subcategory,
    Money? normalized,
  }) => AnalysisEconomicTransaction(
    id: TransactionId(id),
    money: Money(
      amount: DecimalValue.parse(amount),
      currency: CurrencyCode(currency),
    ),
    direction: direction,
    transactionDate: date,
    merchantId: merchant == null ? null : MerchantId(merchant),
    categoryId: category == null ? null : CategoryId(category),
    subcategoryId: subcategory == null ? null : CategoryId(subcategory),
    normalizedMoney: normalized,
  );

  AnalysisDataset dataset(List<AnalysisEconomicTransaction> selected) =>
      AnalysisDataset(
        context: context,
        transactions: selected,
        primaryTransactionsByPeriod: {'selected_period': selected},
      );

  test('new merchant budget is zero even with no analysis rules or expenses', () {
    final budgets = [
      budget('merchant', 'merchant-new'),
      budget('overall', null),
      budget('category', 'category-new'),
      budget('subcategory', 'sub-new'),
    ];
    final result = calculateBudgetActualsFromDataset(dataset([]), budgets);
    for (final item in budgets) {
      expect(result.byBudgetId[item.id], DecimalValue.parse('0'));
    }
  });

  test('zero-spending new merchant is not confused with other merchants', () {
    final selected = [
      row('one', '25.50', merchant: 'older-merchant'),
      row('two', '9.25', merchant: 'older-merchant'),
    ];
    final budgets = [
      budget('merchant', 'new-merchant'),
      budget('merchant', 'older-merchant'),
      budget('overall', null),
    ];
    final amounts = calculateBudgetActualsFromDataset(
      dataset(selected),
      budgets,
    ).byBudgetId;
    expect(amounts[budgets[0].id], DecimalValue.parse('0'));
    expect(amounts[budgets[1].id], DecimalValue.parse('34.75'));
    expect(amounts[budgets[2].id], DecimalValue.parse('34.75'));
  });

  test('category, subcategory and merchant budget actuals use exact IDs', () {
    final values = [
      row('a', '42.10', merchant: 'merchant-a',
          category: 'category-a', subcategory: 'sub-a'),
      row('b', '7.23', merchant: 'merchant-b',
          category: 'category-a', subcategory: 'sub-b'),
    ];
    final budgets = [
      budget('category', 'category-a'),
      budget('subcategory', 'sub-a'),
      budget('merchant', 'merchant-b'),
    ];
    final amounts = calculateBudgetActualsFromDataset(
      dataset(values),
      budgets,
    ).byBudgetId;
    expect(amounts[budgets[0].id], DecimalValue.parse('49.33'));
    expect(amounts[budgets[1].id], DecimalValue.parse('42.10'));
    expect(amounts[budgets[2].id], DecimalValue.parse('7.23'));
  });

  test('income, transfer and refunds do not count as spending', () {
    final selected = [
      row('expense', '10'),
      row('income', '20', direction: TransactionDirection.income),
      row('transfer', '30', direction: TransactionDirection.transfer),
      row('refund', '40', direction: TransactionDirection.refund),
    ];
    final item = budget('overall', null);
    final actual = calculateBudgetActualsFromDataset(
      dataset(selected), [item],
    ).byBudgetId[item.id];
    expect(actual, DecimalValue.parse('10'));
  });

  test('normalized FX is used in a matching base-currency budget', () {
    final selected = [
      row('foreign', '10', currency: 'EUR', merchant: 'market',
          normalized: Money(amount: DecimalValue.parse('11.50'), currency: usd)),
    ];
    final item = budget('merchant', 'market');
    expect(
      calculateBudgetActualsFromDataset(
        dataset(selected), [item],
      ).byBudgetId[item.id],
      DecimalValue.parse('11.5'),
    );
  });

  test('matching expense without FX stays unavailable instead of zero', () {
    final selected = [row('foreign', '10', currency: 'EUR', merchant: 'market')];
    final affected = budget('merchant', 'market');
    final unrelated = budget('merchant', 'new-merchant');
    final amounts = calculateBudgetActualsFromDataset(
      dataset(selected), [affected, unrelated],
    ).byBudgetId;
    expect(amounts[affected.id], isNull);
    expect(amounts[unrelated.id], DecimalValue.parse('0'));
  });

  test('non-base budget currency uses original amounts when compatible', () {
    final item = budget('merchant', 'market', currency: eur.value);
    final selected = [
      row('foreign', '7.95', merchant: 'market', currency: eur.value),
    ];
    expect(
      calculateBudgetActualsFromDataset(
        dataset(selected), [item],
      ).byBudgetId[item.id],
      DecimalValue.parse('7.95'),
    );
    expect(
      calculateBudgetActualsFromDataset(
        dataset([row('usd', '7.95', merchant: 'market')]), [item],
      ).byBudgetId[item.id],
      isNull,
    );
  });

  test('absence of a selected-month dataset never fabricates zero', () {
    final item = budget('merchant', 'new-merchant');
    final missing = AnalysisDataset(
      context: context,
      transactions: const [],
    );
    expect(
      calculateBudgetActualsFromDataset(missing, [item]).byBudgetId[item.id],
      isNull,
    );
  });
}
