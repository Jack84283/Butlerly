import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart' hide Transaction;

import '../database/butlerly_database.dart';
import 'sqlite_transaction_repository.dart';

final class SqlitePaymentSettlementRepository
    implements
        PaymentSettlementRepository,
        PaginatedPaymentSettlementRepository {
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
      // SQLite does the limiting before any domain records are decoded.
      // Use the same order as listAll, with id as a stable tiebreaker.
      final countRows = await database.connection.rawQuery(
        'SELECT COUNT(*) AS total FROM payment_settlements',
      );
      final totalCount = countRows.first['total']! as int;
      final rows = await database.connection.query(
        'payment_settlements',
        orderBy: 'payment_date DESC, id',
        limit: limit,
        offset: offset,
      );
      return PaymentSettlementPage(
        rows: List.unmodifiable(rows.map(_fromRow)),
        totalCount: totalCount,
      );
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
