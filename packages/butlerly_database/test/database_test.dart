import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  late ButlerlyDatabase database;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    final baseline = await File('database/schema/v1.sql').readAsString();
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: baseline,
    );
    await database.open();
  });

  tearDown(() => database.close());

  test('applies current schema with foreign keys and indexes', () async {
    final version = await database.connection.getVersion();
    final foreignKeys = await database.connection.rawQuery(
      'PRAGMA foreign_keys',
    );
    final tables = await database.connection.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final indexes = await database.connection.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index'",
    );

    expect(version, ButlerlyDatabase.databaseVersion);
    expect(foreignKeys.single.values.single, 1);
    expect(
      tables.map((row) => row['name']),
      containsAll([
        'transactions',
        'provenances',
        'evidence_items',
        'suggestions',
        'review_issues',
        'user_preferences',
        'category_translations',
        'tag_translations',
        'reference_data',
        'reference_data_translations',
        'duplicate_candidate_groups',
        'duplicate_candidate_group_transactions',
      ]),
    );
    expect(
      indexes.map((row) => row['name']),
      contains('idx_transactions_duplicate_group_lookup'),
    );
    expect(await database.passesIntegrityCheck(), isTrue);
  });

  test('creates the fresh database directly from the V1 SQL baseline', () async {
    await database.close();
    final baseline = await File('database/schema/v1.sql').readAsString();
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: baseline,
    );
    await database.open();

    expect(
      await database.connection.getVersion(),
      ButlerlyDatabase.databaseVersion,
    );
    expect(await database.passesIntegrityCheck(), isTrue);
    expect(
      await database.connection.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'normalized_money_v15'",
      ),
      isEmpty,
    );
    expect(
      await database.connection.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_transactions_duplicate_lookup'",
      ),
      isEmpty,
    );
    expect(
      await database.connection.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_transactions_duplicate_group_lookup'",
      ),
      hasLength(1),
    );
  });

  test('upgrades an installed pre-disposition V1 database', () async {
    final directory = await Directory.systemTemp.createTemp('butlerly-db-');
    final path = '${directory.path}/legacy.db';
    final current = await File('database/schema/v1.sql').readAsString();
    final migration = await File(
      'database/migrations/v1_to_v2.sql',
    ).readAsString();
    final resultsMigration = await File(
      'database/migrations/v2_to_v3.sql',
    ).readAsString();
    final merchantMigration = await File(
      'database/migrations/v3_to_v4.sql',
    ).readAsString();
    final classificationMigration = await File(
      'database/migrations/v4_to_v5.sql',
    ).readAsString();
    final statementSubcategoryMigration = await File(
      'database/migrations/v5_to_v6.sql',
    ).readAsString();
    final legacy = current
        .replaceFirst(', status_before_skip TEXT', '')
        .replaceFirst(
          ',\n      normalized_name TEXT NOT NULL DEFAULT \'\',\n      default_category_id TEXT REFERENCES categories(id),\n      default_subcategory_id TEXT REFERENCES categories(id),\n      is_built_in INTEGER NOT NULL DEFAULT 0',
          '',
        )
        .replaceFirst(
          ',\n      subcategory_id TEXT REFERENCES categories(id), normalized_description TEXT NOT NULL DEFAULT \'\'',
          '',
        )
        .replaceFirst(
          ',\n      subcategory_id TEXT REFERENCES categories(id),\n      UNIQUE(statement_id, position)',
          ',\n      UNIQUE(statement_id, position)',
        )
        .replaceFirst(
          "CREATE INDEX idx_transactions_classification_merchant ON transactions(merchant_id, status, category_id, subcategory_id);",
          '',
        )
        .replaceFirst(
          "CREATE INDEX idx_transactions_classification_description ON transactions(normalized_description, status, category_id, subcategory_id);",
          '',
        );
    final legacyDb = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          for (final sql in splitSqlStatements(legacy)) {
            await db.execute(sql);
          }
        },
      ),
    );
    await legacyDb.insert('categories', {
      'id': 'category.food',
      'name': 'Food & Dining',
      'origin': 'system',
      'status': 'active',
    });
    await legacyDb.insert('merchants', {
      'id': 'merchant.safeway',
      'name': 'Safeway',
      'status': 'active',
    });
    await legacyDb.insert('provenances', {
      'id': 'legacy-provenance',
      'source_type': 'import',
      'captured_at': '2026-01-01T00:00:00.000Z',
      'original_representation': 'SAFEWAY #1234',
    });
    await legacyDb.insert('transactions', {
      'id': 'legacy-safeway',
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '12',
      'amount_scale': 0,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'import',
      'status': 'active',
      'description': 'SAFEWAY #1234',
      'raw_counterparty': 'ignored raw value',
      'merchant_id': 'merchant.safeway',
      'category_id': 'category.food',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
      'transaction_date': '2026-01-01',
    });
    await legacyDb.insert('categories', {
      'id': 'category.food.restaurants',
      'name': 'Restaurants',
      'origin': 'system',
      'parent_id': 'category.food',
      'status': 'active',
    });
    await legacyDb.insert('evidence_items', {
      'id': 'legacy-evidence',
      'type': 'statement',
      'original_name': 'legacy.csv',
      'media_type': 'text/csv',
      'provenance_id': 'legacy-provenance',
      'created_at': '2026-01-01T00:00:00.000Z',
    });
    await legacyDb.insert('financial_statements', {
      'id': 'legacy-statement',
      'evidence_id': 'legacy-evidence',
      'status': 'needsSource',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    await legacyDb.insert('statement_rows', {
      'id': 'legacy-flattened',
      'statement_id': 'legacy-statement',
      'position': 0,
      'original_text': 'Restaurant 10.00',
      'row_kind': 'purchase',
      'status': 'pending',
      'category_id': 'category.food.restaurants',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    await legacyDb.insert('statement_rows', {
      'id': 'legacy-root',
      'statement_id': 'legacy-statement',
      'position': 1,
      'original_text': 'Food 20.00',
      'row_kind': 'purchase',
      'status': 'pending',
      'category_id': 'category.food',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    });
    await legacyDb.insert('transaction_provenances', {
      'transaction_id': 'legacy-safeway',
      'provenance_id': 'legacy-provenance',
    });
    await legacyDb.insert('transactions', {
      'id': 'legacy-empty',
      'unknown_time_reason': 'unknown',
      'amount_coefficient': '1',
      'amount_scale': 0,
      'currency': 'USD',
      'direction': 'expense',
      'source_type': 'import',
      'status': 'active',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
      'transaction_date': '2026-01-01',
    });
    expect(
      await legacyDb.rawQuery('PRAGMA table_info(statement_rows)'),
      isNot(
        contains(predicate<Map>((row) => row['name'] == 'status_before_skip')),
      ),
    );
    await legacyDb.close();

    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: path,
      schemaSql: current,
      migrations: {
        2: migration,
        3: resultsMigration,
        4: merchantMigration,
        5: classificationMigration,
        6: statementSubcategoryMigration,
      },
    );
    await database.open();
    expect(await database.connection.getVersion(), 6);
    expect(
      (await database.connection.rawQuery(
        'PRAGMA table_info(statement_rows)',
      )).any((row) => row['name'] == 'status_before_skip'),
      isTrue,
    );
    expect(
      (await database.connection.rawQuery(
        'PRAGMA table_info(statement_rows)',
      )).any((row) => row['name'] == 'subcategory_id'),
      isTrue,
    );
    expect(
      (await database.connection.query(
        'transactions',
        columns: ['normalized_description'],
        where: 'id = ?',
        whereArgs: ['legacy-safeway'],
      )).single['normalized_description'],
      'safeway',
    );
    expect(
      (await database.connection.query(
        'statement_rows',
        columns: ['category_id', 'subcategory_id'],
        where: 'id = ?',
        whereArgs: ['legacy-flattened'],
      )).single,
      {
        'category_id': 'category.food',
        'subcategory_id': 'category.food.restaurants',
      },
    );
    expect(
      (await database.connection.query(
        'statement_rows',
        columns: ['category_id', 'subcategory_id'],
        where: 'id = ?',
        whereArgs: ['legacy-root'],
      )).single,
      {'category_id': 'category.food', 'subcategory_id': null},
    );
    expect(
      (await database.connection.query(
        'transactions',
        columns: ['normalized_description'],
        where: 'id = ?',
        whereArgs: ['legacy-empty'],
      )).single['normalized_description'],
      '',
    );
    final candidates =
        await (SqliteTransactionRepository(database)
                as HistoricalClassificationRepository)
            .findClassificationCandidates(normalizedDescription: 'safeway');
    expect(candidates.map((value) => value.id.value), ['legacy-safeway']);
    expect(
      (await (SqliteTransactionRepository(database)
                  as HistoricalClassificationRepository)
              .findClassificationCandidates(
                merchantId: MerchantId('merchant.safeway'),
              ))
          .map((value) => value.id.value),
      ['legacy-safeway'],
    );
    await database.close();
    await directory.delete(recursive: true);
  });

  test('applies the idempotent database-owned catalog seed', () async {
    await database.close();
    final baseline = await File('database/schema/v1.sql').readAsString();
    final catalog = await File('database/seed/catalog.sql').readAsString();
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: baseline,
      seedSql: [catalog, catalog],
    );
    await database.open();

    expect(
      (await database.connection.query('categories')).length,
      greaterThan(30),
    );
    expect(
      (await database.connection.query('category_translations')).length,
      greaterThan(30),
    );
    expect(
      (await database.connection.query('reference_data')).length,
      greaterThan(30),
    );
    expect(
      await database.connection.query(
        'categories',
        where: 'id = ?',
        whereArgs: ['category.food.restaurants'],
      ),
      hasLength(1),
    );
    expect(
      (await database.connection.query(
        'category_translations',
        where: 'category_id = ? AND locale = ?',
        whereArgs: ['category.food', 'en'],
      )).single['label'],
      'Food & Dining',
    );
    expect(
      (await database.connection.query(
        'category_translations',
        where: 'category_id = ? AND locale = ?',
        whereArgs: ['category.food', 'zh-Hans'],
      )).single['label'],
      '餐饮',
    );
    expect(
      (await database.connection.query(
        'tag_translations',
        where: 'tag_id = ? AND locale IN (?, ?)',
        whereArgs: ['tag.business', 'en', 'zh-Hans'],
      )),
      hasLength(2),
    );
    expect(
      (await database.connection.query(
        'reference_data_translations',
        where: 'reference_data_id = ? AND locale IN (?, ?)',
        whereArgs: ['transaction.direction.expense', 'en', 'zh-Hans'],
      )),
      hasLength(2),
    );
  });

  test('round-trips possible duplicate group state and memberships', () async {
    for (final id in ['tx-a', 'tx-b']) {
      await database.connection.insert('transactions', {
        'id': id,
        'unknown_time_reason': 'not supplied',
        'amount_coefficient': '25',
        'amount_scale': 0,
        'currency': 'USD',
        'direction': TransactionDirection.expense.name,
        'source_type': TransactionSourceType.manual.name,
        'status': TransactionStatus.active.name,
        'created_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'updated_at': DateTime.utc(2026, 1, 1).toIso8601String(),
        'transaction_date': '2026-01-01',
      });
    }
    final repository = SqliteDuplicateCandidateGroupRepository(database);
    final now = DateTime.utc(2026, 1, 1);
    final group = DuplicateCandidateGroup(
      id: 'duplicate:test',
      transactionIds: [TransactionId('tx-b'), TransactionId('tx-a')],
      duplicateKey: DuplicateTransactionKey(
        transactionDate: '2026-01-01',
        amount: DecimalValue.parse('25.00'),
        currency: 'usd',
        direction: TransactionDirection.expense.name,
      ),
      status: DuplicateCandidateGroupStatus.unresolved,
      selectedTransactionId: TransactionId('tx-a'),
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(group);
    final loaded = (await repository.list()).single;
    expect(loaded.transactionIds.map((id) => id.value), ['tx-a', 'tx-b']);
    expect(loaded.duplicateKey.amount, DecimalValue.parse('25'));
    expect(loaded.duplicateKey.currency, 'USD');
    expect(loaded.selectedTransactionId?.value, 'tx-a');
    final matches = await repository.findActiveDuplicateGroups();
    expect(matches, hasLength(1));
    expect(matches.single.transactionIds.map((id) => id.value), [
      'tx-a',
      'tx-b',
    ]);
  });

  test('persists the single local user preference record', () async {
    final repository = SqliteUserPreferenceRepository(database);
    expect(await repository.load(), isNull);

    await repository.save(
      UserPreference(
        locale: 'zh',
        formattingLocale: 'zh-Hans-CN',
        regionCode: 'CN',
        baseCurrency: CurrencyCode('CNY'),
        timeZoneId: 'Asia/Shanghai',
        externalAiEnabled: true,
        firstUseCompleted: true,
      ),
    );

    final value = await repository.load();
    expect(value?.locale, 'zh');
    expect(value?.formattingLocale, 'zh-Hans-CN');
    expect(value?.regionCode, 'CN');
    expect(value?.baseCurrency.value, 'CNY');
    expect(value?.timeZoneId, 'Asia/Shanghai');
    expect(value?.externalAiEnabled, isTrue);
    expect(value?.firstUseCompleted, isTrue);
  });

  test(
    'persists and retrieves master translations by stable ID and locale',
    () async {
      final repository = SqliteMasterTranslationRepository(database);
      await database.connection.insert('categories', {
        'id': 'system-category-food-dining',
        'name': 'Food & Dining',
        'origin': 'system',
        'status': 'active',
      });
      await database.connection.insert('categories', {
        'id': 'category.food',
        'name': 'Food & Dining',
        'origin': 'system',
        'status': 'active',
      });
      await repository.saveAll(const [
        MasterTranslation(
          masterType: 'category',
          masterId: 'category.food',
          locale: 'en',
          label: 'Food & Dining',
        ),
        MasterTranslation(
          masterType: 'category',
          masterId: 'category.food',
          locale: 'zh-Hans',
          label: '餐饮',
        ),
      ]);

      expect(
        await repository.labels(masterType: 'category', locale: 'zh-Hans'),
        {'category.food': '餐饮', 'system-category-food-dining': '餐饮'},
      );
    },
  );

  test(
    'persists generic reference data and localized labels by stable ID',
    () async {
      final repository = SqliteReferenceDataRepository(database);
      final value = ReferenceData(
        id: ReferenceDataId('payment_source.type.credit_card'),
        code: 'card',
        type: 'payment_source.type',
      );
      await repository.save(value);
      await repository.saveTranslation(
        id: value.id,
        locale: 'en',
        label: 'Credit card',
      );
      await repository.saveTranslation(
        id: value.id,
        locale: 'zh-Hans',
        label: '信用卡',
      );

      expect(
        (await repository.list(type: 'payment_source.type')).single.id.value,
        value.id.value,
      );
      expect(
        await repository.labels(type: 'payment_source.type', locale: 'zh-Hans'),
        {value.id.value: '信用卡'},
      );
    },
  );

  test('resolves a legacy reference ID through the MD-0001 alias', () async {
    final repository = SqliteReferenceDataRepository(database);
    await database.connection.insert('reference_data', {
      'id': 'payment_source_type.card',
      'code': 'card',
      'type': 'payment_source_type',
      'origin': 'system',
      'status': 'active',
    });
    await repository.saveTranslation(
      id: ReferenceDataId('payment_source_type.card'),
      locale: 'zh-Hans',
      label: '信用卡',
    );

    expect(
      await repository.labels(type: 'payment_source.type', locale: 'zh-Hans'),
      {'payment_source.type.credit_card': '信用卡'},
    );
  });

  test('rolls back an atomic transaction on failure', () async {
    await expectLater(
      database.transaction((executor) async {
        await executor.insert('merchants', {
          'id': 'merchant-1',
          'name': 'Valid',
        });
        await executor.insert('merchants', {'id': 'merchant-2', 'name': null});
      }),
      throwsA(anything),
    );

    expect(await database.connection.query('merchants'), isEmpty);
  });

  test(
    'prepares only an integrity-checked consistent backup boundary',
    () async {
      await database.prepareForConsistentBackup();
      expect(await database.passesIntegrityCheck(), isTrue);
    },
  );
}
