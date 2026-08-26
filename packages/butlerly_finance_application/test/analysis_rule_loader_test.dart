import 'dart:io';

import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
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
    final definitions = <String, dynamic>{};
    for (final file in files) {
      final parsed = parser.parse(file.readAsStringSync());
      expect(parsed.isValid, isTrue, reason: file.path);
      final result = validator.validate(parsed.document!);
      expect(result.diagnostics, isEmpty, reason: file.path);
      expect(ids.add(result.definition!.identity.value), isTrue);
      definitions[result.definition!.identity.value] = result.definition;
    }
    expect(definitions['ANL-R010'].surface, AnalysisSurface.spending);
    expect(definitions['ANL-R010'].filters.single.values, ['expense']);
    expect(definitions['ANL-R016'].surface, AnalysisSurface.calendar);
    expect(definitions['ANL-R016'].measures, hasLength(3));
    expect(
      definitions['ANL-R016'].measures.first.operation,
      RuleOperation.count,
    );
    expect(definitions['ANL-R020'].enabled, isTrue);
    expect(definitions['ANL-R020'].surface, AnalysisSurface.insights);
    expect(definitions['ANL-R090'].surface, AnalysisSurface.dataQuality);
  });
}
