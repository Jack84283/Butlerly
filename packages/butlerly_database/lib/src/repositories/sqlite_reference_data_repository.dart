import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteReferenceDataRepository implements ReferenceDataRepository {
  const SqliteReferenceDataRepository(this.database);

  final ButlerlyDatabase database;

  static const _legacyAliases = <String, String>{
    'transaction_direction.expense': 'transaction.direction.expense',
    'transaction_direction.income': 'transaction.direction.income',
    'transaction_direction.transfer': 'transaction.direction.transfer',
    'payment_source_type.card': 'payment_source.type.credit_card',
    'payment_source_type.debit_card': 'payment_source.type.debit_card',
    'payment_source_type.account': 'payment_source.type.bank_account',
    'payment_source_type.cash': 'payment_source.type.cash',
    'payment_source_type.wallet': 'payment_source.type.digital_wallet',
    'payment_source_type.other': 'payment_source.type.other',
    'card_network.amex': 'card_network.american_express',
    'evidence_type.imported_record': 'evidence.type.import',
  };

  @override
  Future<void> save(ReferenceData value) async {
    await database.connection.insert('reference_data', {
      'id': value.id.value,
      'code': value.code,
      'type': value.type,
      'origin': value.origin.name,
      'status': value.status.name,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<ReferenceData?> findById(ReferenceDataId id) async {
    final canonicalId = _legacyAliases[id.value] ?? id.value;
    final rows = await database.connection.query(
      'reference_data',
      where: 'id = ? OR id = ?',
      whereArgs: [id.value, canonicalId],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<List<ReferenceData>> list({
    String? type,
    bool includeArchived = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (type != null) {
      where.add('type = ?');
      args.add(type);
    }
    if (!includeArchived) where.add('status = ?');
    if (!includeArchived) args.add(ReferenceDataStatus.active.name);
    final rows = await database.connection.query(
      'reference_data',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'code',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<Map<String, String>> labels({
    required String type,
    required String locale,
    bool includeArchived = false,
  }) async {
    final rows = await database.connection.rawQuery(
      '''SELECT r.id, r.code, r.type, t.label
         FROM reference_data r
         JOIN reference_data_translations t
           ON t.reference_data_id = r.id
         WHERE t.locale = ?${includeArchived ? '' : ' AND r.status = ?'}
         ORDER BY r.code''',
      includeArchived ? [locale] : [locale, ReferenceDataStatus.active.name],
    );
    final result = <String, String>{};
    for (final row in rows) {
      final id = _legacyAliases[row['id']! as String] ?? row['id']! as String;
      if (!id.startsWith('$type.')) continue;
      result[id] = row['label']! as String;
    }
    return result;
  }

  @override
  Future<void> saveTranslation({
    required ReferenceDataId id,
    required String locale,
    required String label,
  }) async {
    await database.connection.insert('reference_data_translations', {
      'reference_data_id': id.value,
      'locale': locale,
      'label': label,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  ReferenceData _fromRow(Map<String, Object?> row) => ReferenceData(
    id: ReferenceDataId(row['id']! as String),
    code: row['code']! as String,
    type: row['type']! as String,
    origin: ReferenceDataOrigin.values.byName(row['origin']! as String),
    status: ReferenceDataStatus.values.byName(row['status']! as String),
  );
}
