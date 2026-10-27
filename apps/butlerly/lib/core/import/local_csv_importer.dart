import 'dart:convert';

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart';

import 'butlerly_csv_template.dart';

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
    required this.externalReference,
    required this.original,
    this.error,
    this.merchant,
    this.notes,
  });

  final int rowNumber;
  final String date;
  final String description;
  final String amount;
  final String currency;
  final TransactionDirection? direction;
  final String? cardReference;
  final String? externalReference;
  final String original;
  final String? error;
  final String? merchant;
  final String? notes;

  bool get isValid => error == null;
}

final class CsvStatementPreview {
  const CsvStatementPreview({
    required this.rows,
    required this.errors,
    this.templateKind,
  });

  final ButlerlyCsvKind? templateKind;
  final List<CsvStatementRow> rows;
  final List<String> errors;
  int get validCount => rows.where((row) => row.isValid).length;
}

typedef CsvDuplicateChecker =
    Future<ApplicationResult<DuplicateTransactionCheckResult>> Function(
      DuplicateTransactionCheckCommand command,
    );

final class LocalCsvImporter {
  LocalCsvImporter(FinanceServices finance)
    : _importTransaction = finance.importTransaction.call,
      _duplicateChecker = finance.duplicateTransactionChecker.call;

  const LocalCsvImporter.withHandler(
    this._importTransaction, {
    CsvDuplicateChecker? duplicateChecker,
  }) : _duplicateChecker = duplicateChecker;

