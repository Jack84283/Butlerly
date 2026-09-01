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
  String? resultSetKey,
  int resultSetSize = 1,
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
      'availability': metric.availability.name,
      'evidence': metric.evidence
          .map(
            (value) => {
              'transactionId': value.transactionId.value,
              'evidenceId': value.evidenceId?.value,
            },
          )
          .toList(growable: false),
      'qualityIssues': metric.qualityIssues
          .map(_qualityIssue)
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
      'evidence': finding.evidence.map(_evidence).toList(growable: false),
      'qualityIssues': finding.qualityIssues
          .map(_qualityIssue)
          .toList(growable: false),
    },
    if (metric == null && finding == null) 'kind': 'failure',
  });
  final dimension = metric?.dimension ?? finding?.dimension;
  return AnalysisRuleResult(
    id: AnalysisResultIdentity.forRule(
      rule: result.rule,
      context: context,
      dimension: dimension,
    ).value,
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
    resultSetKey: resultSetKey,
    resultSetSize: resultSetSize,
  );
}

List<AnalysisRuleResult> materializeResults(
  List<RuleExecutionResult> results, {
  required AnalysisContext context,
  required DateTime at,
  int sourceRevision = 0,
}) {
  final groups = <String, List<RuleExecutionResult>>{};
  for (final result in results) {
    if (result.metric == null && result.finding == null) continue;
    groups.putIfAbsent(result.rule.identity.value, () => []).add(result);
  }
  return [
    for (final entry in groups.entries)
      for (final result in entry.value)
        materializeResult(
          result,
          context: context,
          at: at,
          sourceRevision: sourceRevision,
          resultSetKey: AnalysisResultIdentity.forRule(
            rule: result.rule,
            context: context,
            dimension: null,
          ).value,
          resultSetSize: entry.value.length,
        ),
  ];
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
        evidence: _evidenceList(json['evidence']),
        qualityIssues: _qualityIssues(json['qualityIssues']),
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
      availability: AnalysisDataAvailability.values.byName(
        json['availability'] as String? ??
            AnalysisDataAvailability.sufficient.name,
      ),
      evidence: _evidenceList(json['evidence']),
      qualityIssues: _qualityIssues(json['qualityIssues']),
      calculatedAt: persisted.calculatedAt,
    ),
  );
}

DecimalValue? _decimal(Object? value) =>
    value == null ? null : DecimalValue.parse(value as String);

Map<String, Object?> _evidence(EvidenceReference value) => {
  'transactionId': value.transactionId.value,
  'evidenceId': value.evidenceId?.value,
};

List<EvidenceReference> _evidenceList(Object? value) => value is! List
    ? const []
    : value
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => EvidenceReference(
              transactionId: TransactionId(item['transactionId'].toString()),
              evidenceId: item['evidenceId'] == null
                  ? null
                  : EvidenceId(item['evidenceId'].toString()),
            ),
          )
          .toList(growable: false);

Map<String, Object?> _qualityIssue(DataQualityIssue value) => {
  'code': value.code,
  'detail': value.detail,
  'transactionId': value.transactionId?.value,
};

List<DataQualityIssue> _qualityIssues(Object? value) => value is! List
    ? const []
    : value
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => DataQualityIssue(
              code: item['code'].toString(),
              detail: item['detail'].toString(),
              transactionId: item['transactionId'] == null
                  ? null
                  : TransactionId(item['transactionId'].toString()),
            ),
          )
          .toList(growable: false);
