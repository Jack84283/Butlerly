import 'dart:io';

import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);
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

  test(
    'round-trips conditions, dependency versions, and result policy',
    () async {
      final source = '''
schemaVersion: "1.0.0"
ruleId: ANL-R020
ruleVersion: "1.1.0"
enabled: true
type: insight
nameKey: analysis.rule.r020.name
descriptionKey: analysis.rule.r020.description
period: selected_period
baseline: previousEquivalentPeriod
severity: attention
measure:
  operation: sum
  field: amount
dependencies:
  - ruleId: ANL-R001
    minimumVersion: "1.1.0"
condition:
  operator: gte
  left: percentageChange
  value: "20"
result:
  persistence: finding
  refresh: onInvalidation
''';
      final parsed = parser.parse(source);
      final validated = validator.validate(parsed.document!);
      expect(validated.diagnostics, isEmpty);
      final definition = validated.definition!;
      final database = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
        schemaSql: File(
          '../../packages/butlerly_database/database/schema/v1.sql',
        ).readAsStringSync(),
      );
      await database.open();
      addTearDown(database.close);
      final repository = SqliteAnalysisRuleRepository(database);
      await repository.install(
        definition,
        sourceType: 'test',
        canonicalDefinition: canonicalize(parsed.document!.values),
      );
      final restored = (await repository.listDefinitions()).single;
      expect(restored.condition.operator, 'gte');
      expect(restored.condition.left, 'percentageChange');
      expect(restored.condition.value, DecimalValue.parse('20'));
      expect(restored.dependencies.single.minimumVersion!.value, '1.1.0');
      expect(restored.resultPersistence, ResultPersistencePolicy.finding);
      expect(restored.refreshPolicy, RefreshPolicy.onInvalidation);
      expect(restored.definitionHash, definition.definitionHash);
    },
  );

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

  test('bundled R016 installs and reloads through SQLite', () async {
    final source = File(
      '${Directory.current.path}/../../apps/butlerly/assets/analysis_rules/metrics/ANL-R016.yaml',
    ).readAsStringSync();
    final parsed = parser.parse(source);
    final validated = validator.validate(parsed.document!);
    final database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: File(
        '../../packages/butlerly_database/database/schema/v1.sql',
      ).readAsStringSync(),
    );
    await database.open();
    addTearDown(database.close);
    final repository = SqliteAnalysisRuleRepository(database);
    final definition = validated.definition!;
    await repository.install(
      definition,
      sourceType: 'bundled',
      canonicalDefinition: canonicalize(parsed.document!.values),
    );
    await repository.activate(
      definition.identity,
      definition.version,
      true,
      DateTime.utc(2026, 8, 26),
    );

    final restored = (await repository.listActive()).single;
    expect(restored.identity.value, 'ANL-R016');
    expect(restored.measure.key, 'transactionCount');
    expect(restored.measures.map((measure) => measure.key), [
      'transactionCount',
      'expenseTotal',
      'incomeTotal',
    ]);
    expect(
      restored.measures[1].filters.single.kind,
      AnalysisFilterKind.direction,
    );
  });
}
