import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// A monthly budget's actual spending, using the same canonical metrics as
/// Home and Analysis. Null means the amount cannot be safely calculated.
final class MonthlyBudgetActual {
  const MonthlyBudgetActual({required this.spent, this.metric});

  final double? spent;
  final AnalysisMetric? metric;
}

/// Grouped analysis dimensions include a measure suffix (for example,
/// merchant-id:amount). Compare their raw identity with the budget scope ID.
MonthlyBudgetActual resolveMonthlyBudgetActual(
  Budget budget,
  AnalysisOverview overview,
) {
  final AnalysisMetric? metric = switch (budget.scope) {
    'overall' => overview.spending,
    'category' => _metricFor(overview.categories, budget.scopeId),
    'subcategory' => _metricFor(overview.subcategories, budget.scopeId),
    'merchant' => _metricFor(overview.merchants, budget.scopeId),
    _ => null,
  };

  if (metric != null) {
    final currency =
        metric.currency?.value ?? metric.context.baseCurrency?.value;
    if (currency != budget.currency ||
        metric.availability == AnalysisDataAvailability.insufficient) {
      return const MonthlyBudgetActual(spent: null);
    }
    if (metric.availability == AnalysisDataAvailability.empty) {
      return MonthlyBudgetActual(spent: 0, metric: metric);
    }
    final spent = double.tryParse(metric.value.toString());
    if (spent == null || !spent.isFinite) {
      return const MonthlyBudgetActual(spent: null);
    }
    return MonthlyBudgetActual(spent: spent, metric: metric);
  }

  // The grouped spending rules produce no row for a merchant, category, or
  // subcategory with no eligible transactions in the selected month.
  // This represents zero spending, not unavailable data, provided that the
  // overall monthly spending metric was computed in the same currency.
  if (budget.scope != 'merchant' &&
      budget.scope != 'category' &&
      budget.scope != 'subcategory') {
    return const MonthlyBudgetActual(spent: null);
  }
  final overall = overview.spending;
  final overallCurrency =
      overall?.currency?.value ?? overall?.context.baseCurrency?.value;
  if (overall == null ||
      overallCurrency != budget.currency ||
      overall.availability == AnalysisDataAvailability.insufficient) {
    return const MonthlyBudgetActual(spent: null);
  }
  return const MonthlyBudgetActual(spent: 0);
}

AnalysisMetric? _metricFor(List<AnalysisMetric> metrics, String? scopeId) {
  if (scopeId == null) return null;
  for (final metric in metrics) {
    if (metric.dimension?.split(':').firstOrNull == scopeId) return metric;
  }
  return null;
}
