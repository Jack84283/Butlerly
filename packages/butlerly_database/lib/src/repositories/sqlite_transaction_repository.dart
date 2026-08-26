import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common/sqlite_api.dart' hide Transaction;

import '../database/butlerly_database.dart';
import '../mappers/sqlite_helpers.dart';

final class SqliteTransactionRepository implements TransactionRepository {
  const SqliteTransactionRepository(this.database);

  final ButlerlyDatabase database;

  @override
  Future<void> save(Transaction value) async {
    try {
      await database.transaction(
        (executor) => saveWithExecutor(executor, value),
      );
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'save transaction');
    }
  }

  static Future<void> saveWithExecutor(
    DatabaseExecutor executor,
    Transaction value,
  ) async {
    for (final provenance in value.provenance) {
      await saveProvenance(executor, provenance);
    }
    final row = _transactionToRow(value);
    final existing = await executor.query(
      'transactions',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [value.id.value],
      limit: 1,
    );
    if (existing.isEmpty) {
      await executor.insert('transactions', row);
    } else {
      await executor.update(
        'transactions',
        row,
        where: 'id = ?',
        whereArgs: [value.id.value],
      );
    }
    await _replaceChildren(executor, value);
  }

  @override
  Future<Transaction?> findById(TransactionId id) async {
    final rows = await database.connection.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id.value],
    );
    if (rows.isEmpty) return null;
    return _hydrate(rows.single);
  }

  @override
  Future<List<Transaction>> listAll() async {
    final rows = await database.connection.query(
      'transactions',
      orderBy: 'COALESCE(occurred_at, created_at) DESC, id',
    );
    return Future.wait(rows.map(_hydrate));
  }

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async {
    final conditions = <String>[];
    final arguments = <Object?>[];
    final text = query.text?.trim().toLowerCase();
    if (text != null && text.isNotEmpty) {
      conditions.add('''(
        LOWER(COALESCE(t.description, '')) LIKE ? OR
        LOWER(COALESCE(t.raw_counterparty, '')) LIKE ? OR
        LOWER(COALESCE(t.notes, '')) LIKE ? OR
        LOWER(COALESCE(m.name, '')) LIKE ? OR
        LOWER(COALESCE(c.name, '')) LIKE ? OR
        EXISTS (
          SELECT 1 FROM attachment_links al
          JOIN evidence_items e ON e.id = al.evidence_id
          LEFT JOIN extractions x ON x.evidence_id = e.id
          WHERE al.transaction_id = t.id AND (
            LOWER(e.original_name) LIKE ? OR
            LOWER(COALESCE(x.values_json, '')) LIKE ?
          )
        )
      )''');
      arguments.addAll(List<Object?>.filled(7, '%$text%'));
    }
    if (query.from != null) {
      conditions.add('t.transaction_date >= ?');
      arguments.add(_dateOnly(query.from!));
    }
    if (query.to != null) {
      conditions.add('t.transaction_date <= ?');
      arguments.add(_dateOnly(query.to!));
    }
    if (query.categoryId != null) {
      conditions.add('t.category_id = ?');
      arguments.add(query.categoryId!.value);
    }
    if (query.paymentSourceId != null) {
      conditions.add('t.payment_source_id = ?');
      arguments.add(query.paymentSourceId!.value);
    }
    if (query.currency != null) {
      conditions.add('t.currency = ?');
      arguments.add(query.currency!.trim().toUpperCase());
    }
    if (query.direction != null) {
      conditions.add('t.direction = ?');
      arguments.add(query.direction!.name);
    }
    if (query.status != null) {
      conditions.add('t.status = ?');
      arguments.add(query.status!.name);
    }
    if (query.needsReview != null) {
      final qualifier = query.needsReview! ? 'EXISTS' : 'NOT EXISTS';
      conditions.add('''$qualifier (
        SELECT 1 FROM review_issues ri
        WHERE ri.transaction_id = t.id AND ri.status = 'active'
      )''');
    }

    try {
      final rows = await database.connection.rawQuery(
        '''SELECT DISTINCT t.* FROM transactions t
           LEFT JOIN merchants m ON m.id = t.merchant_id
           LEFT JOIN categories c ON c.id = t.category_id
           ${conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}'}
           ORDER BY t.transaction_date DESC, t.id''',
        arguments,
      );
      return await Future.wait(rows.map(_hydrate));
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'query transactions');
    }
  }

  @override
  Future<void> removePermanently(TransactionId id) async {
    try {
      await database.connection.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [id.value],
      );
    } on DatabaseException catch (error) {
      throw mapDatabaseException(error, 'remove transaction permanently');
    }
  }

  Future<Transaction> _hydrate(Map<String, Object?> row) async {
    final id = row['id']! as String;
    final provenanceRows = await database.connection.rawQuery(
      '''SELECT p.* FROM provenances p
         INNER JOIN transaction_provenances tp ON tp.provenance_id = p.id
         WHERE tp.transaction_id = ? ORDER BY p.captured_at''',
      [id],
    );
    final tagRows = await database.connection.query(
      'transaction_tags',
      columns: ['tag_id'],
      where: 'transaction_id = ?',
      whereArgs: [id],
    );
    final issueRows = await database.connection.query(
      'review_issues',
      where: 'transaction_id = ?',
      whereArgs: [id],
      orderBy: 'created_at',
    );
    final normalizedRows = await database.connection.rawQuery(
      '''SELECT n.amount_coefficient, n.amount_scale, n.currency,
                r.id AS rate_id, r.from_currency, r.to_currency,
                r.rate_coefficient, r.rate_scale, r.effective_at, r.source
         FROM normalized_money n
         LEFT JOIN exchange_rates r ON r.id = n.exchange_rate_id
         WHERE n.transaction_id = ? ORDER BY r.effective_at''',
      [id],
    );

    final money = Money(
      amount: decimalFromRow(row, 'amount_coefficient', 'amount_scale'),
      currency: CurrencyCode(row['currency']! as String),
    );
    return Transaction(
      id: TransactionId(id),
      timing: _timingFromRow(row),
      money: money,
      direction: TransactionDirection.values.byName(
        row['direction']! as String,
      ),
      sourceType: TransactionSourceType.values.byName(
        row['source_type']! as String,
      ),
      status: TransactionStatus.values.byName(row['status']! as String),
      description: row['description'] as String?,
      rawCounterparty: row['raw_counterparty'] as String?,
      externalReference: row['external_reference'] as String?,
      sourceLanguage: row['source_language'] as String?,
      notes: row['notes'] as String?,
      paymentSourceId: _optionalId(
        row['payment_source_id'],
        PaymentSourceId.new,
      ),
      merchantId: _optionalId(row['merchant_id'], MerchantId.new),
      categoryId: _optionalId(row['category_id'], CategoryId.new),
      tagIds: tagRows
          .map((value) => TagId(value['tag_id']! as String))
          .toList(),
      provenance: provenanceRows.map(provenanceFromRow).toList(),
      reviewIssues: issueRows.map(_reviewIssueFromRow).toList(),
      normalizedMoney: normalizedRows
          .map((value) => _normalizedMoneyFromRow(money, value))
          .toList(),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
      transactionDate: row['transaction_date'] as String?,
      timeZoneId: row['time_zone_id'] as String?,
    );
  }

  static Future<void> _replaceChildren(
    DatabaseExecutor executor,
    Transaction value,
  ) async {
    for (final table in [
      'transaction_provenances',
      'transaction_tags',
      'review_issues',
      'normalized_money',
    ]) {
      await executor.delete(
        table,
        where: 'transaction_id = ?',
        whereArgs: [value.id.value],
      );
    }
    for (final provenance in value.provenance) {
      await executor.insert('transaction_provenances', {
        'transaction_id': value.id.value,
        'provenance_id': provenance.id.value,
      });
    }
    for (final tagId in value.tagIds) {
      await executor.insert('transaction_tags', {
        'transaction_id': value.id.value,
        'tag_id': tagId.value,
      });
    }
    for (final issue in value.reviewIssues) {
      await executor.insert('review_issues', _reviewIssueToRow(issue));
    }
    for (final normalized in value.normalizedMoney) {
      await _saveNormalizedMoney(executor, value.id, normalized);
    }
  }

  static Map<String, Object?> _transactionToRow(Transaction value) => {
    'id': value.id.value,
    'occurred_at': value.timing is KnownTransactionTime
        ? (value.timing as KnownTransactionTime).occurredAt.toIso8601String()
        : null,
    'occurred_at_utc': value.timing is KnownTransactionTime
        ? (value.timing as KnownTransactionTime).occurredAt.toIso8601String()
        : null,
    'transaction_date': value.transactionDate,
    'time_zone_id': value.timeZoneId,
    'unknown_time_reason': value.timing is UnknownTransactionTime
        ? (value.timing as UnknownTransactionTime).reason.name
        : null,
    ...decimalToColumns(
      value.money.amount,
      'amount_coefficient',
      'amount_scale',
    ),
    'currency': value.money.currency.value,
    'direction': value.direction.name,
    'source_type': value.sourceType.name,
    'status': value.status.name,
    'description': value.description,
    'raw_counterparty': value.rawCounterparty,
    'external_reference': value.externalReference,
    'source_language': value.sourceLanguage,
    'notes': value.notes,
    'payment_source_id': value.paymentSourceId?.value,
    'merchant_id': value.merchantId?.value,
    'category_id': value.categoryId?.value,
    'created_at': value.createdAt.toIso8601String(),
    'updated_at': value.updatedAt.toIso8601String(),
  };

  static TransactionTiming _timingFromRow(Map<String, Object?> row) {
    final occurredAt = row['occurred_at'] as String?;
    if (occurredAt != null) {
      return KnownTransactionTime(DateTime.parse(occurredAt));
    }
    return UnknownTransactionTime(
      UnknownTransactionTimeReason.values.byName(
        row['unknown_time_reason']! as String,
      ),
    );
  }

  static T? _optionalId<T>(Object? value, T Function(String) create) =>
      value == null ? null : create(value as String);

  static String _dateOnly(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static Map<String, Object?> _reviewIssueToRow(ReviewIssue value) => {
    'id': value.id.value,
    'transaction_id': value.transactionId.value,
    'reason': value.reason.name,
    'status': value.status.name,
    'detail': value.detail,
    'created_at': value.createdAt.toIso8601String(),
    'closed_at': value.closedAt?.toIso8601String(),
  };

  static ReviewIssue _reviewIssueFromRow(Map<String, Object?> row) =>
      ReviewIssue(
        id: ReviewIssueId(row['id']! as String),
        transactionId: TransactionId(row['transaction_id']! as String),
        reason: ReviewIssueReason.values.byName(row['reason']! as String),
        status: ReviewIssueStatus.values.byName(row['status']! as String),
        detail: row['detail'] as String?,
        createdAt: DateTime.parse(row['created_at']! as String),
        closedAt: row['closed_at'] == null
            ? null
            : DateTime.parse(row['closed_at']! as String),
      );

  static Future<void> _saveNormalizedMoney(
    DatabaseExecutor executor,
    TransactionId transactionId,
    NormalizedMoney value,
  ) async {
    final rate = value.exchangeRate;
    if (rate != null) {
      await executor.insert('exchange_rates', {
        'id': rate.id.value,
        'from_currency': rate.fromCurrency.value,
        'to_currency': rate.toCurrency.value,
        ...decimalToColumns(rate.rate, 'rate_coefficient', 'rate_scale'),
        'effective_at': rate.effectiveAt.toIso8601String(),
        'source': rate.source,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await executor.insert('normalized_money', {
      'transaction_id': transactionId.value,
      'exchange_rate_id': rate?.id.value,
      ...decimalToColumns(
        value.converted.amount,
        'amount_coefficient',
        'amount_scale',
      ),
      'currency': value.converted.currency.value,
      'normalization_source': value.source.name,
      'base_currency': value.baseCurrency.value,
      'effective_date': value.effectiveDate,
      'updated_at': value.updatedAt.toIso8601String(),
    });
  }

  static NormalizedMoney _normalizedMoneyFromRow(
    Money original,
    Map<String, Object?> row,
  ) {
    final rateId = row['rate_id'] as String?;
    final rate = rateId == null
        ? null
        : ExchangeRate(
            id: ExchangeRateId(rateId),
            fromCurrency: CurrencyCode(row['from_currency']! as String),
            toCurrency: CurrencyCode(row['to_currency']! as String),
            rate: decimalFromRow(row, 'rate_coefficient', 'rate_scale'),
            effectiveAt: DateTime.parse(row['effective_at']! as String),
            source: row['source']! as String,
          );
    return NormalizedMoney(
      original: original,
      converted: Money(
        amount: decimalFromRow(row, 'amount_coefficient', 'amount_scale'),
        currency: CurrencyCode(row['currency']! as String),
      ),
      exchangeRate: rate,
      source: NormalizationSource.values.byName(
        row['normalization_source'] as String? ?? 'exchangeRate',
      ),
      baseCurrency: CurrencyCode(
        row['base_currency'] as String? ?? row['currency']! as String,
      ),
      effectiveDate: row['effective_date'] as String? ?? '',
      updatedAt: row['updated_at'] == null
          ? null
          : DateTime.parse(row['updated_at']! as String),
    );
  }
}
