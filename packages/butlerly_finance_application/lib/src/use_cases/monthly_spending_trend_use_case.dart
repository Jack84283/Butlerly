import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../analysis/dataset_builder.dart';
import '../result/application_result.dart';
import 'analysis_use_cases.dart';

/// One authoritative monthly spending value for presentation trends.
///
/// [month] is a calendar anchor only. Financial boundaries and timezone
/// semantics remain owned by the analysis period resolver.
final class MonthlySpendingTrendPoint {
  const MonthlySpendingTrendPoint({
    required this.month,
    required this.spending,
  });

  final DateTime month;
  final AnalysisMetric? spending;
}

/// Builds a bounded month-by-month spending trend without persisting findings.
///
/// The current financial month keeps month-to-date semantics. Historical
/// months are resolved as complete selected months by the application period
/// resolver. Only the existing expense-total rule is executed, so loading a
/// Home chart never creates historical insight findings as a side effect.
final class CalculateMonthlySpendingTrend {
  const CalculateMonthlySpendingTrend(this.analysis);

  final CalculateAnalysisOverview analysis;

  Future<ApplicationResult<List<MonthlySpendingTrendPoint>>> call({
    required DateTime endingMonth,
    required DateTime instant,
    int monthCount = 7,
  }) => runApplication('calculate monthly spending trend', () async {
    if (monthCount < 1 || monthCount > 24) {
      throw const DomainValidationException(
        code: DomainErrorCode.invalidRange,
        field: 'monthCount',
        message: 'Monthly spending trend must contain between 1 and 24 months.',
      );
    }

    final currentContextResult = await analysis.contextFor(
      'current_month',
      instant: instant,
    );
    if (currentContextResult is! ApplicationSuccess<AnalysisContext>) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'current financial month is unavailable',
      );
    }
    final currentContext = currentContextResult.value;
    final currentMonth = _monthAnchor(
      DateTime.parse(currentContext.period.startDate),
    );
    final requestedEnd = _monthAnchor(endingMonth);
    if (requestedEnd.isAfter(currentMonth)) {
      throw const DomainValidationException(
        code: DomainErrorCode.invalidRange,
        field: 'endingMonth',
        message: 'Monthly spending trend cannot end in a future month.',
      );
    }

    final definitions = await analysis.rules.listActive();
    final expenseRule = definitions
        .where(
          (rule) =>
              rule.role == 'expenseTotal' &&
              rule.type == AnalysisRuleType.metric,
        )
        .firstOrNull;
    if (expenseRule == null) {
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'expense total analysis rule is unavailable',
      );
    }

    // Build the canonical economic transaction source once. Each trend point
    // reuses that normalized/reconciled source with a different authoritative
    // period context, so a seven-month Home chart does not reread and rebuild
    // the complete finance dataset seven times.
    final sharedDatasetResult = await analysis.datasetBuilder.build(
      currentContext,
    );
    if (sharedDatasetResult is! ApplicationDatasetSuccess) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'monthly spending dataset is unavailable',
      );
    }
    final sharedDataset = sharedDatasetResult.dataset;

    final points = <MonthlySpendingTrendPoint>[];
    for (var offset = monthCount - 1; offset >= 0; offset--) {
      final month = DateTime.utc(
        requestedEnd.year,
        requestedEnd.month - offset,
        1,
      );
      final context = _sameMonth(month, currentMonth)
          ? currentContext
          : await _selectedMonthContext(
              month,
              currentContext.period.timeZoneId,
              instant,
            );
      final dataset = AnalysisDataset(
        transactions: sharedDataset.transactions,
        context: context,
        qualityIssues: sharedDataset.qualityIssues,
      );
      final results = analysis.engine.execute(
        dataset: dataset,
        definitions: [expenseRule],
      );
      final spending = results
          .map((result) => result.metric)
          .whereType<AnalysisMetric>()
          .firstOrNull;
      points.add(MonthlySpendingTrendPoint(month: month, spending: spending));
    }
    return List.unmodifiable(points);
  });

  Future<AnalysisContext> _selectedMonthContext(
    DateTime month,
    String timeZoneId,
    DateTime instant,
  ) async {
    final anchor = _date(month);
    final result = await analysis.contextFor(
      'selected_month',
      instant: instant,
      customPeriod: AnalysisPeriod(
        startDate: anchor,
        endDate: anchor,
        timeZoneId: timeZoneId,
      ),
    );
    if (result is ApplicationSuccess<AnalysisContext>) return result.value;
    throw const RepositoryException(
      RepositoryFailureCode.unavailable,
      'selected financial month is unavailable',
    );
  }
}

DateTime _monthAnchor(DateTime value) =>
    DateTime.utc(value.year, value.month, 1);

bool _sameMonth(DateTime left, DateTime right) =>
    left.year == right.year && left.month == right.month;

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-01';
