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
    final result = <String, String>{
      for (final row in rows) row[idColumn]! as String: row['label']! as String,
    };
    // Preserve readability for databases created before MD-0001 stable IDs
    // were introduced. Legacy rows are mapped by their persisted English
    // master label; the localized value still comes from translation tables.
    final masterTable = masterType == 'category' ? 'categories' : 'tags';
    final masters = await database.connection.query(
      masterTable,
      columns: ['id', 'name'],
    );
    final englishRows = await database.connection.query(
      table,
      columns: [idColumn, 'label'],
      where: 'locale = ?',
      whereArgs: ['en'],
    );
    final englishByLabel = {
      for (final row in englishRows)
        (row['label']! as String).trim().toLowerCase():
            row[idColumn]! as String,
    };
    final localizedByMasterId = {
      for (final row in rows) row[idColumn]! as String: row['label']! as String,
    };
    for (final master in masters) {
      final id = master['id']! as String;
      if (result.containsKey(id)) continue;
      final canonicalId =
          englishByLabel[(master['name']! as String).trim().toLowerCase()];
      if (canonicalId != null && localizedByMasterId.containsKey(canonicalId)) {
        result[id] = localizedByMasterId[canonicalId]!;
      }
    }
    return result;
  }
}
