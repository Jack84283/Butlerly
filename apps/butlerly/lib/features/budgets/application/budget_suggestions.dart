import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// A suggestion based on three *complete* calendar months of canonical
/// analysis results, not raw transaction records.
final class BudgetSuggestion {
  const BudgetSuggestion({
    required this.amount,
    required this.currency,
    required this.months,
  });

  final String amount;
  final String currency;
  final int months;
}

Future<BudgetSuggestion?> suggestMonthlyBudget({
  required FinanceServices finance,
  required String scope,
  required String? scopeId,
  required String currency,
  DateTime? now,
}) async {
  final calculate = finance.calculateAnalysisOverview;
  if (calculate == null || (scope != 'overall' && scopeId == null)) return null;

  final today = now ?? DateTime.now();
  final amounts = <double>[];

  for (var monthsAgo = 1; monthsAgo <= 3; monthsAgo++) {
    final first = DateTime(today.year, today.month - monthsAgo, 1);
    final last = DateTime(today.year, today.month - monthsAgo + 1, 0);
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    final period = await calculate.contextForDates(
      startDate: date(first),
      endDate: date(last),
    );
    if (period is! ApplicationSuccess<AnalysisContext>) return null;
    final result = await calculate(period.value);
    if (result is! ApplicationSuccess<List<RuleExecutionResult>>) return null;

    final overview = AnalysisOverview.fromResults(result.value);
    final AnalysisMetric? metric = switch (scope) {
      'overall' => overview.spending,
      'category' =>
        overview.categories
            .where((value) => value.dimension == scopeId)
            .firstOrNull,
      'subcategory' =>
        overview.subcategories
            .where((value) => value.dimension == scopeId)
            .firstOrNull,
      'merchant' =>
        overview.merchants
            .where((value) => value.dimension == scopeId)
            .firstOrNull,
      _ => null,
    };
    if (metric == null ||
        metric.currency?.value != currency ||
        metric.availability != AnalysisDataAvailability.sufficient ||
        metric.qualityIssues.isNotEmpty) {
      return null;
    }
    final amount = double.tryParse(metric.value.toString());
    if (amount == null || !amount.isFinite || amount < 0) return null;
    amounts.add(amount);
  }

  if (amounts.length != 3) return null;
  final average = amounts.reduce((a, b) => a + b) / 3;
  if (!average.isFinite || average <= 0) return null;
  return BudgetSuggestion(
    amount: average.toStringAsFixed(2),
    currency: currency,
    months: 3,
  );
}
