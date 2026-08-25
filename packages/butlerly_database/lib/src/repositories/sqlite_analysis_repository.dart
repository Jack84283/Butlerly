import 'dart:convert';

import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteAnalysisRuleRepository implements AnalysisRuleRepository {
  const SqliteAnalysisRuleRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> install(
    AnalysisRuleDefinition definition, {
    required String sourceType,
    required String canonicalDefinition,
  }) async {
    await database.connection.insert('analysis_rule_definitions', {
      'rule_id': definition.identity.value,
      'rule_version': definition.version.value,
      'schema_version': definition.schemaVersion,
      'source_type': sourceType,
      'definition': canonicalDefinition,
      'canonical_definition': canonicalDefinition,
      'definition_hash': definition.definitionHash.value,
      'validation_status': 'valid',
      'validation_diagnostics': null,
      'installed_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<AnalysisRuleDefinition>> listDefinitions() async =>
      _readDefinitions();

  @override
  Future<void> activate(
    RuleIdentity id,
    RuleVersion version,
    bool enabled,
    DateTime at,
  ) async {
    await database.connection.insert('analysis_rule_activations', {
      'rule_id': id.value,
      'active_rule_version': version.value,
      'enabled': enabled ? 1 : 0,
      'updated_at': at.toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<AnalysisRuleDefinition>> listActive() async {
    final definitions = await _readDefinitions();
    final activations = await database.connection.query(
      'analysis_rule_activations',
      where: 'enabled = 1',
    );
    final active = {
      for (final row in activations)
        '${row['rule_id']}:${row['active_rule_version']}',
    };
    return definitions
        .where(
          (value) =>
              active.contains('${value.identity.value}:${value.version.value}'),
        )
        .toList(growable: false);
  }

  Future<List<AnalysisRuleDefinition>> _readDefinitions() async {
    final rows = await database.connection.query(
      'analysis_rule_definitions',
      where: 'validation_status = ?',
      whereArgs: ['valid'],
    );
    return rows
        .map(
          (row) => _fromJson(
            jsonDecode(row['canonical_definition']! as String)
                as Map<String, dynamic>,
            row['definition_hash']! as String,
          ),
        )
        .toList(growable: false);
  }

  AnalysisRuleDefinition _fromJson(
    Map<String, dynamic> json,
    String hash,
  ) => AnalysisRuleDefinition(
    identity: RuleIdentity(json['ruleId'] as String),
    version: RuleVersion(json['ruleVersion'] as String),
    schemaVersion: json['schemaVersion'] as String,
    type: AnalysisRuleType.values.byName(json['type'] as String),
    nameKey: json['nameKey'] as String,
    descriptionKey: json['descriptionKey'] as String,
    enabled: json['enabled'] as bool? ?? true,
    status: AnalysisRuleStatus.active,
    period: json['period'] as String? ?? 'currentPeriod',
    measure: RuleMeasure(
      operation: RuleOperation.values.byName(
        (json['measure'] as Map)['operation'] as String,
      ),
      field: (json['measure'] as Map)['field'] as String,
      currencyBasis: CurrencyBasis.values.byName(
        (json['measure'] as Map)['currencyBasis'] as String? ?? 'original',
      ),
    ),
    grouping: RuleGrouping.values.byName(json['grouping'] as String? ?? 'none'),
    baseline: RuleBaseline.values.byName(json['baseline'] as String? ?? 'none'),
    condition: const RuleCondition(operator: 'none'),
    severity: RuleSeverity.values.byName(json['severity'] as String? ?? 'info'),
    filters: _filters(json['filters']),
    dependencies: _dependencies(json['dependencies']),
    definitionHash: RuleDefinitionHash(hash),
  );

  List<AnalysisFilter> _filters(Object? raw) {
    if (raw is! Map) return const [];
    return raw.entries
        .map(
          (entry) => AnalysisFilter(
            kind: AnalysisFilterKind.values.byName(entry.key.toString()),
            values: entry.value is List
                ? (entry.value as List)
                      .map((value) => value.toString())
                      .toList(growable: false)
                : [entry.value.toString()],
          ),
        )
        .toList(growable: false);
  }

  List<RuleDependency> _dependencies(Object? raw) => raw is! List
      ? const []
      : raw
            .map(
              (value) => RuleDependency(ruleId: RuleIdentity(value.toString())),
            )
            .toList(growable: false);
}

final class SqliteAnalysisFindingRepository
    implements AnalysisFindingRepository {
  const SqliteAnalysisFindingRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(AnalysisFinding finding) async {
    await database.connection.insert('analysis_findings', {
      'id': finding.id,
      'rule_id': finding.rule.identity.value,
      'rule_version': finding.rule.version.value,
      'definition_hash': finding.rule.definitionHash.value,
      'period_start': finding.context.period.startDate,
      'period_end': finding.context.period.endDate,
      'time_zone_id': finding.context.period.timeZoneId,
      'payload': jsonEncode({
        'dimension': finding.dimension,
        'severity': finding.severity.name,
      }),
      'lifecycle': finding.lifecycle.name,
      'generated_at': finding.generatedAt.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<AnalysisFinding>> list({FindingLifecycle? lifecycle}) async {
    final rows = await database.connection.query(
      'analysis_findings',
      where: lifecycle == null ? null : 'lifecycle = ?',
      whereArgs: lifecycle == null ? null : [lifecycle.name],
      orderBy: 'generated_at DESC, id',
    );
    final definitions = await SqliteAnalysisRuleRepository(
      database,
    ).listDefinitions();
    final byKey = {
      for (final value in definitions)
        '${value.identity.value}:${value.version.value}': value,
    };
    return rows
        .map((row) {
          final rule = byKey['${row['rule_id']}:${row['rule_version']}'];
          if (rule == null) {
            throw StateError(
              'Stored finding references an unavailable rule definition.',
            );
          }
          final payload =
              jsonDecode(row['payload']! as String) as Map<String, dynamic>;
          return AnalysisFinding(
            id: row['id']! as String,
            rule: rule,
            context: AnalysisContext(
              period: AnalysisPeriod(
                startDate: row['period_start']! as String,
                endDate: row['period_end']! as String,
                timeZoneId: row['time_zone_id']! as String,
              ),
              datasetMode: DatasetMode.allEligible,
              currencyBasis: CurrencyBasis.original,
            ),
            severity: RuleSeverity.values.byName(
              payload['severity'] as String? ?? 'info',
            ),
            lifecycle: FindingLifecycle.values.byName(
              row['lifecycle']! as String,
            ),
            dimension: payload['dimension'] as String?,
            generatedAt: DateTime.parse(row['generated_at']! as String),
          );
        })
        .toList(growable: false);
  }

  @override
  Future<void> updateLifecycle(
    String id,
    FindingLifecycle lifecycle,
    DateTime at,
  ) async {
    await database.connection.update(
      'analysis_findings',
      {'lifecycle': lifecycle.name, 'updated_at': at.toUtc().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
