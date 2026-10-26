import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../analysis/dataset_builder.dart';
import '../result/application_result.dart';

/// Monthly budget spending is derived from canonical economic transactions,
/// not from optional/disabled analysis rules or the presence of grouped metrics.
final class CanonicalBudgetActuals {
  const CanonicalBudgetActuals(this.byBudgetId);

  /// A null amount means the source cannot support a safe comparison.
  /// Zero is an exact, verified absence of matching expenses.
  final Map<String, DecimalValue?> byBudgetId;
}

final class CalculateCanonicalBudgetActuals {
  const CalculateCanonicalBudgetActuals(this.datasetBuilder);

  final AnalysisDatasetBuilder datasetBuilder;

  Future<ApplicationResult<CanonicalBudgetActuals>> call({
    required DateTime month,
    required List<Budget> budgets,
  }) => runApplication('calculate monthly budget actuals', () async {
    final currency = await datasetBuilder.baseCurrency();
    if (currency == null) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'Budget calculation requires configured financial preferences.',
      );
    }
    final timeZoneId = await datasetBuilder.timeZoneId();
    final first = DateTime.utc(month.year, month.month);
    final last = DateTime.utc(month.year, month.month + 1, 0);
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    final context = AnalysisContext(
      period: AnalysisPeriod(
        startDate: date(first),
        endDate: date(last),
        timeZoneId: timeZoneId,
      ),
      datasetMode: DatasetMode.allEligible,
      currencyBasis: CurrencyBasis.baseCurrency,
      baseCurrency: currency,
      periodType: 'selected_period',
    );
    final result = await datasetBuilder.build(context);
    if (result is! ApplicationDatasetSuccess) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'Canonical transaction data is unavailable for the budget month.',
      );
    }
    return calculateBudgetActualsFromDataset(result.dataset, budgets);
  });
}

/// Pure calculation shared by the application use case and regression tests.
/// The selected-period rows already have financial dates, legacy category
/// normalization, reconciliation and duplicate decisions applied by the
/// canonical dataset builder.
CanonicalBudgetActuals calculateBudgetActualsFromDataset(
  AnalysisDataset dataset,
  List<Budget> budgets,
) {
  final transactions = dataset.primaryTransactionsByPeriod['selected_period'];
  final base = dataset.context.baseCurrency?.value;
  if (transactions == null || base == null) {
    return CanonicalBudgetActuals({
      for (final budget in budgets) budget.id: null,
    });
  }
  final expenses = transactions
      .where((transaction) => transaction.direction == TransactionDirection.expense)
      .toList(growable: false);
  final values = <String, DecimalValue?>{};

  for (final budget in budgets) {
    final validScope = switch (budget.scope) {
      'overall' => budget.scopeId == null,
      'merchant' || 'category' || 'subcategory' => budget.scopeId != null,
      _ => false,
    };
    if (!validScope) {
      values[budget.id] = null;
      continue;
    }

    final relevant = expenses.where((transaction) => switch (budget.scope) {
      'merchant' => transaction.merchantId?.value == budget.scopeId,
      'category' => transaction.categoryId?.value == budget.scopeId,
      'subcategory' => transaction.subcategoryId?.value == budget.scopeId,
      _ => true,
    });
    var total = DecimalValue.parse('0');
    var unavailable = false;
    for (final transaction in relevant) {
      final amount = budget.currency == base
          ? transaction.money.currency.value == base
              ? transaction.money.amount
              : transaction.normalizedMoney?.currency.value == base
              ? transaction.normalizedMoney!.amount
              : null
          : transaction.money.currency.value == budget.currency
              ? transaction.money.amount
              : null;
      if (amount == null) {
        // A matching expense in another currency without conversion cannot
        // silently disappear or be reported as zero.
        unavailable = true;
        break;
      }
      total = total.add(amount);
    }
    values[budget.id] = unavailable ? null : total;
  }
  return CanonicalBudgetActuals(Map.unmodifiable(values));
}
