import 'dart:convert';

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart';

final class CsvImportSummary {
  const CsvImportSummary({
    required this.imported,
    required this.duplicates,
    required this.failed,
    required this.errors,
  });

  final int imported;
  final int duplicates;
  final int failed;
  final List<String> errors;
}

final class CsvStatementRow {
  const CsvStatementRow({
    required this.rowNumber,
    required this.date,
    required this.description,
    required this.amount,
    required this.currency,
    required this.direction,
    required this.cardReference,
    required this.original,
    this.error,
  });

  final int rowNumber;
  final String date;
  final String description;
  final String amount;
  final String currency;
  final TransactionDirection? direction;
  final String? cardReference;
  final String original;
  final String? error;

  bool get isValid => error == null;
}

final class CsvStatementPreview {
  const CsvStatementPreview({required this.rows, required this.errors});

  final List<CsvStatementRow> rows;
  final List<String> errors;
  int get validCount => rows.where((row) => row.isValid).length;
}

final class LocalCsvImporter {
  LocalCsvImporter(FinanceServices finance)
    : _importTransaction = finance.importTransaction.call;

  const LocalCsvImporter.withHandler(this._importTransaction);

  final Future<ApplicationResult<TransactionDto>> Function(
    ImportTransactionCommand command,
  )
  _importTransaction;

  static const acceptedHeaders = <String>{
    'date',
    'amount',
    'currency',
    'direction',
  };

  Future<CsvStatementPreview> preview(XFile file) async {
    final content = await file.readAsString();
    final rows = _parseCsv(content);
    if (rows.isEmpty) {
      return const CsvStatementPreview(
        rows: [],
        errors: ['The CSV file is empty.'],
      );
    }
    final headers = rows.first.map(_header).toList(growable: false);
    final indexes = _columnIndexes(headers);
    final missing = [
      'date',
      'amount',
      'description',
      'currency',
    ].where((key) => !indexes.containsKey(key)).toList(growable: false);
    if (missing.isNotEmpty) {
      return CsvStatementPreview(
        rows: const [],
        errors: ['Missing required columns: ${missing.join(', ')}.'],
      );
    }
    final parsed = <CsvStatementRow>[];
    final errors = <String>[];
    for (var index = 1; index < rows.length; index++) {
      final values = rows[index];
      if (values.every((value) => value.trim().isEmpty)) continue;
      String valueAt(String key) =>
          indexes[key] != null && indexes[key]! < values.length
          ? values[indexes[key]!].trim()
          : '';
      final rawDate = valueAt('date');
      final rawAmount = valueAt('amount');
      final rawCurrency = valueAt('currency').toUpperCase();
      final rawDirection = valueAt('direction');
      final signed = rawAmount.startsWith('-');
      final amount = rawAmount
          .replaceFirst(RegExp(r'^[+-]'), '')
          .replaceAll(',', '');
      String? error;
      if (values.length != headers.length) {
        error = 'column count does not match the header';
      } else if (!_validDate(rawDate)) {
        error = 'invalid date (use YYYY-MM-DD)';
      } else if (double.tryParse(amount) == null || double.parse(amount) <= 0) {
        error = 'invalid amount';
      } else if (!RegExp(r'^[A-Z]{3}$').hasMatch(rawCurrency)) {
        error = 'invalid currency';
      }
      final direction = _statementDirection(rawDirection, signed);
      if (error == null && direction == null) {
        error = 'missing debit/credit direction';
      }
      final row = CsvStatementRow(
        rowNumber: index + 1,
        date: rawDate,
        description: valueAt('description'),
        amount: amount,
        currency: rawCurrency,
        direction: direction,
        cardReference: _optional(valueAt('card_reference')),
        original: _encodeCsvRow(values),
        error: error,
      );
      parsed.add(row);
      if (error != null) errors.add('Row ${index + 1}: $error.');
    }
    return CsvStatementPreview(rows: parsed, errors: errors);
  }

