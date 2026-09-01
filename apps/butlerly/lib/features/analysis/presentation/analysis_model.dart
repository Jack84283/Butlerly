import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

abstract final class AnalysisRuleRoles {
  static const spending = 'ANL-R001';
  static const income = 'ANL-R002';
  static const netCashFlow = 'ANL-R003';
  static const transactionCount = 'ANL-R004';
  static const categoryBreakdown = 'ANL-R010';
  static const spendingTrend = 'ANL-R014';
  static const notableInsight = 'ANL-R020';
}

class AnalysisModel {
  factory AnalysisModel.fromResults(List<RuleExecutionResult> results) {
    AnalysisMetric? metric(String id) => results
        .where((r) => r.metric != null && r.rule.identity.value == id)
        .map((r) => r.metric!)
        .firstOrNull;
    final categories =
        results
            .where(
              (r) =>
                  r.metric != null &&
                  r.rule.identity.value == AnalysisRuleRoles.categoryBreakdown,
            )
            .map((r) => r.metric!)
            .toList()
          ..sort((a, b) => analysisNumber(b).compareTo(analysisNumber(a)));
    final trend =
        results
            .where(
              (r) =>
                  r.metric != null &&
                  r.rule.identity.value == AnalysisRuleRoles.spendingTrend,
            )
            .map((r) => r.metric!)
            .toList()
          ..sort(
            (a, b) =>
                analysisRawDimension(a).compareTo(analysisRawDimension(b)),
          );
    final finding = results
        .where(
          (r) =>
              r.finding != null &&
              r.rule.identity.value == AnalysisRuleRoles.notableInsight,
        )
        .map((r) => r.finding!)
        .firstOrNull;
    final quality = analysisQualitySummary(results);
    return AnalysisModel(
      spending: metric(AnalysisRuleRoles.spending),
      income: metric(AnalysisRuleRoles.income),
      net: metric(AnalysisRuleRoles.netCashFlow),
      transactionCount: metric(AnalysisRuleRoles.transactionCount),
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

  const AnalysisModel({
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

double analysisNumber(AnalysisMetric metric) =>
    double.tryParse(metric.value.toString()) ?? 0;

String analysisCategoryId(AnalysisMetric metric) =>
    metric.dimension?.split(':').firstOrNull ?? '';

String analysisRawDimension(AnalysisMetric metric) =>
    metric.dimension?.split(':').firstOrNull ?? metric.rule.nameKey;

extension AnalysisFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