  final Future<ApplicationResult<TransactionDto>> Function(
    ImportTransactionCommand command,
  )
  _importTransaction;
  final CsvDuplicateChecker? _duplicateChecker;

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
      final amount = _normalizedAmount(rawAmount);
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
        externalReference: _optional(valueAt('transaction_id')),
        original: _encodeCsvRow(values),
        error: error,
      );
      parsed.add(row);
      if (error != null) errors.add('Row ${index + 1}: $error.');
    }
    return CsvStatementPreview(rows: parsed, errors: errors);
  }

  /// Accept only the selected Butlerly V1 schema in the user import flow.
  Future<CsvStatementPreview> previewTemplate(
    XFile file, {
    required ButlerlyCsvKind kind,
    String languageCode = 'en',
  }) async {
    final language = ButlerlyCsvTemplate.language(languageCode);
    final rows = _parseCsv(await file.readAsString());
    final expected = ButlerlyCsvTemplate.headers(kind);
    if (rows.isEmpty) {
      return CsvStatementPreview(
        rows: const [],
        errors: [ _localizedCsvError('empty', language) ],
        templateKind: kind,
      );
    }
    if (!ButlerlyCsvTemplate.matchesHeaders(kind, rows.first)) {
      return CsvStatementPreview(
        rows: const [],
        errors: [
          '${_localizedCsvError('headers', language)} '
          '${ButlerlyCsvTemplate.filename(kind, languageCode: language)}: '
          '${ButlerlyCsvTemplate.displayHeaders(kind, languageCode: language).join(', ')}.',
        ],
        templateKind: kind,
      );
    }
    final parsed = <CsvStatementRow>[];
    final errors = <String>[];
    final references = <String>{};
    for (var index = 1; index < rows.length; index++) {
      final values = rows[index];
      if (values.every((value) => value.trim().isEmpty)) continue;
      String value(String field) {
        final column = expected.indexOf(field);
        return column < 0 || column >= values.length
            ? ''
            : values[column].trim();
      }

      final date = value('date');
      final amount = kind == ButlerlyCsvKind.receipts
          ? value('total')
          : value('amount');
      final currency = value('currency');
      final description = kind == ButlerlyCsvKind.receipts
          ? value('merchant')
          : value('description');
      final merchant = value('merchant');
      final reference = kind == ButlerlyCsvKind.receipts
          ? value('receipt_id')
          : value('transaction_id');
      final direction = kind == ButlerlyCsvKind.receipts
          ? TransactionDirection.expense
          : switch (ButlerlyCsvTemplate.canonicalDirection(value('direction'))) {
              'expense' => TransactionDirection.expense,
              'income' => TransactionDirection.income,
              'transfer' => TransactionDirection.transfer,
              'refund' => TransactionDirection.refund,
              'adjustment' => TransactionDirection.adjustment,
              _ => null,
            };
      String? error;
      if (values.length != expected.length) {
        error = _localizedCsvError('columns', language);
      } else if (!_validDate(date)) {
        error = _localizedCsvError('date', language);
      } else if (description.isEmpty) {
        error = kind == ButlerlyCsvKind.receipts
            ? _localizedCsvError('merchant', language)
            : _localizedCsvError('description', language);
      } else if (kind == ButlerlyCsvKind.receipts && reference.isEmpty) {
        error = _localizedCsvError('receiptId', language);
      } else if (!_validTemplateAmount(amount, allowZero: false)) {
        error = _localizedCsvError('amount', language);
      } else if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
        error = _localizedCsvError('currency', language);
      } else if (direction == null) {
        error =
            _localizedCsvError('direction', language);
      } else if (kind == ButlerlyCsvKind.receipts &&
          (!_validTemplateAmount(
                value('tax'),
                allowZero: true,
                optional: true,
              ) ||
              !_validTemplateAmount(
                value('tip'),
                allowZero: true,
                optional: true,
              ))) {
        error = _localizedCsvError('tax', language);
      } else if (kind == ButlerlyCsvKind.receipts &&
          DecimalValue.parse(amount).compareTo(
                DecimalValue.parse(
                  value('tax').isEmpty ? '0' : value('tax'),
                ).add(
                  DecimalValue.parse(value('tip').isEmpty ? '0' : value('tip')),
                ),
              ) <
              0) {
        error = _localizedCsvError('total', language);
      } else if (reference.isNotEmpty && !references.add(reference)) {
        error = _localizedCsvError('duplicate', language);
      }
      final row = CsvStatementRow(
        rowNumber: index + 1,
        date: date,
        description: description,
        amount: amount,
        currency: currency,
        direction: direction,
        cardReference: kind == ButlerlyCsvKind.transactions
            ? _optional(value('account_reference'))
            : null,
        externalReference: _optional(reference),
        original: _encodeCsvRow(values),
        merchant: _optional(merchant),
        notes: _optional(value('notes')),
        error: error,
      );
      parsed.add(row);
      if (error != null) errors.add(switch (language) {
        'zh' => '第${index + 1}行：$error。',
        'es' => 'Fila ${index + 1}: $error.',
        _ => 'Row ${index + 1}: $error.',
      });
    }
    if (parsed.isEmpty) {
      errors.add(_localizedCsvError('noRows', language));
    }
    return CsvStatementPreview(
      rows: List.unmodifiable(parsed),
      errors: List.unmodifiable(errors),
      templateKind: kind,
    );
  }

  static String _localizedCsvError(String key, String locale) {
    const labels = <String, Map<String, String>>{
      'en': {
        'empty': 'The CSV file is empty.',
        'headers': 'Incorrect CSV template. Use the downloaded template',
        'columns': 'column count does not match the template',
        'date': 'invalid date (use YYYY-MM-DD)',
        'merchant': 'merchant is required',
        'description': 'description is required',
        'receiptId': 'receipt ID is required',
        'amount': 'invalid amount (positive decimal, no signs or commas)',
        'currency': 'invalid currency (use uppercase code, e.g. USD)',
        'direction': 'invalid type (expense, income, transfer, refund or adjustment)',
        'tax': 'invalid tax or tip amount',
        'total': 'total cannot be less than tax plus tip',
        'duplicate': 'duplicate receipt ID or transaction ID in file',
        'noRows': 'The CSV template has no data rows.',
      },
      'zh': {
        'empty': 'CSV 文件为空。',
        'headers': 'CSV 模板不匹配。请使用下载的模板',
        'columns': '该行的列数与模板不一致',
        'date': '日期无效（请使用 YYYY-MM-DD）',
        'merchant': '商家为必填项',
        'description': '描述为必填项',
        'receiptId': '收据编号为必填项',
        'amount': '金额无效（请使用不带符号或千位分隔符的正数）',
        'currency': '币种无效（请使用大写代码，例如 USD）',
        'direction': '交易类型无效（支出、收入、转账、退款、调整）',
        'tax': '税额或小费无效',
        'total': '实付总额不能小于税额与小费之和',
        'duplicate': '文件中存在重复的收据编号或交易编号',
        'noRows': 'CSV 模板中没有数据行。',
      },
      'es': {
        'empty': 'El archivo CSV está vacío.',
        'headers': 'Plantilla CSV incorrecta. Usa la plantilla descargada',
        'columns': 'el número de columnas no coincide con la plantilla',
        'date': 'fecha no válida (usa AAAA-MM-DD)',
        'merchant': 'el comercio es obligatorio',
        'description': 'la descripción es obligatoria',
        'receiptId': 'el ID del recibo es obligatorio',
        'amount': 'importe no válido (decimal positivo sin signo ni separador)',
        'currency': 'moneda no válida (usa el código en mayúsculas, p. ej., USD)',
        'direction': 'tipo no válido (gasto, ingreso, transferencia, reembolso o ajuste)',
        'tax': 'impuesto o propina no válidos',
        'total': 'el total no puede ser menor que impuesto más propina',
        'duplicate': 'ID de recibo o transacción duplicado en el archivo',
        'noRows': 'La plantilla CSV no contiene filas de datos.',
      },
    };
    return labels[locale]?[key] ?? labels['en']![key]!;
  }

  static bool _validTemplateAmount(
    String value, {
    required bool allowZero,
    bool optional = false,
  }) {
    if (optional && value.isEmpty) return true;
    if (!RegExp(r'^\d+(?:\.\d{1,4})?$').hasMatch(value)) return false;
    final decimal = DecimalValue.parse(value);
    return allowZero ? !decimal.isNegative : decimal.isPositive;
  }

  Future<Map<int, List<DuplicateTransactionCandidate>>> findDuplicates(
    CsvStatementPreview preview, {
    String? paymentSourceId,
  }) async {
    final result = <int, List<DuplicateTransactionCandidate>>{};
    for (final row in preview.rows.where((value) => value.isValid)) {
      final candidates = await _duplicatesFor(
        row,
        paymentSourceId: paymentSourceId,
      );
      if (candidates.isNotEmpty) result[row.rowNumber] = candidates;
    }
    return Map.unmodifiable(result);
  }

  Future<CsvImportSummary> commitPreview(
    CsvStatementPreview preview, {
    required String sourceId,
    required String sourceLanguage,
    String? paymentSourceId,
    Map<int, String> confirmedDuplicateTokens = const {},
  }) async {
    // Template-based imports are atomic at validation time: the user must
    // correct every invalid row before any row is committed.
    if (preview.templateKind != null && preview.errors.isNotEmpty) {
      return CsvImportSummary(
        imported: 0,
        duplicates: 0,
        failed: preview.rows.where((row) => !row.isValid).length,
        errors: List.unmodifiable(preview.errors),
      );
    }
    var imported = 0;
    var duplicates = 0;
    var failed = 0;
    final errors = [...preview.errors];
    for (final row in preview.rows.where((value) => value.isValid)) {
      try {
        final duplicateCandidates = await _duplicatesFor(
          row,
          paymentSourceId: paymentSourceId,
        );
        if (duplicateCandidates.isNotEmpty) {
          final currentToken = duplicateConfirmationToken(
            row,
            duplicateCandidates,
            paymentSourceId: paymentSourceId,
          );
          if (confirmedDuplicateTokens[row.rowNumber] != currentToken) {
            duplicates++;
            errors.add(
              'Row ${row.rowNumber}: possible duplicate requires confirmation.',
            );
            continue;
          }
        }
        final fingerprint = _fingerprint(
          [
            row.date,
            row.amount,
            row.currency,
            row.direction!.name,
            row.description,
            row.cardReference ?? '',
            row.externalReference ?? '',
            preview.templateKind?.name ?? '',
          ].join('|'),
        );
        final result = await _importTransaction(
          ImportTransactionCommand(
            id: 'payment-$fingerprint',
            provenanceId: 'payment-provenance-$fingerprint',
            sourceId: preview.templateKind == null
                ? sourceId
                : 'butlerly-csv-${preview.templateKind!.name}:$sourceId',
            originalRepresentation: row.original,
            money: Money(
              amount: DecimalValue.parse(row.amount),
              currency: CurrencyCode(row.currency),
            ),
            direction: row.direction!,
            transactionDate: row.date,
            description: row.description,
            rawCounterparty: row.merchant ?? row.description,
            sourceLanguage: sourceLanguage,
            notes: row.notes,
            paymentSourceId: paymentSourceId,
            externalReference: row.externalReference ?? row.cardReference,
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

  static String duplicateConfirmationToken(
    CsvStatementRow row,
    List<DuplicateTransactionCandidate> candidates, {
    String? paymentSourceId,
  }) {
    final candidateIds =
        candidates
            .map((candidate) => candidate.transaction.id)
            .toList(growable: false)
          ..sort();
    return [
      '${row.rowNumber}',
      row.date,
      row.amount,
      row.currency,
      row.direction?.name ?? '',
      paymentSourceId ?? '',
      ...candidateIds,
    ].join('|');
  }

  Future<List<DuplicateTransactionCandidate>> _duplicatesFor(
    CsvStatementRow row, {
    String? paymentSourceId,
  }) async {
    final checker = _duplicateChecker;
    if (checker == null || row.direction == null || !row.isValid) {
      return const [];
    }
    final result = await checker(
      DuplicateTransactionCheckCommand(
        transactionDate: row.date,
        amount: row.amount,
        currency: row.currency,
        direction: row.direction!,
        paymentSourceId: paymentSourceId,
      ),
    );
    return switch (result) {
      ApplicationSuccess<DuplicateTransactionCheckResult>(:final value) =>
        value.candidates,
      ApplicationFailure<DuplicateTransactionCheckResult>() => throw StateError(
        'Duplicate check could not be completed.',
      ),
    };
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
        final direction = _direction(row['direction']!);
        final amount = _normalizedAmount(row['amount']!);
        final currency = row['currency']!.trim().toUpperCase();
        final importRow = CsvStatementRow(
          rowNumber: index + 1,
          date: row['date']!.trim(),
          description: _optional(row['description']) ?? '',
          amount: amount,
          currency: currency,
          direction: direction,
          cardReference:
              _optional(row['card_reference']) ??
              _optional(row['account_reference']),
          externalReference:
              _optional(row['transaction_id']) ?? _optional(row['reference']),
          original: _encodeCsvRow(values),
        );
        if ((await _duplicatesFor(importRow)).isNotEmpty) {
          duplicates++;
          errors.add(
            'Row ${index + 1}: possible duplicate requires preview confirmation.',
          );
          continue;
        }
        final original = importRow.original;
        final fingerprint = _fingerprint(
          [
            row['date']!.trim(),
            amount,
            currency,
            direction.name,
            row['description'] ?? '',
            row['counterparty'] ?? '',
            row['card_reference'] ?? row['account_reference'] ?? '',
            row['transaction_id'] ?? row['reference'] ?? '',
          ].join('|'),
        );
        final result = await _importTransaction(
          ImportTransactionCommand(
            id: 'import-$fingerprint',
            provenanceId: 'import-provenance-$fingerprint',
            sourceId: file.name,
            originalRepresentation: original,
            money: Money(
              amount: DecimalValue.parse(amount),
              currency: CurrencyCode(currency),
            ),
            direction: direction,
            transactionDate: row['date']!.trim(),
            occurredAtUtc: _optionalInstant(row['occurred_at_utc']),
            timeZoneId: _optional(row['time_zone_id']),
            description: _optional(row['description']),
            rawCounterparty: _optional(row['counterparty']),
            sourceLanguage: _optional(row['source_language']) ?? sourceLanguage,
            notes: _optional(row['notes']),
            externalReference:
                _optional(row['transaction_id']) ??
                _optional(row['reference']) ??
                _optional(row['card_reference']),
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

  static String _normalizedAmount(String value) =>
      value.trim().replaceFirst(RegExp(r'^[+-]'), '').replaceAll(',', '');

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
      'transaction_id': [
        'transaction_id',
        'transaction_reference',
        'reference',
        'id',
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