  Future<CsvImportSummary> commitPreview(
    CsvStatementPreview preview, {
    required String sourceId,
    required String sourceLanguage,
    String? paymentSourceId,
  }) async {
    var imported = 0;
    var duplicates = 0;
    var failed = 0;
    final errors = [...preview.errors];
    for (final row in preview.rows.where((value) => value.isValid)) {
      try {
        final fingerprint = _fingerprint(
          [
            row.date,
            row.amount,
            row.currency,
            row.direction!.name,
            row.description,
          ].join('|'),
        );
        final result = await _importTransaction(
          ImportTransactionCommand(
            id: 'payment-$fingerprint',
            provenanceId: 'payment-provenance-$fingerprint',
            sourceId: sourceId,
            originalRepresentation: row.original,
            money: Money(
              amount: DecimalValue.parse(row.amount),
              currency: CurrencyCode(row.currency),
            ),
            direction: row.direction!,
            transactionDate: row.date,
            description: row.description,
            rawCounterparty: row.description,
            sourceLanguage: sourceLanguage,
            paymentSourceId: paymentSourceId,
          ),
        );
        if (result is ApplicationSuccess<TransactionDto>) {
          imported++;
        } else if ((result as ApplicationFailure<TransactionDto>)
                .failure
                .code ==
            ApplicationFailureCode.conflict) {
          duplicates++;
        } else {
          failed++;
          errors.add('Row ${row.rowNumber}: could not be imported.');
        }
      } on Object {
        failed++;
        errors.add('Row ${row.rowNumber}: could not be imported.');
      }
    }
    return CsvImportSummary(
      imported: imported,
      duplicates: duplicates,
      failed: failed,
      errors: List.unmodifiable(errors),
    );
  }

  Future<CsvImportSummary> import(
    XFile file, {
    required String sourceLanguage,
  }) async {
    final content = await file.readAsString();
    final rows = _parseCsv(content);
    if (rows.isEmpty) {
      return const CsvImportSummary(
        imported: 0,
        duplicates: 0,
        failed: 1,
        errors: ['The CSV file is empty.'],
      );
    }
    final headers = rows.first
        .map((value) => value.trim().toLowerCase())
        .toList();
    if (!headers.toSet().containsAll(acceptedHeaders)) {
      return const CsvImportSummary(
        imported: 0,
        duplicates: 0,
        failed: 1,
        errors: ['Required columns: date, amount, currency, direction.'],
      );
    }

    var imported = 0;
    var duplicates = 0;
    var failed = 0;
    final errors = <String>[];
    for (var index = 1; index < rows.length; index++) {
      final values = rows[index];
      if (values.every((value) => value.trim().isEmpty)) continue;
      if (values.length != headers.length) {
        failed++;
        errors.add('Row ${index + 1}: column count does not match the header.');
        continue;
      }
      final row = <String, String>{
        for (var column = 0; column < headers.length; column++)
          headers[column]: values[column],
      };
      try {
        final original = _encodeCsvRow(values);
        final fingerprint = _fingerprint(
          [
            row['date']!,
            row['amount']!,
            row['currency']!,
            row['direction']!,
            row['description'] ?? '',
            row['counterparty'] ?? '',
          ].join('|'),
        );
        final result = await _importTransaction(
          ImportTransactionCommand(
            id: 'import-$fingerprint',
            provenanceId: 'import-provenance-$fingerprint',
            sourceId: file.name,
            originalRepresentation: original,
            money: Money(
              amount: DecimalValue.parse(row['amount']!),
              currency: CurrencyCode(row['currency']!),
            ),
            direction: _direction(row['direction']!),
            transactionDate: row['date']!.trim(),
            occurredAtUtc: _optionalInstant(row['occurred_at_utc']),
            timeZoneId: _optional(row['time_zone_id']),
            description: _optional(row['description']),
            rawCounterparty: _optional(row['counterparty']),
            sourceLanguage: _optional(row['source_language']) ?? sourceLanguage,
            notes: _optional(row['notes']),
          ),
        );
        if (result is ApplicationSuccess<TransactionDto>) {
          imported++;
        } else if ((result as ApplicationFailure<TransactionDto>)
                .failure
                .code ==
            ApplicationFailureCode.conflict) {
          duplicates++;
        } else {
          failed++;
          errors.add('Row ${index + 1}: invalid transaction data.');
        }
      } on Object {
        failed++;
        errors.add('Row ${index + 1}: invalid transaction data.');
      }
    }
    return CsvImportSummary(
      imported: imported,
      duplicates: duplicates,
      failed: failed,
      errors: List.unmodifiable(errors),
    );
  }

