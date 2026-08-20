import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqlitePaymentSourceRepository implements PaymentSourceRepository {
  const SqlitePaymentSourceRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(PaymentSource value) =>
      _write(database.connection, 'payment_sources', {
        'id': value.id.value,
        'name': value.name,
        'type': value.type.name,
        'status': value.status.name,
        'display_identity': value.displayIdentity,
        'last_four': value.lastFour,
      });

  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async {
    final row = await _find(database.connection, 'payment_sources', id.value);
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<PaymentSource>> listAll() async => (await _list(
    database.connection,
    'payment_sources',
  )).map(_fromRow).toList(growable: false);

  static PaymentSource _fromRow(Map<String, Object?> row) => PaymentSource(
    id: PaymentSourceId(row['id']! as String),
    name: row['name']! as String,
    type: PaymentSourceType.values.byName(row['type']! as String),
    status: PaymentSourceStatus.values.byName(row['status']! as String),
    displayIdentity: row['display_identity'] as String?,
    lastFour: row['last_four'] as String?,
  );
}

final class SqliteMerchantRepository implements MerchantRepository {
  const SqliteMerchantRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(Merchant value) =>
      _write(database.connection, 'merchants', {
        'id': value.id.value,
        'name': value.name,
        'status': value.status.name,
        'raw_name': value.rawName,
      });

  @override
  Future<Merchant?> findById(MerchantId id) async {
    final row = await _find(database.connection, 'merchants', id.value);
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<Merchant>> listAll() async => (await _list(
    database.connection,
    'merchants',
  )).map(_fromRow).toList(growable: false);

  static Merchant _fromRow(Map<String, Object?> row) => Merchant(
    id: MerchantId(row['id']! as String),
    name: row['name']! as String,
    status: MerchantStatus.values.byName(row['status'] as String? ?? 'active'),
    rawName: row['raw_name'] as String?,
  );
}

final class SqliteCategoryRepository implements CategoryRepository {
  const SqliteCategoryRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(Category value) =>
      _write(database.connection, 'categories', {
        'id': value.id.value,
        'name': value.name,
        'origin': value.origin.name,
        'parent_id': value.parentId?.value,
        'status': value.status.name,
      });

  @override
  Future<Category?> findById(CategoryId id) async {
    final row = await _find(database.connection, 'categories', id.value);
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<Category>> listAll() async => (await _list(
    database.connection,
    'categories',
  )).map(_fromRow).toList(growable: false);

  static Category _fromRow(Map<String, Object?> row) => Category(
    id: CategoryId(row['id']! as String),
    name: row['name']! as String,
    origin: CategoryOrigin.values.byName(row['origin']! as String),
    parentId: row['parent_id'] == null
        ? null
        : CategoryId(row['parent_id']! as String),
    status: CategoryStatus.values.byName(row['status'] as String? ?? 'active'),
  );
}

final class SqliteTagRepository implements TagRepository {
  const SqliteTagRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(Tag value) => _write(database.connection, 'tags', {
    'id': value.id.value,
    'name': value.name,
    'status': value.status.name,
  });

  @override
  Future<Tag?> findById(TagId id) async {
    final row = await _find(database.connection, 'tags', id.value);
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<List<Tag>> listAll() async => (await _list(
    database.connection,
    'tags',
  )).map(_fromRow).toList(growable: false);

  static Tag _fromRow(Map<String, Object?> row) => Tag(
    id: TagId(row['id']! as String),
    name: row['name']! as String,
    status: TagStatus.values.byName(row['status'] as String? ?? 'active'),
  );
}

Future<void> _write(
  DatabaseExecutor executor,
  String table,
  Map<String, Object?> row,
) async {
  try {
    await executor.insert(
      table,
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  } on DatabaseException catch (error) {
    throw mapDatabaseException(error, 'save $table');
  }
}

Future<Map<String, Object?>?> _find(
  DatabaseExecutor executor,
  String table,
  String id,
) async {
  final rows = await executor.query(table, where: 'id = ?', whereArgs: [id]);
  return rows.isEmpty ? null : rows.single;
}

Future<List<Map<String, Object?>>> _list(
  DatabaseExecutor executor,
  String table,
) => executor.query(table, orderBy: 'name COLLATE NOCASE');
