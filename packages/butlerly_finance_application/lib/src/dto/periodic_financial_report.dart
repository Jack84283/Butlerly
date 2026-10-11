import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'analysis_overview.dart';
import 'recurring_pattern.dart';
import '../result/application_result.dart';

/// The report projection keeps actual canonical analysis separate from
/// derived recurring predictions. Expected future occurrences never inflate
/// actual totals.
final class PeriodicFinancialReport {
  const PeriodicFinancialReport({
    required this.context,
    required this.results,
    required this.overview,
    required this.recurringPatternsResult,
  });

  final AnalysisContext context;
  final List<RuleExecutionResult> results;
  final AnalysisOverview overview;
  final ApplicationResult<List<RecurringPattern>> recurringPatternsResult;

  List<RecurringPattern> get recurringPatterns =>
      recurringPatternsResult is ApplicationSuccess<List<RecurringPattern>>
      ? (recurringPatternsResult as ApplicationSuccess<List<RecurringPattern>>)
            .value
      : const [];

  List<AnalysisMetric> get merchantBreakdown => overview.merchants;

  List<AnalysisMetric> get categoryBreakdown => overview.categories;

  List<AnalysisMetric> get subcategoryBreakdown => overview.subcategories;
}
