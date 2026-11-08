import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;
import 'package:test/test.dart';

void main() {
  sqfliteFfiInit();

  late ButlerlyDatabase database;
  late SqlitePaymentSettlementRepository settlements;
  late SqliteTransactionRepository transactions;

  setUp(() async {
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: await File('database/schema/v1.sql').readAsString(),
    );
    await database.open();
    settlements = SqlitePaymentSettlementRepository(database);
    transactions = SqliteTransactionRepository(database);

    await _insertPaymentSource(database, 'visa', 'Visa');
    await _insertPaymentSource(database, 'amex', 'Amex');
  });

  tearDown(() => database.close());

  test(
    'persists settlement-owned payment facts without a transaction',
    () async {
      final settlement = _settlement();

      await settlements.save(settlement);
      final loaded = await settlements.findById(settlement.id);

      expect(loaded, isNotNull);
      expect(loaded!.paymentSourceId, PaymentSourceId('visa'));
      expect(loaded.payment.amount, DecimalValue.parse('2846.72'));
      expect(loaded.payment.currency, CurrencyCode('USD'));
      expect(loaded.paymentDate, '2026-09-20');
      expect(loaded.periodStart, '2026-08-15');
      expect(loaded.periodEnd, '2026-09-14');
      expect(loaded.statementBalance, settlement.statementBalance);

      final transactionRows = await database.connection.query('transactions');
      expect(transactionRows, isEmpty);
    },
  );

  test('resolves activity dynamically and excludes transfers', () async {
    final settlement = _settlement();
    await settlements.save(settlement);
    await transactions.save(
      _transaction(
        id: 'inside-expense',
        sourceId: 'visa',
        transactionDate: '2026-09-01',
      ),
    );
    await transactions.save(
      _transaction(
        id: 'inside-refund',
        sourceId: 'visa',
        transactionDate: '2026-09-02',
        direction: TransactionDirection.refund,
      ),
    );
    await transactions.save(
      _transaction(
        id: 'inside-transfer',
        sourceId: 'visa',
        transactionDate: '2026-09-03',
        direction: TransactionDirection.transfer,
      ),
    );
    await transactions.save(
      _transaction(
        id: 'outside',
        sourceId: 'visa',
        transactionDate: '2026-09-15',
      ),
    );
    await transactions.save(
      _transaction(
        id: 'other-source',
        sourceId: 'amex',
        transactionDate: '2026-09-01',
      ),
    );

    final first = await settlements.listTransactions(settlement);
    expect(first.map((value) => value.id.value).toSet(), {
      'inside-expense',
      'inside-refund',
    });

    await transactions.save(
      _transaction(
        id: 'late-import',
        sourceId: 'visa',
        transactionDate: '2026-08-20',
      ),
    );

    final refreshed = await settlements.listTransactions(settlement);
    expect(refreshed.map((value) => value.id.value).toSet(), {
      'inside-expense',
      'inside-refund',
      'late-import',
    });
  });

  test(
    'includes timing-only activity when application supplies period bounds',
    () async {
      final settlement = _settlement();
      await settlements.save(settlement);
      await transactions.save(
        _transaction(
          id: 'timing-only-inside',
          sourceId: 'visa',
          transactionDate: null,
          occurredAt: DateTime.utc(2026, 9, 14, 23),
        ),
      );
      await transactions.save(
        _transaction(
          id: 'timing-only-outside',
          sourceId: 'visa',
          transactionDate: null,
          occurredAt: DateTime.utc(2026, 9, 15),
        ),
      );

      final result = await settlements.listTransactions(
        settlement,
        occurredAtFrom: DateTime.utc(2026, 8, 15),
        occurredAtToExclusive: DateTime.utc(2026, 9, 15),
      );

      expect(result.map((value) => value.id.value), ['timing-only-inside']);
    },
  );

  test('updates payment amount and date directly on the settlement', () async {
    await settlements.save(_settlement());

    final at = DateTime.utc(2026, 9, 21, 12);
    await settlements.save(
      PaymentSettlement(
        id: PaymentSettlementId('settlement-1'),
        paymentSourceId: PaymentSourceId('visa'),
        payment: _money('2900.00'),
        paymentDate: '2026-09-21',
        periodStart: '2026-08-15',
        periodEnd: '2026-09-14',
        status: PaymentSettlementStatus.open,
        createdAt: DateTime.utc(2026, 9, 20, 12),
        updatedAt: at,
      ),
    );

    final loaded = await settlements.findById(
      PaymentSettlementId('settlement-1'),
    );
    expect(loaded!.payment.amount, DecimalValue.parse('2900.00'));
    expect(loaded.paymentDate, '2026-09-21');
  });

  test('deleting a settlement does not delete ordinary transactions', () async {
    await settlements.save(_settlement());
    await transactions.save(
      _transaction(
        id: 'purchase',
        sourceId: 'visa',
        transactionDate: '2026-09-01',
      ),
    );

    await settlements.remove(PaymentSettlementId('settlement-1'));

    expect(
      await settlements.findById(PaymentSettlementId('settlement-1')),
      isNull,
    );
    expect(await transactions.findById(TransactionId('purchase')), isNotNull);
  });

  test(
    'large settlement history preserves every row and stable ordering',
    () async {
      final now = DateTime.utc(2026, 9, 20, 12);
      for (var index = 0; index < 260; index++) {
        await settlements.save(
          PaymentSettlement(
            id: PaymentSettlementId('restored-$index'),
            paymentSourceId: PaymentSourceId('visa'),
            payment: _money('10.00'),
            paymentDate: '2026-09-20',
            periodStart: '2026-08-15',
            periodEnd: '2026-09-14',
            status: PaymentSettlementStatus.open,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      final listed = await settlements.listAll();
      final ids = listed.map((value) => value.id.value).toList();
      final expected = [
        for (var index = 0; index < 260; index++) 'restored-$index',
      ]..sort();
      expect(ids, expected);
      expect(ids.toSet(), hasLength(260));
    },
  );

  test('SQL pages bound settlement loading without losing history', () async {
    final at = DateTime.utc(2026, 11, 8);
    for (var index = 0; index < 53; index++) {
      await settlements.save(
        PaymentSettlement(
          id: PaymentSettlementId('page-${index.toString().padLeft(3, '0')}'),
          paymentSourceId: PaymentSourceId('visa'),
          payment: _money('11.00'),
          paymentDate: '2026-09-20',
          periodStart: '2026-08-15',
          periodEnd: '2026-09-14',
          status: PaymentSettlementStatus.open,
          createdAt: at,
          updatedAt: at,
        ),
      );
    }

    final first = await settlements.listPage(offset: 0, limit: 20);
    final second = await settlements.listPage(offset: 20, limit: 20);
    final third = await settlements.listPage(offset: 40, limit: 20);
    expect(first.totalCount, 53);
    expect(second.totalCount, 53);
    expect(third.totalCount, 53);
    expect(first.rows, hasLength(20));
    expect(second.rows, hasLength(20));
    expect(third.rows, hasLength(13));
    expect(first.rows.first.id.value, 'page-000');
    expect(second.rows.first.id.value, 'page-020');
    expect(third.rows.last.id.value, 'page-052');
    expect(
      [...first.rows, ...second.rows, ...third.rows]
          .map((settlement) => settlement.id.value)
          .toSet(),
      hasLength(53),
    );
    expect(await settlements.listAll(), hasLength(53));
  });

  test('transaction pages match full history with exact period totals', () async {
    final settlement = _settlement();
    await settlements.save(settlement);
    for (var index = 0; index < 45; index++) {
      await transactions.save(
        _transaction(
          id: 'paged-$index',
          sourceId: 'visa',
          transactionDate: '2026-09-01',
          amount: '1.25',
          direction: index == 0
              ? TransactionDirection.refund
              : TransactionDirection.expense,
        ),
      );
    }
    await transactions.save(
      _transaction(
        id: 'timing-only-paged',
        sourceId: 'visa',
        occurredAt: DateTime.utc(2026, 9, 14, 23),
        amount: '0.75',
      ),
    );
    await transactions.save(
      _transaction(
        id: 'excluded-transfer',
        sourceId: 'visa',
        transactionDate: '2026-09-01',
        direction: TransactionDirection.transfer,
      ),
    );
    await transactions.save(
      _transaction(
        id: 'outside-period',
        sourceId: 'visa',
        transactionDate: '2026-09-15',
      ),
    );
    await transactions.save(
      _transaction(
        id: 'wrong-source',
        sourceId: 'amex',
        transactionDate: '2026-09-01',
      ),
    );
    await transactions.save(
      _transaction(
        id: 'archived-paged',
        sourceId: 'visa',
        transactionDate: '2026-09-01',
        status: TransactionStatus.archived,
      ),
    );

    final from = DateTime.utc(2026, 8, 15);
    final toExclusive = DateTime.utc(2026, 9, 15);
    final full = await settlements.listTransactions(
      settlement,
      occurredAtFrom: from,
      occurredAtToExclusive: toExclusive,
    );
    final first = await settlements.listTransactionsPage(
      settlement,
      occurredAtFrom: from,
      occurredAtToExclusive: toExclusive,
      offset: 0,
      limit: 20,
    );
    final second = await settlements.listTransactionsPage(
      settlement,
      occurredAtFrom: from,
      occurredAtToExclusive: toExclusive,
      offset: 20,
      limit: 20,
    );
    final third = await settlements.listTransactionsPage(
      settlement,
      occurredAtFrom: from,
      occurredAtToExclusive: toExclusive,
      offset: 40,
      limit: 20,
    );
    expect(first.totalCount, 46);
    expect(second.totalCount, 46);
    expect(third.totalCount, 46);
    expect(first.rows, hasLength(20));
    expect(second.rows, hasLength(20));
    expect(third.rows, hasLength(6));
    expect(
      [...first.rows, ...second.rows, ...third.rows]
          .map((t) => t.id.value)
          .toList(),
      full.map((t) => t.id.value).toList(),
    );
    // 44 expenses - 1 refund, at 1.25 each, plus 0.75 timing-only.
    expect(first.recordedTotal, _money('54.50'));
    expect(second.recordedTotal, first.recordedTotal);

    await transactions.save(
      _transaction(
        id: 'adjustment',
        sourceId: 'visa',
        transactionDate: '2026-09-01',
        direction: TransactionDirection.adjustment,
      ),
    );
    final uncomparable = await settlements.listTransactionsPage(
      settlement,
      occurredAtFrom: from,
      occurredAtToExclusive: toExclusive,
      offset: 0,
      limit: 20,
    );
    expect(uncomparable.totalCount, 47);
    expect(uncomparable.recordedTotal, isNull);
  });

  test(
    'bounded queries preserve provenance, tags, review and normalized values',
    () async {
    final at = DateTime.utc(2026, 9, 2, 12);
    final id = TransactionId('rich-paged');
    final money = _money('2.50');
    await database.connection.insert('tags', {
      'id': 'tag-paged',
      'name': 'Paged Tag',
    });
    await transactions.save(
      Transaction(
        id: id,
        timing: KnownTransactionTime(at),
        money: money,
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.import,
        paymentSourceId: PaymentSourceId('visa'),
        transactionDate: '2026-09-02',
        tagIds: [TagId('tag-paged')],
        provenance: [
          Provenance(
            id: ProvenanceId('rich-page-provenance'),
            sourceType: ProvenanceSourceType.import,
            capturedAt: at,
            originalRepresentation: 'preserve me',
          ),
        ],
        reviewIssues: [
          ReviewIssue(
            id: ReviewIssueId('rich-page-review'),
            transactionId: id,
            reason: ReviewIssueReason.uncertain,
            createdAt: at,
          ),
        ],
        normalizedMoney: [
          NormalizedMoney(original: money, converted: money, updatedAt: at),
        ],
        createdAt: at,
        updatedAt: at,
      ),
    );
    final direct = (await transactions.findById(id))!;
    final paged = await transactions.query(
      TransactionRepositoryQuery(
        from: DateTime.utc(2026, 9, 1),
        to: DateTime.utc(2026, 9, 30),
        paymentSourceId: PaymentSourceId('visa'),
        limit: 20,
        offset: 0,
      ),
    );
    final read = paged.singleWhere((t) => t.id == id);
    expect(
      read.provenance.map((p) => p.id.value).toList(),
      direct.provenance.map((p) => p.id.value).toList(),
    );
    expect(read.tagIds, direct.tagIds);
    expect(
      read.reviewIssues.map((review) => review.id.value).toList(),
      direct.reviewIssues.map((review) => review.id.value).toList(),
    );
    expect(
      read.normalizedMoney.map((money) => money.converted).toList(),
      direct.normalizedMoney.map((money) => money.converted).toList(),
    );
  });

  test('does not create a persisted settlement membership table', () async {
    final rows = await database.connection.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'payment_settlement_items'",
    );

    expect(rows, isEmpty);
  });
}

PaymentSettlement _settlement() {
  final at = DateTime.utc(2026, 9, 20, 12);
  return PaymentSettlement(
    id: PaymentSettlementId('settlement-1'),
    paymentSourceId: PaymentSourceId('visa'),
    payment: _money('2846.72'),
    paymentDate: '2026-09-20',
    periodStart: '2026-08-15',
    periodEnd: '2026-09-14',
    statementBalance: _money('2846.72'),
    status: PaymentSettlementStatus.open,
    createdAt: at,
    updatedAt: at,
  );
}

Money _money(String amount) =>
    Money(amount: DecimalValue.parse(amount), currency: CurrencyCode('USD'));

Transaction _transaction({
  required String id,
  required String sourceId,
  String? transactionDate,
  DateTime? occurredAt,
  TransactionDirection direction = TransactionDirection.expense,
  TransactionStatus status = TransactionStatus.active,
  String amount = '10.00',
}) {
  final at = occurredAt ?? DateTime.parse('${transactionDate!}T12:00:00Z');
  return Transaction(
    id: TransactionId(id),
    timing: KnownTransactionTime(at),
    money: _money(amount),
    direction: direction,
    sourceType: TransactionSourceType.import,
    status: status,
    paymentSourceId: PaymentSourceId(sourceId),
    provenance: [
      Provenance(
        id: ProvenanceId('provenance-$id'),
        sourceType: ProvenanceSourceType.import,
        capturedAt: at,
        originalRepresentation: id,
      ),
    ],
    transactionDate: transactionDate,
    createdAt: at,
    updatedAt: at,
  );
}

Future<void> _insertPaymentSource(
  ButlerlyDatabase database,
  String id,
  String name,
) async {
  await database.connection.insert('payment_sources', {
    'id': id,
    'name': name,
    'type': PaymentSourceType.card.name,
    'status': PaymentSourceStatus.active.name,
  });
}
