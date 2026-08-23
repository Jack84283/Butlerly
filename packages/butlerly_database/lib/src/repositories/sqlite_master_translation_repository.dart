import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteMasterTranslationRepository
    implements MasterTranslationRepository {
  const SqliteMasterTranslationRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<void> saveAll(List<MasterTranslation> translations) async {
    await database.transaction((transaction) async {
      for (final value in translations) {
        final table = switch (value.masterType) {
          'category' => 'category_translations',
          'tag' => 'tag_translations',
          _ => throw const RepositoryException(
            RepositoryFailureCode.constraint,
            'save master translation',
          ),
        };
        final idColumn = value.masterType == 'category'
            ? 'category_id'
            : 'tag_id';
        await transaction.insert(table, {
          idColumn: value.masterId,
          'locale': value.locale,
          'label': value.label,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  @override
  Future<Map<String, String>> labels({
    required String masterType,
    required String locale,
  }) async {
    final table = switch (masterType) {
      'category' => 'category_translations',
      'tag' => 'tag_translations',
      _ => throw const RepositoryException(
        RepositoryFailureCode.constraint,
        'load master translations',
      ),
    };
    final idColumn = masterType == 'category' ? 'category_id' : 'tag_id';
    final rows = await database.connection.query(
      table,
      columns: [idColumn, 'label'],
      where: 'locale = ?',
      whereArgs: [locale],
    );
    return {
      for (final row in rows) row[idColumn]! as String: row['label']! as String,
    };
  }
}
