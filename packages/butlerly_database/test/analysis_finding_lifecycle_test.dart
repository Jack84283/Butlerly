import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late ButlerlyDatabase database;
  late SqliteAnalysisFindingRepository repository;

  setUp(() async {
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: await File('database/schema/v1.sql').readAsString(),
    );
    await database.open();
    repository = SqliteAnalysisFindingRepository(database);
  });

  tearDown(() => database.close());

  test('fresh active save reactivates a superseded finding', () async {
    final finding = _finding();
    await repository.save(finding);
    await repository.updateLifecycle(
      finding.id,
      FindingLifecycle.superseded,
      DateTime.utc(2026, 9, 11, 12),
    );

    await repository.save(finding);

    expect(await _storedLifecycle(database, finding.id), 'active');
  });

  test('acknowledged and dismissed lifecycle remain sticky', () async {
    for (final lifecycle in [
      FindingLifecycle.acknowledged,
      FindingLifecycle.dismissed,
    ]) {
      final finding = _finding(id: 'finding-${lifecycle.name}');
      await repository.save(finding);
      await repository.updateLifecycle(
        finding.id,
        lifecycle,
        DateTime.utc(2026, 9, 11, 12),
      );

      await repository.save(finding);

      expect(await _storedLifecycle(database, finding.id), lifecycle.name);
    }
  });
}

Future<String> _storedLifecycle(ButlerlyDatabase database, String id) async {
  final rows = await database.connection.query(
    'analysis_findings',
    columns: ['lifecycle'],
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return rows.single['lifecycle']! as String;
}

AnalysisFinding _finding({String id = 'finding-1'}) {
  final rule = AnalysisRuleDefinition(
    identity: RuleIdentity('ANL-R020'),
    version: RuleVersion('1.0.0'),
    schemaVersion: '1.0.0',
    type: AnalysisRuleType.insight,
    nameKey: 'analysis.rule.r020.name',
    descriptionKey: 'analysis.rule.r020.description',
    enabled: true,
    status: AnalysisRuleStatus.active,
    period: 'selected_period',
    measure: const RuleMeasure(
      operation: RuleOperation.sum,
      field: 'amount',
    ),
    grouping: RuleGrouping.none,
    baseline: RuleBaseline.previousEquivalentPeriod,
    condition: const RuleCondition(operator: 'gte'),
    severity: RuleSeverity.attention,
    surface: AnalysisSurface.insights,
    definitionHash: RuleDefinitionHash('a' * 64),
  );
  final context = AnalysisContext(
    period: AnalysisPeriod(
      startDate: '2026-09-01',
      endDate: '2026-09-11',
      timeZoneId: 'America/Los_Angeles',
    ),
    datasetMode: DatasetMode.allEligible,
    currencyBasis: CurrencyBasis.baseCurrency,
    baseCurrency: CurrencyCode('USD'),
  );
  return AnalysisFinding(
    id: id,
    rule: rule,
    context: context,
    severity: RuleSeverity.attention,
    lifecycle: FindingLifecycle.active,
    currentValue: DecimalValue.parse('120'),
    baselineValue: DecimalValue.parse('90'),
    absoluteChange: DecimalValue.parse('30'),
    percentageChange: DecimalValue.parse('33.33'),
    generatedAt: DateTime.utc(2026, 9, 11, 12),
  );
}
