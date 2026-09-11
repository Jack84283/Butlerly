import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

enum InsightSemanticType { positive, attention, neutral }

enum InsightVisualizationType { none, comparison, bar, pie, trend }

enum InsightPrimaryMetric { amount, percentage, count, share }

final class InsightPresentationMetadata {
  const InsightPresentationMetadata({
    required this.semanticType,
    required this.visualizationType,
    required this.primaryMetric,
  });

  final InsightSemanticType semanticType;
  final InsightVisualizationType visualizationType;
  final InsightPrimaryMetric primaryMetric;
}

/// Resolves presentation behavior from declarative rule/result metadata.
///
/// This intentionally never branches on a rule ID. The optional rule [role]
/// carries semantic intent for rules that need an explicit positive/attention
/// classification; structural result fields determine the visualization.
extension InsightPresentationMetadataResolver on InsightResult {
  InsightPresentationMetadata get presentation => InsightPresentationMetadata(
    semanticType: _semanticType,
    visualizationType: _visualizationType,
    primaryMetric: _primaryMetric,
  );

  InsightSemanticType get _semanticType {
    return switch (rule.role) {
      'positive' => InsightSemanticType.positive,
      'attention' => InsightSemanticType.attention,
      'neutral' => InsightSemanticType.neutral,
      _ when outputType == InsightOutputType.alert =>
        InsightSemanticType.attention,
      _ => InsightSemanticType.neutral,
    };
  }

  InsightVisualizationType get _visualizationType {
    if (baselineValue != null) return InsightVisualizationType.comparison;
    if (rule.measure.operation == RuleOperation.share &&
        rule.grouping == RuleGrouping.category) {
      return InsightVisualizationType.pie;
    }
    if (rule.grouping == RuleGrouping.day ||
        rule.grouping == RuleGrouping.week ||
        rule.grouping == RuleGrouping.month ||
        rule.grouping == RuleGrouping.adaptive) {
      return InsightVisualizationType.trend;
    }
    if (rule.grouping != RuleGrouping.none &&
        rule.grouping != RuleGrouping.transaction) {
      return InsightVisualizationType.bar;
    }
    return InsightVisualizationType.none;
  }

  InsightPrimaryMetric get _primaryMetric {
    if (rule.measure.operation == RuleOperation.share) {
      return InsightPrimaryMetric.share;
    }
    if (rule.measure.operation == RuleOperation.count ||
        rule.measure.operation == RuleOperation.distinctCount ||
        rule.measure.operation == RuleOperation.frequency) {
      return InsightPrimaryMetric.count;
    }
    return InsightPrimaryMetric.amount;
  }
}
