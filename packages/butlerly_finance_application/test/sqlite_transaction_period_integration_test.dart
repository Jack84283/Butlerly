import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:test/test.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  for (final zone in ['Asia/Tokyo', 'America/Los_Angeles']) {
    test(
      'Home, Analysis and settlement share financial dates in $zone',
      () async {
        final database = ButlerlyDatabase(
          factory: databaseFactoryFfi,
          path: inMemoryDatabasePath,
          schemaSql: await File(
            '../butlerly_database/database/schema/v1.sql',
          ).readAsString(),
        );
        await database.open();
        addTearDown(database.close);
        final repository = SqliteTransactionRepository(database);
        final preferences = SqliteUserPreferenceRepository(database);
        await preferences.save(_preference(zone));
        final now = DateTime.utc(2026, 10, 2, 12);
        final source = PaymentSourceId('card');
        final category = CategoryId('test-category');
        await SqliteCategoryRepository(database).save(
          Category(
            id: category,
            name: 'Test category',
            origin: CategoryOrigin.user,
          ),
        );
        await SqlitePaymentSourceRepository(database).save(
          PaymentSource(
            id: source,
            name: 'Card',
            type: PaymentSourceType.wallet,
          ),
        );
        final inside = zone == 'Asia/Tokyo'
            ? DateTime.utc(2026, 9, 30, 16, 30)
            : DateTime.utc(2026, 10, 1, 7, 30);
        final outside = zone == 'Asia/Tokyo'
            ? DateTime.utc(2026, 9, 30, 14, 30)
            : DateTime.utc(2026, 10, 1, 6, 30);
        final values = [
          _transaction(id: 'fallback', occurredAt: inside, now: now),
          _transaction(id: 'outside', occurredAt: outside, now: now),
          _transaction(
            id: 'explicit',
            occurredAt: outside,
            transactionDate: '2026-10-01',
            now: now,
          ),
          _transaction(
            id: 'explicit-outside',
            occurredAt: inside,
            transactionDate: '2026-09-30',
            now: now,
          ),
          _transaction(id: 'unknown', occurredAt: null, now: now),
        ];
        for (final value in values) {
          await repository.save(
            value
                .assignPaymentSource(source, now)
                .assignCategory(category, now),
          );
        }
        final period =
            (await ResolveHomePeriod(preferences)(instant: now)
                    as ApplicationSuccess<HomePeriodResolution>)
                .value
                .period;
        final list = ListTransactions(repository, preferences: preferences);
        final home =
            (await list(
                      ListTransactionsQuery(
                        from: DateTime.parse(period.startDate),
                        to: DateTime.parse(period.endDate),
                        status: TransactionStatus.active,
                      ),
                    )
                    as ApplicationSuccess<List<TransactionDto>>)
                .value;
        expect(
          home.map((v) => v.id),
          unorderedEquals(['fallback', 'explicit']),
        );
        final analysis =
            await AnalysisDatasetBuilder(repository, preferences, null).build(
                  AnalysisContext(
                    period: period,
                    datasetMode: DatasetMode.allEligible,
                    currencyBasis: CurrencyBasis.original,
                  ),
                )
                as ApplicationDatasetSuccess;
        expect(
          analysis.dataset.primaryTransactionsByPeriod['selected_period']!.map(
            (v) => v.id.value,
          ),
          unorderedEquals(home.map((v) => v.id)),
        );
        expect(
          analysis.dataset.qualityIssues
              .where((q) => q.code == 'missingFinancialDate')
              .map((q) => q.transactionId!.value),
          ['unknown'],
        );
        for (final bounded in [false, true]) {
          for (final include in [false, true]) {
            final query = ListTransactionsQuery(
              from: bounded ? DateTime.utc(2026, 10, 1) : null,
              to: bounded ? DateTime.utc(2026, 10, 2) : null,
              includeUndated: include,
              text: 'financial fixture',
              categoryId: category.value,
              paymentSourceId: 'card',
              status: TransactionStatus.active,
            );
            final listed =
                (await list(query) as ApplicationSuccess<List<TransactionDto>>)
                    .value;
            expect(listed.any((v) => v.id == 'unknown'), include);
            expect(listed.any((v) => v.id == 'fallback'), isTrue);
            final direct = await repository.query(
              TransactionRepositoryQuery(
                includeUndated: include,
                text: 'financial fixture',
                categoryId: category,
                paymentSourceId: source,
                status: TransactionStatus.active,
              ),
            );
            expect(direct.any((v) => v.id.value == 'unknown'), include);
          }
        }
        final settlements = SqlitePaymentSettlementRepository(database);
        await settlements.save(
          PaymentSettlement(
            id: PaymentSettlementId('october'),
            paymentSourceId: source,
            payment: values.first.money,
            paymentDate: '2026-10-02',
            periodStart: '2026-10-01',
            periodEnd: '2026-10-31',
            status: PaymentSettlementStatus.open,
            createdAt: now,
            updatedAt: now,
          ),
        );
        final detail =
            (await GetPaymentSettlementDetail(
                      settlements,
                      preferences: preferences,
                    )('october')
                    as ApplicationSuccess<PaymentSettlementDetailDto>)
                .value;
        expect(
          detail.transactions.map((v) => v.id),
          unorderedEquals(['fallback', 'explicit']),
        );
        expect(
          detail.transactions.map((v) => v.financialDate),
          everyElement(DateTime.utc(2026, 10, 1)),
        );
      },
    );
  }

  test(
    'reopens persisted transactions before applying financial timezone bounds',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'butlerly-transaction-period-',
      );
      final path = '${directory.path}/butlerly.db';
      var database = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: await File(
          '../../packages/butlerly_database/database/schema/v1.sql',
        ).readAsString(),
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });

      await database.open();
      final transactions = SqliteTransactionRepository(database);
      final preferences = SqliteUserPreferenceRepository(database);
      await preferences.save(_preference('Asia/Tokyo'));
      final now = DateTime.utc(2026, 10, 2);

      final datedInside = _transaction(
        id: 'dated-inside',
        occurredAt: DateTime.utc(2026, 10, 1, 12),
        transactionDate: '2026-10-01',
        now: now,
      );
      final undatedNewest = _transaction(
        id: 'undated-newest',
        occurredAt: DateTime.utc(2026, 9, 30, 16, 45),
        now: now,
      );
      final legacyBlank = _transaction(
        id: 'legacy-blank',
        occurredAt: DateTime.utc(2026, 9, 30, 16, 30),
        now: now,
      );
      final undatedOutside = _transaction(
        id: 'undated-outside',
        occurredAt: DateTime.utc(2026, 9, 30, 14, 59),
        now: now,
      );
      final archived = _transaction(
        id: 'archived-undated',
        occurredAt: DateTime.utc(2026, 9, 30, 16, 40),
        now: now,
      ).archive(now.add(const Duration(minutes: 1)));

      for (final transaction in [
        datedInside,
        undatedNewest,
        legacyBlank,
        undatedOutside,
        archived,
      ]) {
        await transactions.save(transaction);
      }
      // Simulate a legacy persisted blank date. New writes normalize blanks to
      // NULL, while the query must remain compatible with existing rows.
      await database.connection.update(
        'transactions',
        {'transaction_date': ' '},
        where: 'id = ?',
        whereArgs: [legacyBlank.id.value],
      );
      await database.close();

      database = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: path,
        schemaSql: await File(
          '../../packages/butlerly_database/database/schema/v1.sql',
        ).readAsString(),
      );
      await database.open();

      final reopenedTransactions = SqliteTransactionRepository(database);
      final reopenedPreferences = SqliteUserPreferenceRepository(database);
      final tokyoResult =
          await ListTransactions(
            reopenedTransactions,
            preferences: reopenedPreferences,
          )(
            ListTransactionsQuery(
              from: DateTime.utc(2026, 10, 1),
              to: DateTime.utc(2026, 10, 1),
              status: TransactionStatus.active,
            ),
          );

      expect(tokyoResult, isA<ApplicationSuccess<List<TransactionDto>>>());
      final tokyoValues =
          (tokyoResult as ApplicationSuccess<List<TransactionDto>>).value;
      expect(tokyoValues.map((value) => value.id), [
        datedInside.id.value,
        undatedNewest.id.value,
        legacyBlank.id.value,
      ]);
      expect(tokyoValues.skip(1).map((value) => value.financialDate), [
        DateTime.utc(2026, 10, 1),
        DateTime.utc(2026, 10, 1),
      ]);

      await reopenedPreferences.save(_preference('America/Los_Angeles'));
      final losAngelesResult =
          await ListTransactions(
            reopenedTransactions,
            preferences: reopenedPreferences,
          )(
            ListTransactionsQuery(
              from: DateTime.utc(2026, 9, 30),
              to: DateTime.utc(2026, 9, 30),
              status: TransactionStatus.active,
            ),
          );

      expect(losAngelesResult, isA<ApplicationSuccess<List<TransactionDto>>>());
      final losAngelesValues =
          (losAngelesResult as ApplicationSuccess<List<TransactionDto>>).value;
      expect(losAngelesValues.map((value) => value.id), [
        undatedNewest.id.value,
        legacyBlank.id.value,
        undatedOutside.id.value,
      ]);
      expect(losAngelesValues.map((value) => value.financialDate), [
        DateTime.utc(2026, 9, 30),
        DateTime.utc(2026, 9, 30),
        DateTime.utc(2026, 9, 30),
      ]);
    },
  );
}

UserPreference _preference(String timeZoneId) => UserPreference(
  locale: 'en',
  baseCurrency: CurrencyCode('USD'),
  timeZoneId: timeZoneId,
);

Transaction _transaction({
  required String id,
  required DateTime? occurredAt,
  required DateTime now,
  String? transactionDate,
}) => Transaction(
  id: TransactionId(id),
  timing: occurredAt == null
      ? const UnknownTransactionTime(UnknownTransactionTimeReason.unknown)
      : KnownTransactionTime(occurredAt),
  money: Money(amount: DecimalValue.parse('10'), currency: CurrencyCode('USD')),
  direction: TransactionDirection.expense,
  sourceType: TransactionSourceType.manual,
  description: 'financial fixture',
  transactionDate: transactionDate,
  provenance: [
    Provenance(
      id: ProvenanceId('$id-provenance'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: now,
    ),
  ],
  createdAt: now,
  updatedAt: now,
);
