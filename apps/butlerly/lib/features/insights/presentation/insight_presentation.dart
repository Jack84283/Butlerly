import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

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

/// Resolves presentation behavior from declarative rule metadata first, then
/// falls back to the legacy structural inference for older installed rules.
extension InsightPresentationMetadataResolver on InsightResult {
  InsightPresentationMetadata get presentation {
    final declared = rule.presentation;
    if (declared != null) {
      return InsightPresentationMetadata(
        semanticType: declared.semanticType,
        visualizationType: declared.visualizationType,
        primaryMetric: declared.primaryMetric,
      );
    }
    return InsightPresentationMetadata(
      semanticType: _legacySemanticType,
      visualizationType: _legacyVisualizationType,
      primaryMetric: _legacyPrimaryMetric,
    );
  }

  InsightSemanticType get _legacySemanticType {
    return switch (rule.role) {
      'positive' => InsightSemanticType.positive,
      'attention' => InsightSemanticType.attention,
      'neutral' => InsightSemanticType.neutral,
      _ when outputType == InsightOutputType.alert =>
        InsightSemanticType.attention,
      _ => InsightSemanticType.neutral,
    };
  }

  InsightVisualizationType get _legacyVisualizationType {
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

  InsightPrimaryMetric get _legacyPrimaryMetric {
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
