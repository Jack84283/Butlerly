import 'dart:convert';

import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';

/// SQLite-backed storage for incidental backup/restore findings.
///
/// This store owns only diagnostic records. It never updates the financial
/// source tables and it does not run a comprehensive integrity scan.
final class LocalOperationDiagnosticsStore
    implements OperationDiagnosticsStore {
  LocalOperationDiagnosticsStore(this.database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LocalDatabase database;
  final DateTime Function() _clock;

  @override
  Future<void> record({
    required String operation,
    required List<DataIntegrityFinding> findings,
  }) async {
    if (operation.trim().isEmpty || findings.isEmpty) return;
    final detectedAt = _clock().toUtc();
    await database.database.transaction((transaction) async {
      for (var index = 0; index < findings.length; index++) {
        final finding = findings[index];
        var id = 'operation-${detectedAt.microsecondsSinceEpoch}-$index';
        var suffix = 0;
        while ((await transaction.query(
          'operation_diagnostics',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [id],
          limit: 1,
        )).isNotEmpty) {
          suffix++;
          id = 'operation-${detectedAt.microsecondsSinceEpoch}-$index-$suffix';
        }
        await transaction.insert('operation_diagnostics', {
          'id': id,
          'operation': operation,
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
  }

  @override
  Future<List<OperationDiagnostic>> recent({int limit = 20}) async {
    if (limit < 1) throw ArgumentError.value(limit, 'limit');
    final rows = await database.database.rawQuery(
      'SELECT * FROM operation_diagnostics '
      'ORDER BY detected_at DESC, id DESC LIMIT $limit',
    );
    return List.unmodifiable([for (final row in rows) _read(row)]);
  }

  OperationDiagnostic _read(Map<String, Object?> row) {
    final id = row['id'];
    final operation = row['operation'];
    final code = row['code'];
    final category = row['category'];
    final severity = row['severity'];
    final description = row['description'];
    final affectedRecords = row['affected_records'];
    final context = row['context'];
    final recommendedAction = row['recommended_action'];
    final detectedAt = row['detected_at'];
    if (id is! String ||
        operation is! String ||
        code is! String ||
        category is! String ||
        severity is! String ||
        description is! String ||
        affectedRecords is! String ||
        context is! String ||
        recommendedAction is! String ||
        detectedAt is! String) {
      throw const FormatException('Operation diagnostic is invalid.');
    }
    final decodedRecords = jsonDecode(affectedRecords);
    final decodedContext = jsonDecode(context);
    if (decodedRecords is! List || decodedContext is! Map) {
      throw const FormatException('Operation diagnostic payload is invalid.');
    }
    return OperationDiagnostic(
      id: id,
      operation: operation,
      finding: DataIntegrityFinding(
        id: '$operation:$code:$id',
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
}
