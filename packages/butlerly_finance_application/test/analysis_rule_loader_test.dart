import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:test/test.dart';

void main() {
  const parser = RestrictedRuleParser();
  const validator = RuleDefinitionValidator();

  const valid = '''
schemaVersion: "1.0.0"
ruleId: ANL-R001
ruleVersion: "1.0.0"
enabled: true
type: metric
nameKey: analysis.r001.name
descriptionKey: analysis.r001.description
period: currentPeriod
measure:
  operation: sum
  field: amount
''';

  test('parses and validates a restricted rule definition', () {
    final parsed = parser.parse(valid);
    expect(parsed.isValid, isTrue);
    final result = validator.validate(parsed.document!);
    expect(result.diagnostics, isEmpty);
    expect(result.definition!.identity.value, 'ANL-R001');
    expect(result.definition!.definitionHash.value, hasLength(64));
  });

  test('rejects duplicate keys and anchors', () {
    final result = parser.parse('''
schemaVersion: "1.0.0"
schemaVersion: "1.0.0"
ruleId: ANL-R001
value: &bad 1
other: *bad
''');
    expect(result.isValid, isFalse);
    expect(
      result.diagnostics.map((value) => value.code),
      contains('duplicateKey'),
    );
    expect(
      result.diagnostics.map((value) => value.code),
      contains('unsupportedYamlFeature'),
    );
  });

  test('canonical hash is deterministic', () {
    final first = parser.parse(valid).document!;
    final second = parser.parse(valid).document!;
    expect(canonicalize(first.values), canonicalize(second.values));
  });

  test('rejects unknown fields', () {
    final parsed = parser.parse('$valid\nnotAllowed: true\n');
    final result = validator.validate(parsed.document!);
    expect(result.definition, isNull);
    expect(
      result.diagnostics.map((value) => value.code),
      contains('unknownField'),
    );
  });
}
