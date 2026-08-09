import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

Map<String, Object?> provenanceToRow(Provenance value) => {
  'id': value.id.value,
  'source_type': value.sourceType.name,
  'captured_at': value.capturedAt.toIso8601String(),
  'source_id': value.sourceId,
  'original_representation': value.originalRepresentation,
  'source_language': value.sourceLanguage,
};

Provenance provenanceFromRow(Map<String, Object?> row) => Provenance(
  id: ProvenanceId(row['id']! as String),
  sourceType: ProvenanceSourceType.values.byName(row['source_type']! as String),
  capturedAt: DateTime.parse(row['captured_at']! as String),
  sourceId: row['source_id'] as String?,
  originalRepresentation: row['original_representation'] as String?,
  sourceLanguage: row['source_language'] as String?,
);

Future<void> saveProvenance(DatabaseExecutor executor, Provenance value) =>
    executor.insert(
      'provenances',
      provenanceToRow(value),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

DecimalValue decimalFromRow(
  Map<String, Object?> row,
  String coefficient,
  String scale,
) => DecimalValue.fromParts(
  coefficient: BigInt.parse(row[coefficient]! as String),
  scale: row[scale]! as int,
);

Map<String, Object> decimalToColumns(
  DecimalValue value,
  String coefficient,
  String scale,
) => {coefficient: value.coefficient.toString(), scale: value.scale};
