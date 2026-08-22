import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteUserPreferenceRepository implements UserPreferenceRepository {
  const SqliteUserPreferenceRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<UserPreference?> load() async {
    try {
      final rows = await database.connection.query(
        'user_preferences',
        where: 'id = 1',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.single;
      return UserPreference(
        locale: row['locale']! as String,
        baseCurrency: CurrencyCode(row['base_currency']! as String),
        timeZoneId: row['time_zone_id']! as String,
        externalAiEnabled: row['external_ai_enabled'] == 1,
        firstUseCompleted: row['first_use_completed'] == 1,
        appearance: row['appearance'] as String? ?? 'system',
        colorTheme: row['color_theme'] as String? ?? 'butlerRed',
      );
    } on Exception catch (error) {
      if (error is RepositoryException) rethrow;
      throw const RepositoryException(
        RepositoryFailureCode.unknown,
        'load user preferences',
      );
    }
  }

  @override
  Future<void> save(UserPreference preference) async {
    try {
      await database.connection.insert('user_preferences', {
        'id': 1,
        'locale': preference.locale,
        'base_currency': preference.baseCurrency.value,
        'time_zone_id': preference.timeZoneId,
        'external_ai_enabled': preference.externalAiEnabled ? 1 : 0,
        'first_use_completed': preference.firstUseCompleted ? 1 : 0,
        'appearance': preference.appearance,
        'color_theme': preference.colorTheme,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } on Exception catch (error) {
      if (error is RepositoryException) rethrow;
      throw const RepositoryException(
        RepositoryFailureCode.unknown,
        'save user preferences',
      );
    }
  }
}
