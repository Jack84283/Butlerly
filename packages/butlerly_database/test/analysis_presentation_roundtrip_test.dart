import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('round-trips declarative insight presentation through SQLite', () async {
    final database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: await File('database/schema/v1.sql').readAsString(),
    );
    await database.open();
    addTearDown(database.close);

    final source = File(
      '../../apps/butlerly/assets/analysis_rules/insights/ANL-R026.yaml',
    ).readAsStringSync();
    final parsed = const RestrictedRuleParser().parse(source);
    expect(parsed.diagnostics, isEmpty);
    final validated = const RuleDefinitionValidator().validate(parsed.document!);
    expect(validated.diagnostics, isEmpty);
    final definition = validated.definition!;
    expect(definition.presentation, isNotNull);

    final repository = SqliteAnalysisRuleRepository(database);
    await repository.install(
      definition,
      sourceType: 'bundled',
      canonicalDefinition: canonicalize(parsed.document!.values),
    );
    await repository.activate(
      definition.identity,
      definition.version,
      true,
      DateTime.utc(2026, 9, 11),
    );

    final reloaded = (await repository.listActive()).single;
    expect(reloaded.presentation, isNotNull);
    expect(
      reloaded.presentation!.semanticType,
      InsightSemanticType.neutral,
    );
    expect(
      reloaded.presentation!.visualizationType,
      InsightVisualizationType.pie,
    );
    expect(
      reloaded.presentation!.primaryMetric,
      InsightPrimaryMetric.share,
    );
  });
}
