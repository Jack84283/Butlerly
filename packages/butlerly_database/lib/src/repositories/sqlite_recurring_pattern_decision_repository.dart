import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

final class SqliteRecurringPatternDecisionRepository
    implements RecurringPatternDecisionRepository {
  const SqliteRecurringPatternDecisionRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<List<RecurringPatternDecision>> list() async {
    final rows = await database.connection.query(
      'recurring_pattern_decisions',
      orderBy: 'updated_at DESC, pattern_key',
    );
    return rows.map(_fromRow).toList(growable: false);
  }

  @override
  Future<RecurringPatternDecision?> findByPatternKey(String patternKey) async {
    final rows = await database.connection.query(
      'recurring_pattern_decisions',
      where: 'pattern_key = ?',
      whereArgs: [patternKey],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<void> save(RecurringPatternDecision decision) async {
    try {
      await database.connection.insert(
        'recurring_pattern_decisions',
        _row(decision),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save recurring pattern decision');
    }
  }

  static RecurringPatternDecision _fromRow(Map<String, Object?> row) {
    try {
      return RecurringPatternDecision(
        id: row['id']! as String,
        patternKey: row['pattern_key']! as String,
        status: RecurringPatternDecisionStatus.values.byName(
          row['status']! as String,
        ),
        cadence: RecurringPatternDecisionCadence.values.byName(
          row['cadence']! as String,
        ),
        intervalDays: row['interval_days']! as int,
        expectedAmount: DecimalValue.fromParts(
          coefficient: BigInt.parse(
            row['expected_amount_coefficient']! as String,
          ),
          scale: row['expected_amount_scale']! as int,
        ),
        createdAt: DateTime.parse(row['created_at']! as String).toUtc(),
        updatedAt: DateTime.parse(row['updated_at']! as String).toUtc(),
      );
    } on Object {
      throw const RepositoryException(
        RepositoryFailureCode.integrity,
        'read recurring pattern decision',
        detail: 'A saved recurring decision has invalid persisted data.',
      );
    }
  }

  static Map<String, Object?> _row(RecurringPatternDecision value) => {
    'id': value.id,
    'pattern_key': value.patternKey,
    'status': value.status.name,
    'cadence': value.cadence.name,
    'interval_days': value.intervalDays,
    'expected_amount_coefficient': value.expectedAmount.coefficient.toString(),
    'expected_amount_scale': value.expectedAmount.scale,
    'created_at': value.createdAt.toUtc().toIso8601String(),
    'updated_at': value.updatedAt.toUtc().toIso8601String(),
  };
}
