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
