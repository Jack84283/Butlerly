import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

/// Monthly, user-approved limit. Amount is stored as a decimal string to
/// avoid floating-point changes to financial thresholds.
final class StoredBudget {
  const StoredBudget({
    required this.id,
    required this.scope,
    required this.scopeId,
    required this.currency,
    required this.amount,
  });

  final String id;
  final String scope;
  final String? scopeId;
  final String currency;
  final String amount;
}

/// Persistence for explicit budget choices, not machine-generated suggestions.
final class SqliteBudgetRepository {
  const SqliteBudgetRepository(this.database);

  final ButlerlyDatabase database;

  Future<List<StoredBudget>> list() async {
    final rows = await database.connection.query(
      'budgets',
      orderBy: 'scope ASC, scope_id ASC, currency ASC',
    );
    return [
      for (final row in rows)
        StoredBudget(
          id: row['id']! as String,
          scope: row['scope']! as String,
          scopeId: row['scope_id'] as String?,
          currency: row['currency']! as String,
          amount: row['amount']! as String,
        ),
    ];
  }

  Future<void> save(StoredBudget budget) async {
    if (!const {
      'overall',
      'category',
      'subcategory',
      'merchant',
    }.contains(budget.scope)) {
      throw ArgumentError.value(budget.scope, 'scope');
    }
    if ((budget.scope == 'overall') != (budget.scopeId == null)) {
      throw ArgumentError.value(budget.scopeId, 'scopeId');
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(budget.currency)) {
      throw ArgumentError.value(budget.currency, 'currency');
    }
    final parsed = num.tryParse(budget.amount);
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      throw ArgumentError.value(budget.amount, 'amount');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    await database.connection.transaction((transaction) async {
      final existing = await transaction.query(
        'budgets',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [budget.id],
        limit: 1,
      );
      final fields = <String, Object?>{
        'scope': budget.scope,
        'scope_id': budget.scopeId,
        'currency': budget.currency,
        'amount': budget.amount,
        'updated_at': now,
      };
      if (existing.isEmpty) {
        await transaction.insert(
          'budgets',
          {'id': budget.id, ...fields, 'created_at': now},
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      } else {
        await transaction.update(
          'budgets',
          fields,
          where: 'id = ?',
          whereArgs: [budget.id],
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }
    });
  }

  Future<void> remove(String id) async {
    await database.connection.delete(
      'budgets',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
