import 'dart:convert';
import 'dart:io';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/persisted_analysis_rule_validation.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:path/path.dart' as path;

/// SQLite-backed, read-only integrity scanner.
///
/// Scanning never updates source tables. The only writes made by [runReport]
/// are to the report-history tables, which are diagnostic artifacts owned by
/// this service.
final class LocalDataIntegrityReportService
    implements DataIntegrityReportService {
  LocalDataIntegrityReportService(
    this.database,
    this.localDataManager, {
    DateTime Function()? clock,
    AnalysisConsistencyGate? consistencyGate,
  }) : _clock = clock ?? DateTime.now,
       _consistencyGate = consistencyGate;

  final LocalDatabase database;
  final LocalDataManager localDataManager;
  final DateTime Function() _clock;
  final AnalysisConsistencyGate? _consistencyGate;

  @override
  Future<DataIntegrityReport?> latestReport() async {
    final rows = await database.database.rawQuery(
      'SELECT * FROM data_integrity_reports '
      'ORDER BY scanned_at DESC, id DESC LIMIT 1',
    );
    if (rows.isEmpty) return null;
    return _readReport(rows.first);
  }

  @override
  Future<List<DataIntegrityReport>> reportHistory({int limit = 20}) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final rows = await database.database.rawQuery(
      'SELECT * FROM data_integrity_reports '
      'ORDER BY scanned_at DESC, id DESC LIMIT $limit',
    );
    return List.unmodifiable([for (final row in rows) await _readReport(row)]);
  }

  @override
  Future<DataIntegrityReport> runReport() {
    Future<DataIntegrityReport> locked() =>
        EvidenceMutationLock.runExclusive(_runReportUnlocked);
    final gate = _consistencyGate;
    return gate == null ? locked() : gate.runExclusive(locked);
  }

  Future<DataIntegrityReport> _runReportUnlocked() async {
    final scannedAt = _clock().toUtc();
    final findings = await _scan(scannedAt);
    final baseId = 'integrity-report-${scannedAt.microsecondsSinceEpoch}';
    late DataIntegrityReport report;

    await database.database.transaction((transaction) async {
      var reportId = baseId;
      var suffix = 0;
      while ((await transaction.query(
        'data_integrity_reports',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [reportId],
        limit: 1,
      )).isNotEmpty) {
        suffix++;
        reportId = '$baseId-$suffix';
      }
      report = DataIntegrityReport(
        id: reportId,
        scannedAtUtc: scannedAt,
        findings: List.unmodifiable(findings),
      );
      await transaction.insert('data_integrity_reports', {
        'id': report.id,
        'scanned_at': report.scannedAtUtc.toIso8601String(),
        'finding_count': report.findings.length,
      });
      for (final finding in report.findings) {
        await transaction.insert('data_integrity_findings', {
          'id': finding.id,
          'report_id': report.id,
          'code': finding.code,
          'category': finding.category.name,
          'severity': finding.severity.name,
          'description': finding.description,
          'affected_records': jsonEncode([
            for (final record in finding.affectedRecords)
              {'type': record.type, 'id': record.id},
          ]),
          'context': jsonEncode(finding.context),
          'recommended_action': finding.recommendedAction,
          'detected_at': finding.detectedAtUtc.toIso8601String(),
        });
      }
    });
    return report;
  }

  Future<List<DataIntegrityFinding>> _scan(DateTime detectedAtUtc) async {
    final findings = <DataIntegrityFinding>[];
    final evidenceRoot = await localDataManager.evidenceDirectory();
    final links = await database.database.rawQuery(
      'SELECT transaction_id, evidence_id FROM attachment_links',
    );
    final transactionsByEvidence = <String, List<String>>{};
    for (final row in links) {
      final transactionId = row['transaction_id'];
      final evidenceId = row['evidence_id'];
      if (transactionId is! String || evidenceId is! String) continue;
      transactionsByEvidence
          .putIfAbsent(evidenceId, () => [])
          .add(transactionId);
    }

    final evidenceRows = await database.database.rawQuery(
      'SELECT id, type, local_file_name FROM evidence_items ORDER BY id',
    );
    for (final row in evidenceRows) {
      final evidenceId = row['id'];
      if (evidenceId is! String || evidenceId.isEmpty) continue;
      final evidenceType = row['type'] is String
          ? row['type']! as String
          : 'attachment';
      final records = <DataIntegrityRecordReference>[
        DataIntegrityRecordReference(type: 'evidence', id: evidenceId),
        for (final transactionId
            in transactionsByEvidence[evidenceId] ?? const <String>[])
          DataIntegrityRecordReference(type: 'transaction', id: transactionId),
      ];
      final rawPath = row['local_file_name'];
      if (rawPath == null || (rawPath is String && rawPath.trim().isEmpty)) {
        findings.add(
          _finding(
            code: 'missing_evidence_file',
            category: _evidenceCategory(evidenceType),
            severity: DataIntegrityFindingSeverity.warning,
            description: _missingEvidenceDescription(evidenceType),
            records: records,
            context: {'evidenceType': evidenceType, 'unsafe': 'false'},
            recommendedAction:
                'Attach the original file again from the affected record.',
            detectedAtUtc: detectedAtUtc,
          ),
        );
        continue;
      }
      if (rawPath is! String) {
        findings.add(
          _finding(
            code: 'invalid_evidence_reference',
            category: DataIntegrityFindingCategory.invalidFileReference,
            severity: DataIntegrityFindingSeverity.error,
            description: 'An attachment has an invalid local file reference.',
            records: records,
            context: {'evidenceType': evidenceType, 'unsafe': 'true'},
            recommendedAction:
                'Review the affected record and attach the file again.',
            detectedAtUtc: detectedAtUtc,
          ),
        );
        continue;
      }

      try {
        final normalized = await validateEvidenceReferencePath(
          evidenceRoot,
          rawPath,
        );
        final file = File(path.join(evidenceRoot.path, normalized));
        if (!await file.exists() ||
            await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file) {
          findings.add(
            _finding(
              code: 'missing_evidence_file',
              category: _evidenceCategory(evidenceType),
              severity: DataIntegrityFindingSeverity.warning,
              description: _missingEvidenceDescription(evidenceType),
              records: records,
              context: {'evidenceType': evidenceType},
              recommendedAction:
                  'Attach the original file again from the affected record.',
              detectedAtUtc: detectedAtUtc,
            ),
          );
        }
      } on Object {
        findings.add(
          _finding(
            code: 'invalid_evidence_reference',
            category: DataIntegrityFindingCategory.invalidFileReference,
            severity: DataIntegrityFindingSeverity.error,
            description:
                'An attachment points to an unsafe local file reference.',
            records: records,
            context: {'evidenceType': evidenceType, 'unsafe': 'true'},
            recommendedAction:
                'Review the affected record and attach the file again.',
            detectedAtUtc: detectedAtUtc,
          ),
        );
      }
    }

    await _scanForeignKeys(findings, detectedAtUtc);
    await _scanBudgetReferences(findings, detectedAtUtc);
    await _scanAnalysisConfiguration(findings, detectedAtUtc);
    return findings;
  }

  Future<void> _scanBudgetReferences(
    List<DataIntegrityFinding> findings,
    DateTime detectedAtUtc,
  ) async {
    final budgets = await database.database.query('budgets', orderBy: 'id');
    for (final row in budgets) {
      final budgetId = row['id'];
      final scope = row['scope'];
      final scopeId = row['scope_id'];
      if (budgetId is! String) continue;
      final budgetRecord = [
        DataIntegrityRecordReference(type: 'budget', id: budgetId),
      ];
      if (scope == 'overall' && scopeId == null) continue;
      if (scope is! String ||
          !{'category', 'subcategory', 'merchant', 'overall'}.contains(scope) ||
          (scope == 'overall' && scopeId != null) ||
          (scope != 'overall' && scopeId is! String)) {
        findings.add(
          _finding(
            code: 'invalid_budget_scope_reference',
            category: DataIntegrityFindingCategory.relationshipInconsistency,
            severity: DataIntegrityFindingSeverity.error,
            description: 'A budget has an invalid scope reference.',
            records: budgetRecord,
            context: {'scope': '${scope ?? 'unknown'}'},
            recommendedAction:
                'Review the budget scope and choose an available category, subcategory, or merchant.',
            detectedAtUtc: detectedAtUtc,
          ),
        );
        continue;
      }
      final targetTable = scope == 'merchant' ? 'merchants' : 'categories';
      final scopedId = scopeId as String;
      final target = await database.database.query(
        targetTable,
        columns: targetTable == 'categories' ? ['id', 'parent_id'] : ['id'],
        where: 'id = ?',
        whereArgs: [scopedId],
        limit: 1,
      );
      if (target.isEmpty) {
        findings.add(
          _finding(
            code: 'missing_budget_scope_record',
            category: DataIntegrityFindingCategory.missingReferencedRecord,
            severity: DataIntegrityFindingSeverity.error,
            description: 'A budget points to a record that is unavailable.',
            records: [
              ...budgetRecord,
              DataIntegrityRecordReference(type: targetTable, id: scopedId),
            ],
            context: {'scope': scope},
            recommendedAction:
                'Review the budget and select an available record for its scope.',
            detectedAtUtc: detectedAtUtc,
          ),
        );
      } else if (targetTable == 'categories') {
        final parentId = target.single['parent_id'];
        final validHierarchy = switch (scope) {
          'category' => parentId == null,
          'subcategory' =>
            parentId is String &&
                parentId.isNotEmpty &&
                (await database.database.query(
                  'categories',
                  columns: ['id'],
                  where: 'id = ? AND parent_id IS NULL',
                  whereArgs: [parentId],
                  limit: 1,
                )).isNotEmpty,
          _ => true,
        };
        if (!validHierarchy) {
          findings.add(
            _finding(
              code: 'invalid_budget_scope_reference',
              category: DataIntegrityFindingCategory.relationshipInconsistency,
              severity: DataIntegrityFindingSeverity.error,
              description:
                  'A budget references a category with an incompatible hierarchy.',
              records: [
                ...budgetRecord,
                DataIntegrityRecordReference(type: 'category', id: scopedId),
              ],
              context: {
                'scope': scope,
                if (parentId is String && parentId.isNotEmpty)
                  'parentId': parentId,
              },
              recommendedAction:
                  'Review the budget and select a category or subcategory with the matching scope.',
              detectedAtUtc: detectedAtUtc,
            ),
          );
        }
      }
    }
  }

  Future<void> _scanForeignKeys(
    List<DataIntegrityFinding> findings,
    DateTime detectedAtUtc,
  ) async {
    final rows = await database.database.rawQuery('PRAGMA foreign_key_check');
    if (rows.isEmpty) return;
    final byTable = <String, int>{};
    final records = <String, DataIntegrityRecordReference>{};
    for (final row in rows) {
      final table = row['table'];
      if (table is String && table.isNotEmpty) {
        byTable.update(table, (count) => count + 1, ifAbsent: () => 1);
      }
      final record = await _foreignKeyViolationRecord(row);
      if (record != null) {
        records['${record.type}:${record.id}'] = record;
      }
    }
    findings.add(
      _finding(
        code: 'missing_referenced_record',
        category: DataIntegrityFindingCategory.missingReferencedRecord,
        severity: DataIntegrityFindingSeverity.error,
        description:
            'One or more records refer to local records that are unavailable.',
        records: records.values.toList(growable: false),
        context: {
          'violationCount': rows.length.toString(),
          'tables': byTable.keys.join(','),
        },
        recommendedAction:
            'Review the affected records and restore the missing related data from a trusted source.',
        detectedAtUtc: detectedAtUtc,
      ),
    );
  }

  Future<DataIntegrityRecordReference?> _foreignKeyViolationRecord(
    Map<String, Object?> violation,
  ) async {
    final table = violation['table'];
    final rowId = violation['rowid'];
    if (table is! String || table.isEmpty || rowId == null) return null;

    final recordType = _recordTypeForTable(table);
    try {
      final quotedTable = '"${table.replaceAll('"', '""')}"';
      final columns = await database.database.rawQuery(
        'PRAGMA table_info($quotedTable)',
      );
      final primaryKeys =
          columns
              .where(
                (column) => column['pk'] is int && (column['pk']! as int) > 0,
              )
              .toList()
            ..sort(
              (left, right) =>
                  (left['pk']! as int).compareTo(right['pk']! as int),
            );
      final recordRows = await database.database.rawQuery(
        'SELECT * FROM $quotedTable WHERE rowid = ? LIMIT 1',
        [rowId],
      );
      if (recordRows.isEmpty) {
        return DataIntegrityRecordReference(type: recordType, id: 'row:$rowId');
      }
      final record = recordRows.single;
      final keyColumns = primaryKeys.isEmpty
          ? const <String>['rowid']
          : [
              for (final column in primaryKeys)
                if (column['name'] is String) column['name']! as String,
            ];
      final id = keyColumns.length == 1 && keyColumns.single == 'rowid'
          ? 'row:$rowId'
          : keyColumns.map((column) => '${record[column]}').join('|');
      return DataIntegrityRecordReference(type: recordType, id: id);
    } on Object {
      return DataIntegrityRecordReference(type: recordType, id: 'row:$rowId');
    }
  }

  String _recordTypeForTable(String table) => switch (table) {
    'transactions' => 'transaction',
    'evidence_items' => 'evidence',
    'attachment_links' => 'attachment',
    'budgets' => 'budget',
    'categories' => 'category',
    'merchants' => 'merchant',
    'analysis_rule_definitions' ||
    'analysis_rule_activations' ||
    'analysis_rule_configurations' ||
    'analysis_rule_provenance' => 'analysisRule',
    _ => 'relatedRecord',
  };

  Future<void> _scanAnalysisConfiguration(
    List<DataIntegrityFinding> findings,
    DateTime detectedAtUtc,
  ) async {
    final definitions = await database.database.rawQuery(
      'SELECT rule_id, rule_version, source_type, canonical_definition, '
      'definition_hash, validation_status FROM analysis_rule_definitions '
      'ORDER BY rule_id, rule_version',
    );
    final validDefinitions = <String>{};
    for (final row in definitions) {
      final ruleId = row['rule_id'];
      final version = row['rule_version'];
      if (ruleId is! String || version is! String) continue;
      final identity = '$ruleId@$version';
      final valid = isSemanticallyValidPersistedAnalysisRule(row);
      if (valid) validDefinitions.add(identity);
      if (!valid) {
        findings.add(
          _finding(
            code: 'invalid_analysis_rule_definition',
            category: DataIntegrityFindingCategory.analysisInconsistency,
            severity: DataIntegrityFindingSeverity.error,
            description:
                'An analysis rule definition is incomplete or invalid.',
            records: [
              DataIntegrityRecordReference(type: 'analysisRule', id: identity),
            ],
            context: {'sourceType': '${row['source_type'] ?? 'unknown'}'},
            recommendedAction:
                'Review the rule configuration or reinstall the rule from its original source.',
            detectedAtUtc: detectedAtUtc,
          ),
        );
      }
    }

    final provenance = await database.database.rawQuery(
      'SELECT p.rule_id, p.rule_version, p.definition_hash, p.source_type, '
      'd.definition_hash AS installed_hash, d.source_type AS installed_source_type '
      'FROM analysis_rule_provenance p '
      'LEFT JOIN analysis_rule_definitions d '
      'ON d.rule_id = p.rule_id AND d.rule_version = p.rule_version',
    );
    for (final row in provenance) {
      final ruleId = row['rule_id'];
      final version = row['rule_version'];
      if (ruleId is! String || version is! String) continue;
      final recordedHash = row['definition_hash'];
      final installedHash = row['installed_hash'];
      final recordedSourceType = row['source_type'];
      final installedSourceType = row['installed_source_type'];
      if (installedHash != recordedHash ||
          installedSourceType != recordedSourceType) {
        findings.add(
          _finding(
            code: 'analysis_rule_provenance_mismatch',
            category: DataIntegrityFindingCategory.analysisInconsistency,
            severity: DataIntegrityFindingSeverity.warning,
            description:
                'An analysis rule provenance record does not match its definition.',
            records: [
              DataIntegrityRecordReference(
                type: 'analysisRule',
                id: '$ruleId@$version',
              ),
            ],
            context: const {},
            recommendedAction:
                'Review the rule source and configuration before relying on its results.',
            detectedAtUtc: detectedAtUtc,
          ),
        );
      }
    }

    final activations = await database.database.rawQuery(
      'SELECT a.rule_id, a.active_rule_version, a.enabled '
      'FROM analysis_rule_activations a',
    );
    for (final row in activations) {
      final ruleId = row['rule_id'];
      final version = row['active_rule_version'];
      if (ruleId is! String || version is! String) continue;
      if (row['enabled'] == 1 &&
          !validDefinitions.contains('$ruleId@$version')) {
        findings.add(
          _finding(
            code: 'active_analysis_rule_missing',
            category: DataIntegrityFindingCategory.analysisInconsistency,
            severity: DataIntegrityFindingSeverity.error,
            description:
                'An enabled analysis rule is missing its active definition.',
            records: [
              DataIntegrityRecordReference(
                type: 'analysisRule',
                id: '$ruleId@$version',
              ),
            ],
            context: const {},
            recommendedAction:
                'Review the rule configuration before running analysis again.',
            detectedAtUtc: detectedAtUtc,
          ),
        );
      }
    }

    final configurations = await database.database.rawQuery(
      'SELECT c.rule_id, c.configuration, '
      '(SELECT d.source_type FROM analysis_rule_definitions d '
      'WHERE d.rule_id = c.rule_id '
      'ORDER BY d.installed_at DESC, d.rule_version DESC LIMIT 1) '
      'AS source_type '
      'FROM analysis_rule_configurations c',
    );
    for (final row in configurations) {
      final ruleId = row['rule_id'];
      final configuration = row['configuration'];
      if (ruleId is! String) continue;
      var valid = false;
      if (configuration is String) {
        try {
          final decoded = jsonDecode(configuration);
          valid = decoded is Map || decoded is List;
        } on Object {
          valid = false;
        }
      }
      if (!valid) {
        findings.add(
          _finding(
            code: 'invalid_analysis_rule_configuration',
            category: _isUserOwnedRuleSource(row['source_type'])
                ? DataIntegrityFindingCategory.invalidCustomConfiguration
                : DataIntegrityFindingCategory.analysisInconsistency,
            severity: DataIntegrityFindingSeverity.error,
            description: 'An analysis rule configuration is not valid JSON.',
            records: [
              DataIntegrityRecordReference(type: 'analysisRule', id: ruleId),
            ],
            context: {'sourceType': '${row['source_type'] ?? 'unknown'}'},
            recommendedAction:
                'Review the rule configuration and correct it before running analysis.',
            detectedAtUtc: detectedAtUtc,
          ),
        );
      }
    }
  }

  DataIntegrityFinding _finding({
    required String code,
    required DataIntegrityFindingCategory category,
    required DataIntegrityFindingSeverity severity,
    required String description,
    required List<DataIntegrityRecordReference> records,
    required Map<String, String> context,
    required String recommendedAction,
    required DateTime detectedAtUtc,
  }) {
    final stableRecords =
        records.map((record) => '${record.type}:${record.id}').toSet().toList()
          ..sort();
    return DataIntegrityFinding(
      id: '$code:${stableRecords.join('|')}',
      code: code,
      category: category,
      severity: severity,
      description: description,
      affectedRecords: List.unmodifiable(records),
      context: Map.unmodifiable(context),
      recommendedAction: recommendedAction,
      detectedAtUtc: detectedAtUtc,
    );
  }

  DataIntegrityFindingCategory _evidenceCategory(String type) =>
      type.toLowerCase().contains('receipt')
      ? DataIntegrityFindingCategory.missingReceipt
      : DataIntegrityFindingCategory.missingAttachment;

  String _missingEvidenceDescription(String type) =>
      type.toLowerCase().contains('receipt')
      ? 'A receipt linked to a transaction could not be found in local storage.'
      : 'An attachment linked to a record could not be found in local storage.';

  bool _isUserOwnedRuleSource(Object? sourceType) =>
      sourceType == 'custom' || sourceType == 'user';

  Future<DataIntegrityReport> _readReport(Map<String, Object?> row) async {
    final reportId = row['id'];
    final scannedAt = row['scanned_at'];
    if (reportId is! String || scannedAt is! String) {
      throw const FormatException('Integrity report metadata is invalid.');
    }
    final findingRows = await database.database.query(
      'data_integrity_findings',
      where: 'report_id = ?',
      whereArgs: [reportId],
      orderBy: 'id',
    );
    final findings = <DataIntegrityFinding>[];
    for (final findingRow in findingRows) {
      final id = findingRow['id'];
      final code = findingRow['code'];
      final category = findingRow['category'];
      final severity = findingRow['severity'];
      final description = findingRow['description'];
      final affectedRecords = findingRow['affected_records'];
      final context = findingRow['context'];
      final recommendedAction = findingRow['recommended_action'];
      final detectedAt = findingRow['detected_at'];
      if (id is! String ||
          code is! String ||
          category is! String ||
          severity is! String ||
          description is! String ||
          affectedRecords is! String ||
          context is! String ||
          recommendedAction is! String ||
          detectedAt is! String) {
        throw const FormatException('Integrity report finding is invalid.');
      }
      final decodedRecords = jsonDecode(affectedRecords);
      final decodedContext = jsonDecode(context);
      if (decodedRecords is! List || decodedContext is! Map) {
        throw const FormatException(
          'Integrity report finding payload is invalid.',
        );
      }
      findings.add(
        DataIntegrityFinding(
          id: id,
          code: code,
          category: DataIntegrityFindingCategory.values.byName(category),
          severity: DataIntegrityFindingSeverity.values.byName(severity),
          description: description,
          affectedRecords: [
            for (final raw in decodedRecords)
              if (raw is Map && raw['type'] is String && raw['id'] is String)
                DataIntegrityRecordReference(
                  type: raw['type']! as String,
                  id: raw['id']! as String,
                ),
          ],
          context: {
            for (final entry in decodedContext.entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String,
          },
          recommendedAction: recommendedAction,
          detectedAtUtc: DateTime.parse(detectedAt).toUtc(),
        ),
      );
    }
    return DataIntegrityReport(
      id: reportId,
      scannedAtUtc: DateTime.parse(scannedAt).toUtc(),
      findings: List.unmodifiable(findings),
    );
  }
}
