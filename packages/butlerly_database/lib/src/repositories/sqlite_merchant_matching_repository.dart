import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteMerchantMatchingConfigurationRepository
    implements MerchantMatchingConfigurationRepository {
  const SqliteMerchantMatchingConfigurationRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<void> saveConfiguration({
    required Merchant merchant,
    required List<MerchantAlias> aliases,
    required List<MerchantNormalizationPattern> patterns,
  }) async {
    try {
      await database.transaction((transaction) async {
        await _saveMerchant(transaction, merchant);
        await transaction.delete(
          'merchant_aliases',
          where: 'merchant_id = ?',
          whereArgs: [merchant.id.value],
        );
        for (final alias in aliases) {
          await transaction.insert('merchant_aliases', {
            'id': alias.id.value,
            'merchant_id': alias.merchantId.value,
            'alias': alias.alias,
            'normalized_alias': alias.normalizedAlias,
            'status': alias.status.name,
            'created_at': alias.createdAt.toIso8601String(),
            'updated_at': alias.updatedAt.toIso8601String(),
          });
        }
        await transaction.delete(
          'merchant_normalization_patterns',
          where: 'merchant_id = ?',
          whereArgs: [merchant.id.value],
        );
        for (final pattern in patterns) {
          await transaction.insert('merchant_normalization_patterns', {
            'id': pattern.id.value,
            'merchant_id': pattern.merchantId.value,
            'pattern': pattern.pattern,
            'normalized_pattern': pattern.normalizedPattern,
            'status': pattern.status.name,
            'created_at': pattern.createdAt.toIso8601String(),
            'updated_at': pattern.updatedAt.toIso8601String(),
          });
        }
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save merchant matching configuration');
    }
  }
}

Future<void> _saveMerchant(DatabaseExecutor executor, Merchant value) async {
  try {
    final existing = await executor.query(
      'merchants',
      columns: ['created_at'],
      where: 'id = ?',
      whereArgs: [value.id.value],
      limit: 1,
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final row = {
      'id': value.id.value,
      'name': value.name,
      'status': value.status.name,
      'raw_name': value.rawName,
      'normalized_name': value.normalizedName,
      'default_category_id': value.defaultCategoryId?.value,
      'default_subcategory_id': value.defaultSubcategoryId?.value,
      'is_built_in': value.isBuiltIn ? 1 : 0,
      'created_at': existing.isEmpty ? now : existing.single['created_at'],
      'updated_at': now,
    };
    if (existing.isEmpty) {
      await executor.insert('merchants', row);
    } else {
      await executor.update(
        'merchants',
        row,
        where: 'id = ?',
        whereArgs: [value.id.value],
      );
    }
  } on DatabaseException catch (error) {
    throw mapDatabaseException(error, 'save merchant matching configuration');
  }
}

final class SqliteMerchantAliasRepository implements MerchantAliasRepository {
  const SqliteMerchantAliasRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(MerchantAlias value) =>
      _save(database.connection, 'merchant_aliases', {
        'id': value.id.value,
        'merchant_id': value.merchantId.value,
        'alias': value.alias,
        'normalized_alias': value.normalizedAlias,
        'status': value.status.name,
        'created_at': value.createdAt.toIso8601String(),
        'updated_at': value.updatedAt.toIso8601String(),
      });

  @override
  Future<MerchantAlias?> findById(MerchantAliasId id) async {
    final rows = await database.connection.query(
      'merchant_aliases',
      where: 'id = ?',
      whereArgs: [id.value],
      limit: 1,
    );
    return rows.isEmpty ? null : _alias(rows.single);
  }

  @override
  Future<List<MerchantAlias>> listForMerchant(MerchantId merchantId) async {
    final rows = await database.connection.query(
      'merchant_aliases',
      where: 'merchant_id = ?',
      whereArgs: [merchantId.value],
      orderBy: 'alias COLLATE NOCASE',
    );
    return rows.map(_alias).toList(growable: false);
  }

  @override
  Future<void> remove(MerchantAliasId id) =>
      _remove(database.connection, 'merchant_aliases', id.value);
}

final class SqliteMerchantNormalizationPatternRepository
    implements MerchantNormalizationPatternRepository {
  const SqliteMerchantNormalizationPatternRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(MerchantNormalizationPattern value) =>
      _save(database.connection, 'merchant_normalization_patterns', {
        'id': value.id.value,
        'merchant_id': value.merchantId.value,
        'pattern': value.pattern,
        'normalized_pattern': value.normalizedPattern,
        'status': value.status.name,
        'created_at': value.createdAt.toIso8601String(),
        'updated_at': value.updatedAt.toIso8601String(),
      });

  @override
  Future<MerchantNormalizationPattern?> findById(
    MerchantNormalizationPatternId id,
  ) async {
    final rows = await database.connection.query(
      'merchant_normalization_patterns',
      where: 'id = ?',
      whereArgs: [id.value],
      limit: 1,
    );
    return rows.isEmpty ? null : _pattern(rows.single);
  }

  @override
  Future<List<MerchantNormalizationPattern>> listForMerchant(
    MerchantId merchantId,
  ) async {
    final rows = await database.connection.query(
      'merchant_normalization_patterns',
      where: 'merchant_id = ?',
      whereArgs: [merchantId.value],
      orderBy: 'pattern COLLATE NOCASE',
    );
    return rows.map(_pattern).toList(growable: false);
  }

  @override
  Future<void> remove(MerchantNormalizationPatternId id) =>
      _remove(database.connection, 'merchant_normalization_patterns', id.value);
}

final class SqliteTransactionRuleRepository
    implements TransactionRuleRepository {
  const SqliteTransactionRuleRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(TransactionRule value) =>
      _save(database.connection, 'transaction_rules', {
        'id': value.id.value,
        'name': value.name,
        'description': value.description,
        'enabled': value.enabled ? 1 : 0,
        'priority': value.priority,
        'merchant_id': value.merchantId?.value,
        'category_id': value.categoryId?.value,
        'payment_source_id': value.paymentSourceId?.value,
        'tag_id': value.tagId?.value,
        'description_contains': value.descriptionContains,
        'raw_counterparty_contains': value.rawCounterpartyContains,
        'assign_merchant_id': value.assignMerchantId?.value,
        'assign_category_id': value.assignCategoryId?.value,
        'assign_subcategory_id': value.assignSubcategoryId?.value,
        'assign_payment_source_id': value.assignPaymentSourceId?.value,
        'assign_tag_id': value.assignTagId?.value,
        'created_at': value.createdAt.toIso8601String(),
        'updated_at': value.updatedAt.toIso8601String(),
      });

  @override
  Future<List<TransactionRule>> listAll() async {
    final rows = await database.connection.query(
      'transaction_rules',
      orderBy: 'priority ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(_rule).toList(growable: false);
  }

  @override
  Future<TransactionRule?> findById(TransactionRuleId id) async {
    final rows = await database.connection.query(
      'transaction_rules',
      where: 'id = ?',
      whereArgs: [id.value],
      limit: 1,
    );
    return rows.isEmpty ? null : _rule(rows.single);
  }

  @override
  Future<void> remove(TransactionRuleId id) =>
      _remove(database.connection, 'transaction_rules', id.value);
}

MerchantAlias _alias(Map<String, Object?> row) => MerchantAlias(
  id: MerchantAliasId(row['id']! as String),
  merchantId: MerchantId(row['merchant_id']! as String),
  alias: row['alias']! as String,
  normalizedAlias: row['normalized_alias']! as String,
  status: MerchantMatchingStatus.values.byName(row['status']! as String),
  createdAt: DateTime.parse(row['created_at']! as String),
  updatedAt: DateTime.parse(row['updated_at']! as String),
);

MerchantNormalizationPattern _pattern(Map<String, Object?> row) =>
    MerchantNormalizationPattern(
      id: MerchantNormalizationPatternId(row['id']! as String),
      merchantId: MerchantId(row['merchant_id']! as String),
      pattern: row['pattern']! as String,
      normalizedPattern: row['normalized_pattern']! as String,
      status: MerchantMatchingStatus.values.byName(row['status']! as String),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );

TransactionRule _rule(Map<String, Object?> row) => TransactionRule(
  id: TransactionRuleId(row['id']! as String),
  name: row['name']! as String,
  description: row['description'] as String?,
  enabled: (row['enabled'] as int? ?? 0) != 0,
  priority: row['priority']! as int,
  merchantId: _id<MerchantId>(row['merchant_id'], MerchantId.new),
  categoryId: _id<CategoryId>(row['category_id'], CategoryId.new),
  paymentSourceId: _id<PaymentSourceId>(
    row['payment_source_id'],
    PaymentSourceId.new,
  ),
  tagId: _id<TagId>(row['tag_id'], TagId.new),
  descriptionContains: row['description_contains'] as String?,
  rawCounterpartyContains: row['raw_counterparty_contains'] as String?,
  assignMerchantId: _id<MerchantId>(row['assign_merchant_id'], MerchantId.new),
  assignCategoryId: _id<CategoryId>(row['assign_category_id'], CategoryId.new),
  assignSubcategoryId: _id<CategoryId>(
    row['assign_subcategory_id'],
    CategoryId.new,
  ),
  assignPaymentSourceId: _id<PaymentSourceId>(
    row['assign_payment_source_id'],
    PaymentSourceId.new,
  ),
  assignTagId: _id<TagId>(row['assign_tag_id'], TagId.new),
  createdAt: DateTime.parse(row['created_at']! as String),
  updatedAt: DateTime.parse(row['updated_at']! as String),
);

T? _id<T>(Object? value, T Function(String) create) =>
    value == null ? null : create(value as String);

Future<void> _save(
  DatabaseExecutor executor,
  String table,
  Map<String, Object?> values,
) async {
  try {
    await executor.insert(
      table,
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  } on DatabaseException catch (error) {
    throw mapDatabaseException(error, 'save $table');
  }
}

Future<void> _remove(DatabaseExecutor executor, String table, String id) async {
  try {
    await executor.delete(table, where: 'id = ?', whereArgs: [id]);
  } on DatabaseException catch (error) {
    throw mapDatabaseException(error, 'delete $table');
  }
}
