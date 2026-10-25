import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('monthly budgets persist across database restarts', () async {
    final directory = await Directory.systemTemp.createTemp('budgets-v18-');
    final path = '${directory.path}/budgets.db';
    final schema = await File('database/schema/v1.sql').readAsString();
    final deployment = await File(
      'database/migrations/deployment.sql',
    ).readAsString();

    Future<ButlerlyDatabase> open() async {
      final database = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: schema,
        migrations: parseDeploymentMigrations(deployment),
      );
      await database.open();
      return database;
    }

    try {
      var database = await open();
      var budgets = SqliteBudgetRepository(database);
      await budgets.save(
        const Budget(
          id: 'groceries-usd',
          scope: 'category',
          scopeId: 'groceries',
          currency: 'USD',
          amount: '750.00',
        ),
      );
      expect((await budgets.list()).single.amount, '750.00');
      await expectLater(
        budgets.save(
          const Budget(
            id: 'duplicate-scope',
            scope: 'category',
            scopeId: 'groceries',
            currency: 'USD',
            amount: '999.00',
          ),
        ),
        throwsA(isA<Exception>()),
      );
      expect((await budgets.list()).single.amount, '750.00');

      await database.close();

      database = await open();
      budgets = SqliteBudgetRepository(database);
      final saved = (await budgets.list()).single;
      expect(saved.scopeId, 'groceries');
      expect(saved.currency, 'USD');
      await budgets.remove(saved.id);
      expect(await budgets.list(), isEmpty);
      await database.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('budget amounts must be positive and finite', () async {
    final database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: await File('database/schema/v1.sql').readAsString(),
    );
    await database.open();
    try {
      final budgets = SqliteBudgetRepository(database);
      for (final amount in ['0', '-1', 'NaN', 'Infinity', 'invalid']) {
        await expectLater(
          budgets.save(
            Budget(
              id: 'invalid',
              scope: 'overall',
              scopeId: null,
              currency: 'USD',
              amount: amount,
            ),
          ),
          throwsArgumentError,
        );
      }
    } finally {
      await database.close();
    }
  });
}
