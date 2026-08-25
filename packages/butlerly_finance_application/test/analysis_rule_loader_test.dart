import 'dart:io';

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
period: selected_period
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

  test('rejects incompatible measure semantics', () {
    final parsed = parser.parse('''
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
  field: transactionCount
''');
    final result = validator.validate(parsed.document!);
    expect(result.definition, isNull);
    expect(result.diagnostics.map((value) => value.code), contains('semantic'));
  });

  test('all bundled initial rules validate through the production loader', () {
    final root = Directory.current.path;
    final assets = Directory('$root/../../apps/butlerly/assets/analysis_rules');
    final files =
        assets
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.yaml'))
            .where((file) => !file.path.endsWith('catalog.yaml'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, hasLength(11));
    final ids = <String>{};
    for (final file in files) {
      final parsed = parser.parse(file.readAsStringSync());
      expect(parsed.isValid, isTrue, reason: file.path);
      final result = validator.validate(parsed.document!);
      expect(result.diagnostics, isEmpty, reason: file.path);
      expect(ids.add(result.definition!.identity.value), isTrue);
    }
  });
}
