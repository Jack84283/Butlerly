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

  AnalysisRuleDefinition _fromJson(Map<String, dynamic> json, String hash) =>
      AnalysisRuleDefinition(
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
        ),
        grouping: RuleGrouping.none,
        baseline: RuleBaseline.none,
        condition: const RuleCondition(operator: 'none'),
        severity: RuleSeverity.info,
        definitionHash: RuleDefinitionHash(hash),
      );
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
  Future<List<AnalysisFinding>> list({FindingLifecycle? lifecycle}) async =>
      const [];

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
