import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'analysis_value.dart';

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
    final spending = metric(AnalysisSemanticRole.expenseTotal);
    final income = metric(AnalysisSemanticRole.incomeTotal);
    final savings = spending == null || income == null
        ? null
        : AnalysisValue(
            value: income.value.subtract(spending.value),
            currency:
                income.currency ??
                spending.currency ??
                income.context.baseCurrency,
            context: income.context,
            availability: _combinedAvailability(
              spending.availability,
              income.availability,
            ),
            qualityIssues: [...spending.qualityIssues, ...income.qualityIssues],
          );
    final savingsRate =
        savings == null ||
            savings.availability != AnalysisDataAvailability.sufficient ||
            income == null ||
            !income.value.isPositive
        ? null
        : _ratio(savings.value, income.value);
    final categoryShares =
        spending == null ||
            spending.availability != AnalysisDataAvailability.sufficient ||
            !spending.value.isPositive
        ? const <String, DecimalValue>{}
        : <String, DecimalValue>{
            for (final category in categories)
              category.id: _ratio(category.value, spending.value),
          };
    AnalysisComparison? comparisonFor(String role) => results
        .where((r) => r.rule.role == role)
        .map((r) => r.comparison)
        .whereType<AnalysisComparison>()
        .where(isUsableComparison)
        .firstOrNull;
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
      spending: spending,
      income: income,
      savings: savings,
      savingsRate: savingsRate,
      net: metric(AnalysisSemanticRole.netCashFlow),
      transactionCount: metric(AnalysisSemanticRole.eligibleTransactionCount),
      insight: finding,
      comparison: results
          .map((result) => result.comparison)
          .whereType<AnalysisComparison>()
          .where(isUsableComparison)
          .firstOrNull,
      spendingComparison: comparisonFor(AnalysisSemanticRole.expenseTotal),
      incomeComparison: comparisonFor(AnalysisSemanticRole.incomeTotal),
      netComparison: comparisonFor(AnalysisSemanticRole.netCashFlow),
      insightUnavailable: results.any(
        (r) => r.rule.surface == AnalysisSurface.insights && r.failure != null,
      ),
      trend: trend,
      categories: categories,
      categoryShares: categoryShares,
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
    this.categoryShares = const {},
    required this.qualityCount,
    required this.qualityEvaluated,
    required this.qualityLimited,
    this.comparison,
    this.spendingComparison,
    this.incomeComparison,
    this.netComparison,
    this.savings,
    this.savingsRate,
  });

  final AnalysisMetric? spending;
  final AnalysisMetric? income;
  final AnalysisValue? savings;
  final DecimalValue? savingsRate;
  final AnalysisMetric? net;
  final AnalysisMetric? transactionCount;
  final AnalysisFinding? insight;
  final bool insightUnavailable;
  final List<AnalysisMetric> trend;
  final List<AnalysisMetric> categories;
  final Map<String, DecimalValue> categoryShares;
  final int qualityCount;
  final bool qualityEvaluated;
  final bool qualityLimited;
  final AnalysisComparison? comparison;
  final AnalysisComparison? spendingComparison;
  final AnalysisComparison? incomeComparison;
  final AnalysisComparison? netComparison;
}

AnalysisDataAvailability _combinedAvailability(
  AnalysisDataAvailability left,
  AnalysisDataAvailability right,
) {
  if (left == AnalysisDataAvailability.insufficient ||
      right == AnalysisDataAvailability.insufficient) {
    return AnalysisDataAvailability.insufficient;
  }
  if (left == AnalysisDataAvailability.empty ||
      right == AnalysisDataAvailability.empty) {
    return AnalysisDataAvailability.empty;
  }
  return AnalysisDataAvailability.sufficient;
}

DecimalValue _ratio(DecimalValue numerator, DecimalValue denominator) {
  const scale = 6;
  final scaledNumerator =
      numerator.coefficient * BigInt.from(10).pow(scale + denominator.scale);
  final scaledDenominator =
      denominator.coefficient * BigInt.from(10).pow(numerator.scale);
  return DecimalValue.fromParts(
    coefficient: scaledNumerator ~/ scaledDenominator,
    scale: scale,
  );
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
