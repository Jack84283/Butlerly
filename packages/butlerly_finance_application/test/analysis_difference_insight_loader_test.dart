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

  test('difference insight with two metric dependencies is valid', () {
    final result = validate('''
schemaVersion: "1.0.0"
ruleId: ANL-R029
ruleVersion: "1.0.0"
enabled: true
surface: insights
type: insight
nameKey: analysis.rule.r003.name
descriptionKey: analysis.rule.r003.description
role: positive
period: selected_period
baseline: previousEquivalentPeriod
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
    expect(result.definition!.role, 'positive');
  });

  test('difference insight requires two dependencies', () {
    final result = validate('''
schemaVersion: "1.0.0"
ruleId: ANL-R029
ruleVersion: "1.0.0"
enabled: true
surface: insights
type: insight
nameKey: analysis.rule.r003.name
descriptionKey: analysis.rule.r003.description
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
}
