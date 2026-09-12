import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  const parser = RestrictedRuleParser();
  const validator = RuleDefinitionValidator();

  ({AnalysisRuleDefinition? definition, List<RuleDiagnostic> diagnostics})
  validate(String source) {
    final parsed = parser.parse(source);
    expect(parsed.isValid, isTrue, reason: parsed.diagnostics.toString());
    return validator.validate(parsed.document!);
  }

  test('difference insight with declarative presentation is valid', () {
    final result = validate('''
schemaVersion: "1.0.0"
ruleId: ANL-R029
ruleVersion: "1.0.0"
enabled: true
surface: insights
type: insight
nameKey: analysis.rule.r029.name
descriptionKey: analysis.rule.r029.description
period: selected_period
baseline: previousEquivalentPeriod
presentation:
  semantic_type: positive
  visualization_type: comparison
  primary_metric: amount
measure:
  operation: difference
  field: amount
  currencyBasis: baseCurrency
dependencies:
  - ANL-R001
  - ANL-R002
condition:
  operator: gt
  left: absoluteChange
  value: "0"
severity: info
result:
  persistence: finding
  refresh: onInvalidation
  outputType: pattern
''');

    expect(result.diagnostics, isEmpty);
    expect(result.definition, isNotNull);
    expect(result.definition!.measure.operation, RuleOperation.difference);
    expect(result.definition!.dependencies, hasLength(2));
    expect(
      result.definition!.presentation?.semanticType,
      InsightSemanticType.positive,
    );
    expect(
      result.definition!.presentation?.visualizationType,
      InsightVisualizationType.comparison,
    );
    expect(
      result.definition!.presentation?.primaryMetric,
      InsightPrimaryMetric.amount,
    );
  });

  test('difference insight requires two dependencies', () {
    final result = validate('''
schemaVersion: "1.0.0"
ruleId: ANL-R029
ruleVersion: "1.0.0"
enabled: true
surface: insights
type: insight
nameKey: analysis.rule.r029.name
descriptionKey: analysis.rule.r029.description
period: selected_period
baseline: previousEquivalentPeriod
measure:
  operation: difference
  field: amount
  currencyBasis: baseCurrency
dependencies:
  - ANL-R001
condition:
  operator: gt
  left: absoluteChange
  value: "0"
severity: info
''');

    expect(result.definition, isNull);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      contains('semantic'),
    );
  });

  test('presentation requires all three declarative fields', () {
    final result = validate('''
schemaVersion: "1.0.0"
ruleId: ANL-R027
ruleVersion: "1.0.0"
enabled: true
surface: insights
type: insight
nameKey: analysis.rule.r027.name
descriptionKey: analysis.rule.r027.description
period: selected_period
baseline: previousEquivalentPeriod
presentation:
  semantic_type: positive
  visualization_type: comparison
measure:
  operation: sum
  field: amount
  currencyBasis: baseCurrency
filters:
  direction: expense
condition:
  operator: gt
  left: currentTotal
  value: "0"
severity: info
''');

    expect(result.definition, isNull);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      contains('semantic'),
    );
  });

  test('presentation rejects unknown fields', () {
    final result = validate('''
schemaVersion: "1.0.0"
ruleId: ANL-R027
ruleVersion: "1.0.0"
enabled: true
surface: insights
type: insight
nameKey: analysis.rule.r027.name
descriptionKey: analysis.rule.r027.description
period: selected_period
baseline: previousEquivalentPeriod
presentation:
  semantic_type: positive
  visualization_type: comparison
  primary_metric: amount
  color: green
measure:
  operation: sum
  field: amount
  currencyBasis: baseCurrency
filters:
  direction: expense
condition:
  operator: gt
  left: currentTotal
  value: "0"
severity: info
''');

    expect(result.definition, isNull);
    expect(
      result.diagnostics.map((diagnostic) => diagnostic.code),
      contains('semantic'),
    );
  });
}
