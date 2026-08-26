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
    final existing = await database.connection.query(
      'analysis_rule_definitions',
      columns: ['definition_hash'],
      where: 'rule_id = ? AND rule_version = ?',
      whereArgs: [definition.identity.value, definition.version.value],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      if (existing.first['definition_hash'] !=
          definition.definitionHash.value) {
        throw StateError(
          'Analysis rule version ${definition.identity.value}@${definition.version.value} is immutable.',
        );
      }
      return;
    }
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
    });
  }

  @override
  Future<List<AnalysisRuleDefinition>> listDefinitions() async =>
      _readDefinitions();

  @override
  Future<AnalysisRuleActivation?> existingActivation(RuleIdentity id) async {
    final rows = await database.connection.query(
      'analysis_rule_activations',
      columns: ['active_rule_version', 'enabled'],
      where: 'rule_id = ?',
      whereArgs: [id.value],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AnalysisRuleActivation(
      version: RuleVersion(rows.first['active_rule_version'] as String),
      enabled: rows.first['enabled'] == 1,
    );
  }

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
    final values = {
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
    };
    // Recalculation may update the derived payload, but viewing Analysis must
    // never reactivate a finding that the user acknowledged or dismissed.
    await database.connection.rawInsert(
      '''
      INSERT INTO analysis_findings
        (id, rule_id, rule_version, definition_hash, period_start, period_end,
         time_zone_id, payload, lifecycle, generated_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        rule_id = excluded.rule_id,
        rule_version = excluded.rule_version,
        definition_hash = excluded.definition_hash,
        period_start = excluded.period_start,
        period_end = excluded.period_end,
        time_zone_id = excluded.time_zone_id,
        payload = excluded.payload,
        generated_at = excluded.generated_at,
        updated_at = excluded.updated_at
      ''',
      [
        values['id'],
        values['rule_id'],
        values['rule_version'],
        values['definition_hash'],
        values['period_start'],
        values['period_end'],
        values['time_zone_id'],
        values['payload'],
        values['lifecycle'],
        values['generated_at'],
        values['updated_at'],
      ],
    );
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
