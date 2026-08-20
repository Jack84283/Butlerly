import 'dart:io';

import 'package:butlerly/core/import/local_csv_importer.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'preserves multilingual fields, currency, language, and date-only time',
    () async {
      final root = await Directory.systemTemp.createTemp('butlerly-csv-test-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/transactions.csv');
      await file.writeAsString(
        'date,amount,currency,direction,description,counterparty,source_language\n'
        '2026-08-09,1250.50,jpy,expense,"\u663c\u3054\u98ef, \u5b9a\u98df",\u30ab\u30d5\u30a7,ja\n',
      );
      ImportTransactionCommand? captured;
      final importer = LocalCsvImporter.withHandler((command) async {
        captured = command;
        return ApplicationSuccess<TransactionDto>(_dto(command));
      });

      final summary = await importer.import(
        XFile(file.path),
        sourceLanguage: 'en',
      );

      expect(summary.imported, 1);
      expect(summary.failed, 0);
      expect(captured!.transactionDate, '2026-08-09');
      expect(captured!.occurredAtUtc, isNull);
      expect(captured!.description, '\u663c\u3054\u98ef, \u5b9a\u98df');
      expect(captured!.rawCounterparty, '\u30ab\u30d5\u30a7');
      expect(captured!.sourceLanguage, 'ja');
      expect(captured!.money.currency.value, 'JPY');
      expect(
        captured!.originalRepresentation,
        contains('\u663c\u3054\u98ef, \u5b9a\u98df'),
      );
    },
  );

  test('counts deterministic duplicates and invalid rows separately', () async {
    final root = await Directory.systemTemp.createTemp('butlerly-csv-test-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/transactions.csv');
    await file.writeAsString(
      'date,amount,currency,direction\n'
      '2026-08-09,12.50,USD,expense\n'
      '2026-08-09,12.50,USD,expense\n'
      '2026-08-10,not-money,USD,expense\n',
    );
    final seenIds = <String>{};
    final importer = LocalCsvImporter.withHandler((command) async {
      if (!seenIds.add(command.id)) {
        return const ApplicationFailure<TransactionDto>(
          ApplicationFailureDetail(
            code: ApplicationFailureCode.conflict,
            operation: 'import transaction',
          ),
        );
      }
      return ApplicationSuccess<TransactionDto>(_dto(command));
    });

    final summary = await importer.import(
      XFile(file.path),
      sourceLanguage: 'en',
    );

    expect(summary.imported, 1);
    expect(summary.duplicates, 1);
    expect(summary.failed, 1);
    expect(summary.errors, hasLength(1));
  });

  test('previews bank aliases and validates rows before commit', () async {
    final root = await Directory.systemTemp.createTemp('butlerly-csv-test-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/statement.csv');
    await file.writeAsString(
      'Posting Date,Merchant,Amount,Currency,Debit/Credit,Card\n'
      '2026-08-09,Market,-12.50,USD,Debit,1234\n'
      'bad,Missing,-x,USD,Debit,1234\n',
    );
    final importer = LocalCsvImporter.withHandler(
      (command) async => ApplicationSuccess<TransactionDto>(_dto(command)),
    );

    final preview = await importer.preview(XFile(file.path));

    expect(preview.validCount, 1);
    expect(preview.errors, hasLength(1));
    expect(preview.rows.first.direction, TransactionDirection.expense);
    expect(preview.rows.first.cardReference, '1234');
  });
}

TransactionDto _dto(ImportTransactionCommand command) {
  final now = DateTime.utc(2026, 8, 13);
  return TransactionDto(
    id: command.id,
    amount: command.money.amount.toString(),
    currency: command.money.currency.value,
    direction: command.direction.name,
    status: 'active',
    reviewState: 'clear',
    transactionDate: command.transactionDate,
    occurredAt: command.occurredAtUtc,
    createdAt: now,
    updatedAt: now,
  );
}
