import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// Application projection of validated rule outputs; independent of Flutter.
class AnalysisOverview {
  factory AnalysisOverview.fromResults(List<RuleExecutionResult> results) {
    AnalysisMetric? metric(String role) => results
        .where((r) => r.metric != null && r.rule.role == role)
        .map((r) => r.metric!)
        .firstOrNull;
    final categories =
        results
            .where(
              (r) =>
                  r.metric != null &&
                  r.rule.surface == AnalysisSurface.spending &&
                  r.rule.grouping == RuleGrouping.category,
            )
            .map((r) => r.metric!)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    final trend =
        results
            .where(
              (r) =>
                  r.metric != null && r.rule.surface == AnalysisSurface.trends,
            )
            .map((r) => r.metric!)
            .toList()
          ..sort((a, b) => (a.dimension ?? '').compareTo(b.dimension ?? ''));
    final finding = results
        .where(
          (r) =>
              r.finding != null &&
              r.rule.role == AnalysisSemanticRole.spendingComparison,
        )
        .map((r) => r.finding!)
        .firstOrNull;
    final quality = analysisQualitySummary(results);
    return AnalysisOverview(
      spending: metric(AnalysisSemanticRole.expenseTotal),
      income: metric(AnalysisSemanticRole.incomeTotal),
      net: metric(AnalysisSemanticRole.netCashFlow),
      transactionCount: metric(AnalysisSemanticRole.eligibleTransactionCount),
      insight: finding,
      comparison: results
          .map((result) => result.comparison)
          .whereType<AnalysisComparison>()
          .where(isUsableComparison)
          .firstOrNull,
      insightUnavailable: results.any(
        (r) => r.rule.surface == AnalysisSurface.insights && r.failure != null,
      ),
      trend: trend,
      categories: categories,
      qualityCount: quality.count,
      qualityEvaluated: results.isNotEmpty,
      qualityLimited: quality.limited,
    );
  }

  const AnalysisOverview({
    this.spending,
    this.income,
    this.net,
    this.transactionCount,
    this.insight,
    required this.insightUnavailable,
    required this.trend,
    required this.categories,
    required this.qualityCount,
    required this.qualityEvaluated,
    required this.qualityLimited,
    this.comparison,
  });

  final AnalysisMetric? spending;
  final AnalysisMetric? income;
  final AnalysisMetric? net;
  final AnalysisMetric? transactionCount;
  final AnalysisFinding? insight;
  final bool insightUnavailable;
  final List<AnalysisMetric> trend;
  final List<AnalysisMetric> categories;
  final int qualityCount;
  final bool qualityEvaluated;
  final bool qualityLimited;
  final AnalysisComparison? comparison;
}

class AnalysisQualitySummary {
  const AnalysisQualitySummary(this.count, this.limited);
  final int count;
  final bool limited;
}

AnalysisQualitySummary analysisQualitySummary(
  List<RuleExecutionResult> results,
) {
  final keys = <String>{};
  var failures = 0;
  var limited = false;
  for (final result in results) {
    if (result.failure != null) {
      failures++;
      limited = true;
    }
    final issues = [
      ...result.issues,
      ...?result.metric?.qualityIssues,
      ...?result.finding?.qualityIssues,
    ];
    for (final issue in issues) {
      keys.add('${issue.code}|${issue.detail}|${issue.transactionId?.value}');
    }
    final qualityMetric =
        result.metric != null &&
        result.rule.surface == AnalysisSurface.dataQuality;
    if (qualityMetric) {
      final value = int.tryParse(result.metric!.value.toString()) ?? 0;
      if (value > 0) keys.add('metric|${result.rule.identity.value}|$value');
    }
  }
  return AnalysisQualitySummary(keys.length + failures, limited);
}

bool isUsableComparison(AnalysisComparison comparison) =>
    comparison.availability == AnalysisDataAvailability.sufficient &&
    comparison.baselineValue != null &&
    comparison.percentageChange != null;
