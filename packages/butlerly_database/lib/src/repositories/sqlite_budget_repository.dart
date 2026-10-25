import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';

/// Persistence for explicit budget choices, not machine-generated suggestions.
final class SqliteBudgetRepository implements BudgetRepository {
  const SqliteBudgetRepository(this.database);

  final ButlerlyDatabase database;

  Future<List<Budget>> list() async {
    final rows = await database.connection.query(
      'budgets',
      orderBy: 'scope ASC, scope_id ASC, currency ASC',
    );
    return [
      for (final row in rows)
        Budget(
          id: row['id']! as String,
          scope: row['scope']! as String,
          scopeId: row['scope_id'] as String?,
          currency: row['currency']! as String,
          amount: row['amount']! as String,
        ),
    ];
  }

  Future<void> save(Budget budget) async {
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
