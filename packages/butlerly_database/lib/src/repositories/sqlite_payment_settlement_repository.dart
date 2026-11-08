import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart' hide Transaction;

import '../database/butlerly_database.dart';
import 'sqlite_transaction_repository.dart';

final class SqlitePaymentSettlementRepository
    implements
        PaymentSettlementRepository,
        PaginatedPaymentSettlementRepository,
        PaginatedPaymentSettlementTransactionRepository,
        PaymentSettlementSummaryRepository {
  const SqlitePaymentSettlementRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<void> save(PaymentSettlement value) async {
    try {
      final existing = await database.connection.query(
        'payment_settlements',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [value.id.value],
        limit: 1,
      );
      if (existing.isEmpty) {
        await database.connection.insert('payment_settlements', _row(value));
      } else {
        await database.connection.update(
          'payment_settlements',
          _row(value),
          where: 'id = ?',
          whereArgs: [value.id.value],
        );
      }
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save payment settlement');
    }
  }

  @override
  Future<PaymentSettlement?> findById(PaymentSettlementId id) async {
    try {
      final rows = await database.connection.query(
        'payment_settlements',
        where: 'id = ?',
        whereArgs: [id.value],
        limit: 1,
      );
      return rows.isEmpty ? null : _fromRow(rows.single);
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'find payment settlement');
    }
  }

  @override
  Future<List<PaymentSettlement>> listAll() async {
    try {
      final rows = await database.connection.query(
        'payment_settlements',
        orderBy: 'payment_date DESC, id',
      );
      // Give Flutter an event-loop turn while decoding large restored
      // histories. Keep the existing complete, ordered result contract;
      // pagination and statement provenance belong at the application layer.
      final values = <PaymentSettlement>[];
      for (var index = 0; index < rows.length; index++) {
        values.add(_fromRow(rows[index]));
        if (index > 0 && index % 128 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }
      return List.unmodifiable(values);
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'list payment settlements');
    }
  }

  @override
  Future<PaymentSettlementPage> listPage({
    required int offset,
    required int limit,
  }) async {
    if (offset < 0 || limit <= 0 || limit > 100) {
      throw ArgumentError('Expected offset >= 0 and 1 <= limit <= 100');
    }
    try {
      return await database.transaction((executor) async {
        // COUNT and the visible page share one SQLite read snapshot.
        final counts = await executor.rawQuery(
          'SELECT COUNT(*) AS total FROM payment_settlements',
        );
        final rows = await executor.query(
          'payment_settlements',
          orderBy: 'payment_date DESC, id',
          limit: limit,
          offset: offset,
        );
        return PaymentSettlementPage(
          rows: List.unmodifiable(rows.map(_fromRow)),
          totalCount: counts.single['total']! as int,
        );
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'page payment settlements');
    }
  }

  @override
  Future<List<Transaction>> listTransactions(
    PaymentSettlement settlement, {
    DateTime? occurredAtFrom,
    DateTime? occurredAtToExclusive,
  }) async {
    final values = await SqliteTransactionRepository(database).query(
      TransactionRepositoryQuery(
        from: DateTime.parse(settlement.periodStart),
        to: DateTime.parse(settlement.periodEnd),
        occurredAtFrom: occurredAtFrom,
        occurredAtToExclusive: occurredAtToExclusive,
        paymentSourceId: settlement.paymentSourceId,
        status: TransactionStatus.active,
      ),
    );
    return values
        .where((value) => value.direction != TransactionDirection.transfer)
        .toList(growable: false);
  }

  @override
  Future<PaymentSettlementTransactionPage> listTransactionsPage(
    PaymentSettlement settlement, {
    DateTime? occurredAtFrom,
    DateTime? occurredAtToExclusive,
    required int offset,
    required int limit,
  }) async {
    if (offset < 0 || limit <= 0 || limit > 100) {
      throw ArgumentError('Invalid settlement transaction page bounds');
    }
    final filter = _periodFilter(
      settlement,
      occurredAtFrom: occurredAtFrom,
      occurredAtToExclusive: occurredAtToExclusive,
    );
    try {
      return await database.transaction((executor) async {
        // Count and child aggregates are read from the same snapshot, with
        // *all* child-table queries using the transaction executor.
        final counts = await executor.rawQuery(
          '''SELECT COUNT(*) AS total,
                    COALESCE(MAX(t.updated_at), '') AS latest_update
             FROM transactions t WHERE ${filter.where}''',
          filter.arguments,
        );
        final count = counts.single['total']! as int;
        final latest = counts.single['latest_update']! as String;
        final page = await SqliteTransactionRepository(
          database,
        ).queryWithExecutor(
          TransactionRepositoryQuery(
            from: DateTime.parse(settlement.periodStart),
            to: DateTime.parse(settlement.periodEnd),
            occurredAtFrom: occurredAtFrom,
            occurredAtToExclusive: occurredAtToExclusive,
            paymentSourceId: settlement.paymentSourceId,
            status: TransactionStatus.active,
            excludeTransfers: true,
            offset: offset,
            limit: limit,
          ),
          executor,
        );
        return PaymentSettlementTransactionPage(
          rows: List.unmodifiable(page),
          totalCount: count,
          recordedTotal: null,
          summaryPending: true,
          snapshotToken: _snapshotToken(settlement, count, latest),
        );
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'page settlement transactions');
    }
  }

  @override
  Future<PaymentSettlementTransactionSummary> summarizeTransactions(
    PaymentSettlement settlement, {
    DateTime? occurredAtFrom,
    DateTime? occurredAtToExclusive,
  }) async {
    final filter = _periodFilter(
      settlement,
      occurredAtFrom: occurredAtFrom,
      occurredAtToExclusive: occurredAtToExclusive,
    );
    try {
      // The full-period exact-decimal summary is an independent operation,
      // so device detail can render its first 20 rows without waiting for it.
      // This snapshot is consistent *within* the 400-row scalar scan.
      return await database.transaction((executor) async {
        const batchSize = 400;
        var cursor = '';
        var totalCount = 0;
        var latest = '';
        var sum = DecimalValue.fromParts(
          coefficient: BigInt.zero,
          scale: 0,
        );
        var canCompare = true;
        while (true) {
          final values = await executor.rawQuery(
            '''SELECT t.id, t.updated_at, t.direction, t.currency,
                      t.amount_coefficient, t.amount_scale
               FROM transactions t
               WHERE ${filter.where} AND t.id > ?
               ORDER BY t.id LIMIT ?''',
            [...filter.arguments, cursor, batchSize],
          );
          if (values.isEmpty) break;
          for (final row in values) {
            totalCount++;
            final updated = row['updated_at']! as String;
            if (updated.compareTo(latest) > 0) latest = updated;
            if (!canCompare) continue;
            if ((row['currency'] as String).trim().toUpperCase() !=
                    settlement.payment.currency.value ||
                row['direction'] == TransactionDirection.adjustment.name) {
              canCompare = false;
              continue;
            }
            final amount = DecimalValue.fromParts(
              coefficient: BigInt.parse(row['amount_coefficient']! as String),
              scale: row['amount_scale']! as int,
            ).abs();
            final direction = row['direction'] as String;
            if (direction == TransactionDirection.expense.name) {
              sum = sum.add(amount);
            } else if (direction == TransactionDirection.refund.name ||
                direction == TransactionDirection.income.name) {
              sum = sum.subtract(amount);
            }
          }
          cursor = values.last['id']! as String;
          if (values.length < batchSize) break;
          await Future<void>.delayed(Duration.zero);
        }
        return PaymentSettlementTransactionSummary(
          totalCount: totalCount,
          recordedTotal: canCompare
              ? Money(amount: sum, currency: settlement.payment.currency)
              : null,
          snapshotToken: _snapshotToken(settlement, totalCount, latest),
        );
      });
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'summarize settlement transactions');
    }
  }

  static ({String where, List<Object?> arguments}) _periodFilter(
    PaymentSettlement settlement, {
    DateTime? occurredAtFrom,
    DateTime? occurredAtToExclusive,
  }) {
    const knownDate = "("
        "TRIM(COALESCE(t.transaction_date, '')) != '' AND "
        "TRIM(t.transaction_date) >= ? AND "
        "TRIM(t.transaction_date) <= ?)";
    final occurredParts = <String>[
      "TRIM(COALESCE(t.transaction_date, '')) = ''",
      't.occurred_at IS NOT NULL',
    ];
    final occurredArgs = <Object?>[];
    if (occurredAtFrom != null) {
      occurredParts.add('t.occurred_at >= ?');
      occurredArgs.add(_instantBound(occurredAtFrom));
    }
    if (occurredAtToExclusive != null) {
      occurredParts.add('t.occurred_at < ?');
      occurredArgs.add(_instantBound(occurredAtToExclusive));
    }
    final period = occurredArgs.isEmpty
        ? knownDate
        : '($knownDate OR (${occurredParts.join(' AND ')}))';
    return (
      where: 't.payment_source_id = ? AND t.status = ? '
          'AND t.direction != ? AND $period',
      arguments: <Object?>[
        settlement.paymentSourceId.value,
        TransactionStatus.active.name,
        TransactionDirection.transfer.name,
        settlement.periodStart,
        settlement.periodEnd,
        ...occurredArgs,
      ],
    );
  }

  // Also bind the signature to the settlement definition. A concurrent
  // statement-period or source edit must never attach the old comparison
  // amount to the newly loaded transaction page.
  static String _snapshotToken(
    PaymentSettlement settlement,
    int count,
    String latestUpdate,
  ) => [
    settlement.id.value,
    settlement.paymentSourceId.value,
    settlement.periodStart,
    settlement.periodEnd,
    settlement.payment.currency.value,
    '${count}',
    latestUpdate,
  ].join('|');

  static String _instantBound(DateTime value) {
    final iso = value.toUtc().toIso8601String();
    return iso.endsWith('Z') ? iso.substring(0, iso.length - 1) : iso;
  }

  @override
  Future<void> remove(PaymentSettlementId id) async {
    try {
      await database.connection.delete(
        'payment_settlements',
        where: 'id = ?',
        whereArgs: [id.value],
      );
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'remove payment settlement');
    }
  }

  static Map<String, Object?> _row(PaymentSettlement value) => {
    'id': value.id.value,
    'payment_source_id': value.paymentSourceId.value,
    'payment_amount_coefficient': value.payment.amount.coefficient.toString(),
    'payment_amount_scale': value.payment.amount.scale,
    'payment_currency': value.payment.currency.value,
    'payment_date': value.paymentDate,
    'period_start': value.periodStart,
    'period_end': value.periodEnd,
    'statement_balance_coefficient': value.statementBalance?.amount.coefficient
        .toString(),
    'statement_balance_scale': value.statementBalance?.amount.scale,
    'statement_balance_currency': value.statementBalance?.currency.value,
    'status': value.status.name,
    'description': value.description,
    'external_reference': value.externalReference,
    'created_at': value.createdAt.toIso8601String(),
    'updated_at': value.updatedAt.toIso8601String(),
  };

  static PaymentSettlement _fromRow(Map<String, Object?> row) {
    final statementCoefficient =
        row['statement_balance_coefficient'] as String?;
    final statementScale = row['statement_balance_scale'] as int?;
    final statementCurrency = row['statement_balance_currency'] as String?;
    return PaymentSettlement(
      id: PaymentSettlementId(row['id']! as String),
      paymentSourceId: PaymentSourceId(row['payment_source_id']! as String),
      payment: Money(
        amount: DecimalValue.fromParts(
          coefficient: BigInt.parse(
            row['payment_amount_coefficient']! as String,
          ),
          scale: row['payment_amount_scale']! as int,
        ),
        currency: CurrencyCode(row['payment_currency']! as String),
      ),
      paymentDate: row['payment_date']! as String,
      periodStart: row['period_start']! as String,
      periodEnd: row['period_end']! as String,
      statementBalance:
          statementCoefficient == null ||
              statementScale == null ||
              statementCurrency == null
          ? null
          : Money(
              amount: DecimalValue.fromParts(
                coefficient: BigInt.parse(statementCoefficient),
                scale: statementScale,
              ),
              currency: CurrencyCode(statementCurrency),
            ),
      status: PaymentSettlementStatus.values.byName(row['status']! as String),
      description: row['description'] as String?,
      externalReference: row['external_reference'] as String?,
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }
}
