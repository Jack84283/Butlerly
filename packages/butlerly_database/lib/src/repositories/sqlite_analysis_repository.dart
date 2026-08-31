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

  AnalysisRuleDefinition _fromJson(Map<String, dynamic> json, String hash) {
    final measures = _measures(json);
    final rawLegacyMeasure = json['measure'];
    final legacyMeasure = rawLegacyMeasure is Map
        ? _measure(rawLegacyMeasure)
        : measures.first;
    return AnalysisRuleDefinition(
      identity: RuleIdentity(json['ruleId'] as String),
      version: RuleVersion(json['ruleVersion'] as String),
      schemaVersion: json['schemaVersion'] as String,
      type: AnalysisRuleType.values.byName(json['type'] as String),
      nameKey: json['nameKey'] as String,
      descriptionKey: json['descriptionKey'] as String,
      enabled: json['enabled'] as bool? ?? true,
      status: AnalysisRuleStatus.active,
      period: json['period'] as String? ?? 'currentPeriod',
      measure: legacyMeasure,
      measures: measures,
      surface: AnalysisSurface.values.byName(
        json['surface'] as String? ?? 'overview',
      ),
      grouping: RuleGrouping.values.byName(
        json['grouping'] as String? ?? 'none',
      ),
      baseline: RuleBaseline.values.byName(
        json['baseline'] as String? ?? 'none',
      ),
      condition: _condition(json['condition']),
      severity: RuleSeverity.values.byName(
        json['severity'] as String? ?? 'info',
      ),
      filters: _filters(json['filters']),
      dependencies: _dependencies(json['dependencies']),
      resultPersistence: ResultPersistencePolicy.values.byName(
        (json['result'] as Map?)?['persistence']?.toString() ??
            (json['type'] == 'insight' ? 'finding' : 'transient'),
      ),
      refreshPolicy: RefreshPolicy.values.byName(
        (json['result'] as Map?)?['refresh']?.toString() ?? 'onInvalidation',
      ),
      definitionHash: RuleDefinitionHash(hash),
    );
  }

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

  List<RuleMeasure> _measures(Map<String, dynamic> json) {
    final raw = json['measures'];
    if (raw is! List) return const [];
    return raw
        .map((value) {
          final measure = value as Map;
          return _measure(measure);
        })
        .toList(growable: false);
  }

  RuleMeasure _measure(Map measure) => RuleMeasure(
    operation: RuleOperation.values.byName(measure['operation'] as String),
    field: measure['field'] as String,
    key: measure['key']?.toString() ?? 'value',
    currencyBasis: CurrencyBasis.values.byName(
      measure['currencyBasis'] as String? ?? 'original',
    ),
    filters: _filters(measure['filters']),
  );

  List<RuleDependency> _dependencies(Object? raw) => raw is! List
      ? const []
      : raw
            .map(
              (value) => value is Map
                  ? RuleDependency(
                      ruleId: RuleIdentity(value['ruleId'].toString()),
                      minimumVersion: value['minimumVersion'] == null
                          ? null
                          : RuleVersion(value['minimumVersion'].toString()),
                    )
                  : RuleDependency(ruleId: RuleIdentity(value.toString())),
            )
            .toList(growable: false);

  RuleCondition _condition(Object? raw) {
    if (raw is! Map) return const RuleCondition(operator: 'none');
    final children = raw['children'] is List
        ? (raw['children'] as List).map(_condition).toList(growable: false)
        : const <RuleCondition>[];
    return RuleCondition(
      operator: raw['operator']?.toString() ?? 'none',
      value: raw['value'] == null
          ? null
          : DecimalValue.parse(raw['value'].toString()),
      left: raw['left']?.toString(),
      right: raw['right']?.toString(),
      children: children,
    );
  }
}