  static String _header(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  static Map<String, int> _columnIndexes(List<String> headers) {
    const aliases = <String, List<String>>{
      'date': ['date', 'transaction_date', 'posting_date', 'posted_date'],
      'description': [
        'description',
        'merchant',
        'merchant_name',
        'details',
        'memo',
      ],
      'amount': ['amount', 'transaction_amount', 'value'],
      'currency': ['currency', 'currency_code'],
      'direction': ['direction', 'type', 'debit_credit', 'credit_debit'],
      'card_reference': [
        'card',
        'card_number',
        'card_reference',
        'account',
        'account_reference',
      ],
    };
    final result = <String, int>{};
    for (final entry in aliases.entries) {
      final index = headers.indexWhere(entry.value.contains);
      if (index >= 0) result[entry.key] = index;
    }
    return result;
  }

  static bool _validDate(String value) {
    final parsed = DateTime.tryParse(value);
    return value.length == 10 &&
        parsed != null &&
        parsed.toIso8601String().substring(0, 10) == value;
  }

  static TransactionDirection? _statementDirection(
    String value,
    bool negative,
  ) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('credit') ||
        normalized == 'cr' ||
        normalized == 'income') {
      return TransactionDirection.income;
    }
    if (normalized.contains('debit') ||
        normalized == 'dr' ||
        normalized == 'expense') {
      return TransactionDirection.expense;
    }
    if (negative) return TransactionDirection.expense;
    return null;
  }

  static List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    for (var index = 0; index < input.length; index++) {
      final character = input[index];
      if (character == '"') {
        if (quoted && index + 1 < input.length && input[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          quoted = !quoted;
        }
      } else if (character == ',' && !quoted) {
        row.add(field.toString());
        field = StringBuffer();
      } else if ((character == '\n' || character == '\r') && !quoted) {
        if (character == '\r' &&
            index + 1 < input.length &&
            input[index + 1] == '\n') {
          index++;
        }
        row.add(field.toString());
        rows.add(row);
        row = <String>[];
        field = StringBuffer();
      } else {
        field.write(character);
      }
    }
    if (quoted) throw const FormatException('Unclosed quoted field.');
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }
    if (rows.isNotEmpty && rows.first.isNotEmpty) {
      rows.first[0] = rows.first[0].replaceFirst('\ufeff', '');
    }
    return rows;
  }

  static String _encodeCsvRow(List<String> values) =>
      values.map((value) => '"${value.replaceAll('"', '""')}"').join(',');

  static String _fingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(value.trim())) {
      hash ^= byte;
      hash = (hash * 16777619).toUnsigned(32);
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static TransactionDirection _direction(String value) =>
      switch (value.trim().toLowerCase()) {
        'expense' => TransactionDirection.expense,
        'income' => TransactionDirection.income,
        'transfer' => TransactionDirection.transfer,
        'refund' => TransactionDirection.refund,
        'adjustment' => TransactionDirection.adjustment,
        _ => throw const FormatException('Unsupported direction.'),
      };

  static DateTime? _optionalInstant(String? value) {
    final normalized = _optional(value);
    if (normalized == null) return null;
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('Exact timestamps must include UTC Z.');
    }
    return parsed;
  }

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
