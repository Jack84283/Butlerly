import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../database/butlerly_database.dart';
import '../mappers/sqlite_helpers.dart';

final class SqliteExchangeRateRepository implements ExchangeRateRepository {
  const SqliteExchangeRateRepository(this.database);
  final ButlerlyDatabase database;

  @override
  Future<void> save(ExchangeRate rate) async {
    await database.connection.insert('exchange_rates', {
      'id': rate.id.value,
      'from_currency': rate.fromCurrency.value,
      'to_currency': rate.toCurrency.value,
      ...decimalToColumns(rate.rate, 'rate_coefficient', 'rate_scale'),
      'effective_at': rate.effectiveAt.toIso8601String(),
      'source': rate.source,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<ExchangeRate?> findApplicable({
    required CurrencyCode fromCurrency,
    required CurrencyCode toCurrency,
    required DateTime financialDate,
  }) async {
    final rows = await database.connection.query(
      'exchange_rates',
      where: 'from_currency = ? AND to_currency = ? AND effective_at <= ?',
      whereArgs: [
        fromCurrency.value,
        toCurrency.value,
        financialDate.toUtc().toIso8601String(),
      ],
      orderBy: 'effective_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return ExchangeRate(
      id: ExchangeRateId(row['id']! as String),
      fromCurrency: CurrencyCode(row['from_currency']! as String),
      toCurrency: CurrencyCode(row['to_currency']! as String),
      rate: decimalFromRow(row, 'rate_coefficient', 'rate_scale'),
      effectiveAt: DateTime.parse(row['effective_at']! as String),
      source: row['source']! as String,
    );
  }
}
