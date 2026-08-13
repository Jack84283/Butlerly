import 'dart:convert';

import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';
import '../mappers/sqlite_helpers.dart';

final class SqliteEvidenceRepository implements EvidenceRepository {
  const SqliteEvidenceRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(EvidenceItem value) async {
    try {
      await database.transaction((executor) async {
        await saveProvenance(executor, value.provenance);
        await executor.insert('evidence_items', {
          'id': value.id.value,
          'type': value.type.name,
          'original_name': value.originalName,
          'media_type': value.mediaType,
          'provenance_id': value.provenance.id.value,
          'created_at': value.createdAt.toIso8601String(),
          'source_language': value.sourceLanguage,
          'local_file_name': value.localFileName,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save evidence');
    }
  }

  @override
  Future<void> saveExtraction(Extraction value) async {
    try {
      await database.transaction((executor) async {
        await saveProvenance(executor, value.provenance);
        await executor.insert('extractions', {
          'id': value.id.value,
          'evidence_id': value.evidenceId.value,
          'values_json': jsonEncode(value.values),
          'provenance_id': value.provenance.id.value,
          'created_at': value.createdAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save extraction');
    }
  }

  @override
  Future<void> link(AttachmentLink value) async {
    try {
      await database.connection.insert('attachment_links', {
        'id': value.id.value,
        'transaction_id': value.transactionId.value,
        'evidence_id': value.evidenceId.value,
        'created_at': value.createdAt.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'link evidence');
    }
  }

  @override
  Future<EvidenceItem?> findById(EvidenceId id) async {
    final rows = await database.connection.rawQuery(
      '''SELECT e.*, p.id AS p_id, p.source_type, p.captured_at,
                p.source_id, p.original_representation,
                p.source_language AS p_source_language
         FROM evidence_items e
         INNER JOIN provenances p ON p.id = e.provenance_id
         WHERE e.id = ?''',
      [id.value],
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<List<EvidenceItem>> listForTransaction(TransactionId id) async {
    final rows = await database.connection.rawQuery(
      '''SELECT e.*, p.id AS p_id, p.source_type, p.captured_at,
                p.source_id, p.original_representation,
                p.source_language AS p_source_language
         FROM evidence_items e
         INNER JOIN attachment_links a ON a.evidence_id = e.id
         INNER JOIN provenances p ON p.id = e.provenance_id
         WHERE a.transaction_id = ? ORDER BY a.created_at''',
      [id.value],
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> remove(EvidenceId id) async {
    try {
      await database.transaction((executor) async {
        final rows = await executor.query(
          'evidence_items',
          columns: ['provenance_id'],
          where: 'id = ?',
          whereArgs: [id.value],
        );
        await executor.delete(
          'attachment_links',
          where: 'evidence_id = ?',
          whereArgs: [id.value],
        );
        await executor.delete(
          'evidence_items',
          where: 'id = ?',
          whereArgs: [id.value],
        );
        if (rows.isNotEmpty) {
          await executor.delete(
            'provenances',
            where: 'id = ?',
            whereArgs: [rows.single['provenance_id']],
          );
        }
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'remove evidence');
    }
  }

  static EvidenceItem _fromRow(Map<String, Object?> row) => EvidenceItem(
    id: EvidenceId(row['id']! as String),
    type: EvidenceType.values.byName(row['type']! as String),
    originalName: row['original_name']! as String,
    mediaType: row['media_type']! as String,
    provenance: Provenance(
      id: ProvenanceId(row['p_id']! as String),
      sourceType: ProvenanceSourceType.values.byName(
        row['source_type']! as String,
      ),
      capturedAt: DateTime.parse(row['captured_at']! as String),
      sourceId: row['source_id'] as String?,
      originalRepresentation: row['original_representation'] as String?,
      sourceLanguage: row['p_source_language'] as String?,
    ),
    createdAt: DateTime.parse(row['created_at']! as String),
    sourceLanguage: row['source_language'] as String?,
    localFileName: row['local_file_name'] as String?,
  );
}

final class SqliteSuggestionRepository implements SuggestionRepository {
  const SqliteSuggestionRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(Suggestion value) async {
    try {
      await database.transaction((executor) async {
        await saveProvenance(executor, value.provenance);
        await executor.insert(
          'suggestions',
          _toRow(value),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save suggestion');
    }
  }

  @override
  Future<Suggestion?> findById(SuggestionId id) async {
    final values = await _query('s.id = ?', [id.value]);
    return values.isEmpty ? null : values.single;
  }

  @override
  Future<List<Suggestion>> listForTransaction(TransactionId id) =>
      _query('s.transaction_id = ?', [id.value]);

  Future<List<Suggestion>> _query(String where, List<Object> args) async {
    final rows = await database.connection.rawQuery(
      '''SELECT s.*, p.id AS p_id, p.source_type, p.captured_at,
                p.source_id, p.original_representation,
                p.source_language AS p_source_language
         FROM suggestions s INNER JOIN provenances p ON p.id = s.provenance_id
         WHERE $where ORDER BY s.created_at''',
      args,
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  static Map<String, Object?> _toRow(Suggestion value) => {
    'id': value.id.value,
    'transaction_id': value.transactionId.value,
    'target': value.target.name,
    'proposed_value': value.proposedValue,
    'method': value.method.name,
    'status': value.status.name,
    'provenance_id': value.provenance.id.value,
    'created_at': value.createdAt.toIso8601String(),
    'decided_at': value.decidedAt?.toIso8601String(),
    'confidence': value.confidence,
    'rationale': value.rationale,
    'provider': value.provider,
    'model': value.model,
  };

  static Suggestion _fromRow(Map<String, Object?> row) => Suggestion(
    id: SuggestionId(row['id']! as String),
    transactionId: TransactionId(row['transaction_id']! as String),
    target: SuggestionTarget.values.byName(row['target']! as String),
    proposedValue: row['proposed_value']! as String,
    method: SuggestionMethod.values.byName(row['method']! as String),
    status: SuggestionStatus.values.byName(row['status']! as String),
    provenance: Provenance(
      id: ProvenanceId(row['p_id']! as String),
      sourceType: ProvenanceSourceType.values.byName(
        row['source_type']! as String,
      ),
      capturedAt: DateTime.parse(row['captured_at']! as String),
      sourceId: row['source_id'] as String?,
      originalRepresentation: row['original_representation'] as String?,
      sourceLanguage: row['p_source_language'] as String?,
    ),
    createdAt: DateTime.parse(row['created_at']! as String),
    decidedAt: row['decided_at'] == null
        ? null
        : DateTime.parse(row['decided_at']! as String),
    confidence: row['confidence'] as double?,
    rationale: row['rationale'] as String?,
    provider: row['provider'] as String?,
    model: row['model'] as String?,
  );
}
