import 'dart:convert';

import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// Converts an execution result into the generic persisted representation.
/// The payload is deliberately opaque to SQLite and remains rebuildable from
/// the canonical dataset.
AnalysisRuleResult materializeResult(
  RuleExecutionResult result, {
  required AnalysisContext context,
  required DateTime at,
  int sourceRevision = 0,
}) {
  final metric = result.metric;
  final finding = result.finding;
  final type = finding != null
      ? AnalysisResultType.finding
      : result.rule.type == AnalysisRuleType.dataQuality
      ? AnalysisResultType.dataQuality
      : AnalysisResultType.metric;
  final payload = jsonEncode({
    if (metric != null) ...{
      'kind': 'metric',
      'id': metric.id,
      'value': metric.value.toString(),
      'currency': metric.currency?.value,
      'dimension': metric.dimension,
      'transactionCount': metric.transactionCount,
      'evidence': metric.evidence
          .map(
            (value) => {
              'transactionId': value.transactionId.value,
              'evidenceId': value.evidenceId?.value,
            },
          )
          .toList(growable: false),
    },
    if (finding != null) ...{
      'kind': 'finding',
      'id': finding.id,
      'severity': finding.severity.name,
      'lifecycle': finding.lifecycle.name,
      'currentValue': finding.currentValue?.toString(),
      'baselineValue': finding.baselineValue?.toString(),
      'absoluteChange': finding.absoluteChange?.toString(),
      'percentageChange': finding.percentageChange?.toString(),
      'dimension': finding.dimension,
      'supportingMetrics': finding.supportingMetrics,
    },
    if (metric == null && finding == null) 'kind': 'failure',
  });
  final dimension = metric?.dimension ?? finding?.dimension;
  return AnalysisRuleResult(
    id: '${result.rule.identity.value}:${result.rule.version.value}:${result.rule.definitionHash.value}:${context.period.startDate}:${context.period.endDate}:${context.period.timeZoneId}:${context.datasetMode.name}:${context.currencyBasis.name}:${context.baseCurrency?.value}:$dimension',
    ruleId: result.rule.identity,
    ruleVersion: result.rule.version,
    definitionHash: result.rule.definitionHash,
    resultType: type,
    surface: result.rule.surface,
    context: context,
    dimension: dimension,
    payload: payload,
    calculatedAt: metric?.calculatedAt ?? finding?.generatedAt ?? at,
    sourceRevision: sourceRevision,
    freshness: AnalysisResultFreshness.fresh,
    createdAt: at,
    updatedAt: at,
  );
}

RuleExecutionResult restoreResult(
  AnalysisRuleResult persisted,
  AnalysisRuleDefinition rule,
) {
  final json = jsonDecode(persisted.payload) as Map<String, dynamic>;
  if (persisted.resultType == AnalysisResultType.finding) {
    return RuleExecutionResult(
      rule: rule,
      finding: AnalysisFinding(
        id: json['id'] as String,
        rule: rule,
        context: persisted.context,
        severity: RuleSeverity.values.byName(json['severity'] as String),
        lifecycle: FindingLifecycle.values.byName(json['lifecycle'] as String),
        currentValue: _decimal(json['currentValue']),
        baselineValue: _decimal(json['baselineValue']),
        absoluteChange: _decimal(json['absoluteChange']),
        percentageChange: _decimal(json['percentageChange']),
        dimension: json['dimension'] as String?,
        supportingMetrics:
            (json['supportingMetrics'] as List?)
                ?.map((value) => value.toString())
                .toList(growable: false) ??
            const [],
        generatedAt: persisted.calculatedAt,
      ),
    );
  }
  if (json['kind'] != 'metric') return RuleExecutionResult(rule: rule);
  return RuleExecutionResult(
    rule: rule,
    metric: AnalysisMetric(
      id: json['id'] as String,
      rule: rule,
      context: persisted.context,
      value: DecimalValue.parse(json['value'] as String),
      currency: json['currency'] == null
          ? null
          : CurrencyCode(json['currency'] as String),
      dimension: json['dimension'] as String?,
      transactionCount: json['transactionCount'] as int? ?? 0,
      calculatedAt: persisted.calculatedAt,
    ),
  );
}

DecimalValue? _decimal(Object? value) =>
    value == null ? null : DecimalValue.parse(value as String);
