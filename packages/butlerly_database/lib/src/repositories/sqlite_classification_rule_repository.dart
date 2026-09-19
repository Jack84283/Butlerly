import 'dart:convert';

import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteClassificationRuleRepository
    implements ClassificationRuleRepository {
  const SqliteClassificationRuleRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(ClassificationRule rule) async {
    try {
      await database.connection.insert('classification_rules', {
        'id': rule.id.value,
        'pattern': rule.pattern,
        'match_mode': rule.matchMode.name,
        'enabled': rule.enabled ? 1 : 0,
        'merchant_id': rule.merchantId?.value,
        'category_id': rule.categoryId?.value,
        'subcategory_id': rule.subcategoryId?.value,
        'tag_ids_json': jsonEncode(
          rule.tagIds.map((value) => value.value).toList(growable: false),
        ),
        'created_at': rule.createdAt.toUtc().toIso8601String(),
        'updated_at': rule.updatedAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save classification rule');
    }
  }

  @override
  Future<ClassificationRule?> findById(ClassificationRuleId id) async {
    final rows = await database.connection.query(
      'classification_rules',
      where: 'id = ?',
      whereArgs: [id.value],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<List<ClassificationRule>> listAll() async {
    final rows = await database.connection.query(
      'classification_rules',
      orderBy: 'enabled DESC, LENGTH(pattern) DESC, pattern COLLATE NOCASE, id',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<void> remove(ClassificationRuleId id) async {
    await database.connection.delete(
      'classification_rules',
      where: 'id = ?',
      whereArgs: [id.value],
    );
  }

  static ClassificationRule _fromRow(Map<String, Object?> row) {
    final rawTags = (jsonDecode(row['tag_ids_json']! as String) as List)
        .cast<String>();
    return ClassificationRule(
      id: ClassificationRuleId(row['id']! as String),
      pattern: row['pattern']! as String,
      matchMode: ClassificationRuleMatchMode.values.byName(
        row['match_mode']! as String,
      ),
      enabled: (row['enabled']! as int) != 0,
      merchantId: row['merchant_id'] == null
          ? null
          : MerchantId(row['merchant_id']! as String),
      categoryId: row['category_id'] == null
          ? null
          : CategoryId(row['category_id']! as String),
      subcategoryId: row['subcategory_id'] == null
          ? null
          : CategoryId(row['subcategory_id']! as String),
      tagIds: rawTags.map(TagId.new).toList(growable: false),
      createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
      updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
    );
  }
}