final class SqliteAnalysisRuleResultRepository
    implements AnalysisRuleResultRepository {
  const SqliteAnalysisRuleResultRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<List<AnalysisRuleResult>> findAll({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    int? sourceRevision,
  }) async {
    final where = <String>[
      'rule_id = ?',
      'rule_version = ?',
      'definition_hash = ?',
      'period_start = ?',
      'period_end = ?',
      'time_zone_id = ?',
      'dataset_mode = ?',
      'currency_basis = ?',
      'freshness = ?',
    ];
    final args = <Object?>[
      rule.identity.value,
      rule.version.value,
      rule.definitionHash.value,
      context.period.startDate,
      context.period.endDate,
      context.period.timeZoneId,
      context.datasetMode.name,
      context.currencyBasis.name,
      AnalysisResultFreshness.fresh.name,
    ];
    if (context.baseCurrency == null) {
      where.add('base_currency IS NULL');
    } else {
      where.add('base_currency = ?');
      args.add(context.baseCurrency!.value);
    }
    if (sourceRevision != null) {
      where.add('source_revision = ?');
      args.add(sourceRevision);
    }
    final rows = await database.connection.query(
      'analysis_rule_results',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'dimension, updated_at DESC',
    );
    return rows.map(_result).toList(growable: false);
  }

  @override
  Future<AnalysisRuleResult?> find({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    String? dimension,
    int? sourceRevision,
  }) async {
    final where = <String>[
      'rule_id = ?',
      'rule_version = ?',
      'definition_hash = ?',
      'period_start = ?',
      'period_end = ?',
      'time_zone_id = ?',
      'dataset_mode = ?',
      'currency_basis = ?',
      'freshness = ?',
    ];
    final args = <Object?>[
      rule.identity.value,
      rule.version.value,
      rule.definitionHash.value,
      context.period.startDate,
      context.period.endDate,
      context.period.timeZoneId,
      context.datasetMode.name,
      context.currencyBasis.name,
      AnalysisResultFreshness.fresh.name,
    ];
    if (context.baseCurrency == null) {
      where.add('base_currency IS NULL');
    } else {
      where.add('base_currency = ?');
      args.add(context.baseCurrency!.value);
    }
    if (dimension == null) {
      where.add('dimension IS NULL');
    } else {
      where.add('dimension = ?');
      args.add(dimension);
    }
    if (sourceRevision != null) {
      where.add('source_revision = ?');
      args.add(sourceRevision);
    }
    final rows = await database.connection.query(
      'analysis_rule_results',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _result(rows.single);
  }

  @override
  Future<void> save(AnalysisRuleResult result) async {
    final now = result.updatedAt.toUtc().toIso8601String();
    await database.connection.rawInsert(
      '''
      INSERT INTO analysis_rule_results
        (id, rule_id, rule_version, definition_hash, result_type, surface,
         period_start, period_end, time_zone_id, dataset_mode, currency_basis,
         base_currency, dimension, payload, calculated_at, source_revision,
         result_set_key, result_set_size,
         freshness, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        payload = excluded.payload,
        calculated_at = excluded.calculated_at,
        source_revision = excluded.source_revision,
        result_set_key = excluded.result_set_key,
        result_set_size = excluded.result_set_size,
        freshness = excluded.freshness,
        updated_at = excluded.updated_at
      ''',
      [
        result.id,
        result.ruleId.value,
        result.ruleVersion.value,
        result.definitionHash.value,
        result.resultType.name,
        result.surface.name,
        result.context.period.startDate,
        result.context.period.endDate,
        result.context.period.timeZoneId,
        result.context.datasetMode.name,
        result.context.currencyBasis.name,
        result.context.baseCurrency?.value,
        result.dimension,
        result.payload,
        result.calculatedAt.toUtc().toIso8601String(),
        result.sourceRevision,
        result.resultSetKey,
        result.resultSetSize,
        result.freshness.name,
        result.createdAt.toUtc().toIso8601String(),
        now,
      ],
    );
  }

  @override
  Future<void> markStale({
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  }) async {
    final clauses = <String>['freshness = ?'];
    final args = <Object?>[AnalysisResultFreshness.fresh.name];
    if (periodStart != null) {
      clauses.add('period_end >= ?');
      args.add(periodStart);
    }
    if (periodEnd != null) {
      clauses.add('period_start <= ?');
      args.add(periodEnd);
    }
    if (ruleIds != null && ruleIds.isNotEmpty) {
      clauses.add('rule_id IN (${List.filled(ruleIds.length, '?').join(',')})');
      args.addAll(ruleIds);
    } else if (ruleIds != null) {
      return;
    }
    await database.connection.update(
      'analysis_rule_results',
      {'freshness': AnalysisResultFreshness.stale.name},
      where: clauses.join(' AND '),
      whereArgs: args,
    );
  }

  AnalysisRuleResult _result(Map<String, Object?> row) => AnalysisRuleResult(
    id: row['id']! as String,
    ruleId: RuleIdentity(row['rule_id']! as String),
    ruleVersion: RuleVersion(row['rule_version']! as String),
    definitionHash: RuleDefinitionHash(row['definition_hash']! as String),
    resultType: AnalysisResultType.values.byName(row['result_type']! as String),
    surface: AnalysisSurface.values.byName(row['surface']! as String),
    context: AnalysisContext(
      period: AnalysisPeriod(
        startDate: row['period_start']! as String,
        endDate: row['period_end']! as String,
        timeZoneId: row['time_zone_id']! as String,
      ),
      datasetMode: DatasetMode.values.byName(row['dataset_mode']! as String),
      currencyBasis: CurrencyBasis.values.byName(
        row['currency_basis']! as String,
      ),
      baseCurrency: row['base_currency'] == null
          ? null
          : CurrencyCode(row['base_currency']! as String),
    ),
    dimension: row['dimension'] as String?,
    resultSetKey: row['result_set_key'] as String?,
    resultSetSize: row['result_set_size'] as int? ?? 1,
    payload: row['payload']! as String,
    calculatedAt: DateTime.parse(row['calculated_at']! as String),
    sourceRevision: row['source_revision']! as int,
    freshness: AnalysisResultFreshness.values.byName(
      row['freshness']! as String,
    ),
    createdAt: DateTime.parse(row['created_at']! as String),
    updatedAt: DateTime.parse(row['updated_at']! as String),
  );
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
        'currentValue': finding.currentValue?.toString(),
        'baselineValue': finding.baselineValue?.toString(),
        'absoluteChange': finding.absoluteChange?.toString(),
        'percentageChange': finding.percentageChange?.toString(),
        'supportingMetrics': finding.supportingMetrics,
        'evidence': finding.evidence
            .map(
              (value) => {
                'transactionId': value.transactionId.value,
                'evidenceId': value.evidenceId?.value,
              },
            )
            .toList(growable: false),
        'qualityIssues': finding.qualityIssues
            .map(
              (value) => {
                'code': value.code,
                'detail': value.detail,
                'transactionId': value.transactionId?.value,
              },
            )
            .toList(growable: false),
        'datasetMode': finding.context.datasetMode.name,
        'currencyBasis': finding.context.currencyBasis.name,
        'baseCurrency': finding.context.baseCurrency?.value,
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
              datasetMode: DatasetMode.values.byName(
                payload['datasetMode'] as String? ??
                    DatasetMode.allEligible.name,
              ),
              currencyBasis: CurrencyBasis.values.byName(
                payload['currencyBasis'] as String? ??
                    CurrencyBasis.original.name,
              ),
              baseCurrency: payload['baseCurrency'] == null
                  ? null
                  : CurrencyCode(payload['baseCurrency'] as String),
            ),
            severity: RuleSeverity.values.byName(
              payload['severity'] as String? ?? 'info',
            ),
            lifecycle: FindingLifecycle.values.byName(
              row['lifecycle']! as String,
            ),
            dimension: payload['dimension'] as String?,
            currentValue: payload['currentValue'] == null
                ? null
                : DecimalValue.parse(payload['currentValue'] as String),
            baselineValue: payload['baselineValue'] == null
                ? null
                : DecimalValue.parse(payload['baselineValue'] as String),
            absoluteChange: payload['absoluteChange'] == null
                ? null
                : DecimalValue.parse(payload['absoluteChange'] as String),
            percentageChange: payload['percentageChange'] == null
                ? null
                : DecimalValue.parse(payload['percentageChange'] as String),
            supportingMetrics:
                (payload['supportingMetrics'] as List?)
                    ?.map((value) => value.toString())
                    .toList(growable: false) ??
                const [],
            evidence: _evidenceList(payload['evidence']),
            qualityIssues: _qualityIssues(payload['qualityIssues']),
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

List<EvidenceReference> _evidenceList(Object? value) => value is! List
    ? const []
    : value
          .whereType<Map>()
          .map(
            (item) => EvidenceReference(
              transactionId: TransactionId(item['transactionId'].toString()),
              evidenceId: item['evidenceId'] == null
                  ? null
                  : EvidenceId(item['evidenceId'].toString()),
            ),
          )
          .toList(growable: false);

List<DataQualityIssue> _qualityIssues(Object? value) => value is! List
    ? const []
    : value
          .whereType<Map>()
          .map(
            (item) => DataQualityIssue(
              code: item['code'].toString(),
              detail: item['detail'].toString(),
              transactionId: item['transactionId'] == null
                  ? null
                  : TransactionId(item['transactionId'].toString()),
            ),
          )
          .toList(growable: false);
