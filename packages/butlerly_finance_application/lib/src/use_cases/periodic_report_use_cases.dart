import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../dto/periodic_financial_report.dart';
import '../dto/analysis_overview.dart';
import '../result/application_result.dart';
import 'analysis_use_cases.dart';
import 'recurring_use_cases.dart';

/// Builds the offline periodic report from the same Analysis engine used by
/// Analysis and Insights, then attaches recurring candidates as a separate
/// derived section.
final class CalculatePeriodicFinancialReport {
  const CalculatePeriodicFinancialReport(this.analysis, this.recurring);

  final CalculateAnalysisOverview analysis;
  final DetectRecurringPatterns recurring;

  Future<ApplicationResult<PeriodicFinancialReport>> call(
    AnalysisContext context,
  ) => runApplication('calculate periodic financial report', () async {
    final results = await analysis.call(context);
    if (results is! ApplicationSuccess<List<RuleExecutionResult>>) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'periodic report analysis is unavailable',
      );
    }
    final patterns = await recurring(timeZoneId: context.period.timeZoneId);
    return PeriodicFinancialReport(
      context: context,
      results: results.value,
      overview: AnalysisOverview.fromResults(results.value),
      recurringPatternsResult: patterns,
    );
  });
}
