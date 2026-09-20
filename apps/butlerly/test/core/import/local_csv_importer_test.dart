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

  test(
    'direct import normalizes signed amounts before duplicate detection',
    () async {
      final root = await Directory.systemTemp.createTemp('butlerly-csv-test-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/transactions.csv');
      await file.writeAsString(
        'date,amount,currency,direction,description\n'
        '2026-08-09,-12.50,usd,expense,Market\n',
      );
      var imports = 0;
      String? checkedAmount;
      final importer = LocalCsvImporter.withHandler(
        (command) async {
          imports++;
          return ApplicationSuccess<TransactionDto>(_dto(command));
        },
        duplicateChecker: (command) async {
          checkedAmount = command.amount;
          return ApplicationSuccess(
            DuplicateTransactionCheckResult([_duplicateCandidate('existing')]),
          );
        },
      );

      final summary = await importer.import(
        XFile(file.path),
        sourceLanguage: 'en',
      );

      expect(checkedAmount, '12.50');
      expect(summary.imported, 0);
      expect(summary.duplicates, 1);
      expect(summary.failed, 0);
      expect(imports, 0);
    },
  );

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

  test(
    'retries an identical preview without duplicating transactions',
    () async {
      final preview = CsvStatementPreview(
        rows: [
          CsvStatementRow(
            rowNumber: 2,
            date: '2026-08-09',
            description: 'Market',
            amount: '12.50',
            currency: 'USD',
            direction: TransactionDirection.expense,
            cardReference: null,
            externalReference: 'bank-1',
            original: 'original-row',
          ),
        ],
        errors: const [],
      );
      final seen = <String>{};
      final importer = LocalCsvImporter.withHandler((command) async {
        if (!seen.add(command.id)) {
          return const ApplicationFailure<TransactionDto>(
            ApplicationFailureDetail(
              code: ApplicationFailureCode.conflict,
              operation: 'import transaction',
            ),
          );
        }
        return ApplicationSuccess<TransactionDto>(_dto(command));
      });

      final first = await importer.commitPreview(
        preview,
        sourceId: 'statement.csv',
        sourceLanguage: 'en',
      );
      final retry = await importer.commitPreview(
        preview,
        sourceId: 'statement.csv',
        sourceLanguage: 'en',
      );

      expect(first.imported, 1);
      expect(retry.imported, 0);
      expect(retry.duplicates, 1);
      expect(seen, hasLength(1));
    },
  );

  test(
    'continues after a partial row failure without duplicating successes',
    () async {
      final preview = CsvStatementPreview(
        rows: [
          CsvStatementRow(
            rowNumber: 2,
            date: '2026-08-09',
            description: 'Good',
            amount: '12.50',
            currency: 'USD',
            direction: TransactionDirection.expense,
            cardReference: null,
            externalReference: 'good-1',
            original: 'good-row',
          ),
          CsvStatementRow(
            rowNumber: 3,
            date: '2026-08-10',
            description: 'Bad',
            amount: '8.00',
            currency: 'USD',
            direction: TransactionDirection.expense,
            cardReference: null,
            externalReference: 'bad-1',
            original: 'bad-row',
          ),
        ],
        errors: const [],
      );
      final attempts = <String, int>{};
      final importer = LocalCsvImporter.withHandler((command) async {
        attempts[command.id] = (attempts[command.id] ?? 0) + 1;
        if (command.externalReference == 'bad-1') {
          return const ApplicationFailure<TransactionDto>(
            ApplicationFailureDetail(
              code: ApplicationFailureCode.unavailable,
              operation: 'import transaction',
            ),
          );
        }
        return ApplicationSuccess<TransactionDto>(_dto(command));
      });

      final summary = await importer.commitPreview(
        preview,
        sourceId: 'statement.csv',
        sourceLanguage: 'en',
      );

      expect(summary.imported, 1);
      expect(summary.failed, 1);
      expect(attempts.values, contains(1));
    },
  );

  test('duplicate-check failure blocks preview and commit safely', () async {
    final preview = CsvStatementPreview(
      rows: [
        CsvStatementRow(
          rowNumber: 2,
          date: '2026-08-09',
          description: 'Market',
          amount: '12.50',
          currency: 'USD',
          direction: TransactionDirection.expense,
          cardReference: null,
          externalReference: 'bank-1',
          original: 'original-row',
        ),
      ],
      errors: const [],
    );
    var imports = 0;
    final importer = LocalCsvImporter.withHandler(
      (command) async {
        imports++;
        return ApplicationSuccess<TransactionDto>(_dto(command));
      },
      duplicateChecker: (command) async =>
          const ApplicationFailure<DuplicateTransactionCheckResult>(
            ApplicationFailureDetail(
              code: ApplicationFailureCode.unavailable,
              operation: 'check duplicate transaction',
            ),
          ),
    );

    await expectLater(importer.findDuplicates(preview), throwsStateError);

    final summary = await importer.commitPreview(
      preview,
      sourceId: 'statement.csv',
      sourceLanguage: 'en',
    );
    expect(summary.imported, 0);
    expect(summary.failed, 1);
    expect(imports, 0);
  });

  test(
    'shared duplicate candidates require explicit confirmation before import',
    () async {
      final preview = CsvStatementPreview(
        rows: [
          CsvStatementRow(
            rowNumber: 2,
            date: '2026-08-09',
            description: 'Market',
            amount: '12.50',
            currency: 'USD',
            direction: TransactionDirection.expense,
            cardReference: null,
            externalReference: 'bank-1',
            original: 'original-row',
          ),
        ],
        errors: const [],
      );
      var imports = 0;
      final importer = LocalCsvImporter.withHandler(
        (command) async {
          imports++;
          return ApplicationSuccess<TransactionDto>(_dto(command));
        },
        duplicateChecker: (command) async => ApplicationSuccess(
          DuplicateTransactionCheckResult([
            DuplicateTransactionCandidate(
              transaction: TransactionDto(
                id: 'existing',
                amount: '12.50',
                currency: 'USD',
                direction: 'expense',
                status: 'active',
                reviewState: 'clear',
                transactionDate: '2026-08-09',
                description: 'Existing Market',
                createdAt: DateTime.utc(2026, 8, 9),
                updatedAt: DateTime.utc(2026, 8, 9),
              ),
              confidence: .75,
              matchingReasons: const [
                'transaction date matches',
                'exact amount and currency match',
                'financial direction matches',
              ],
            ),
          ]),
        ),
      );

      final duplicates = await importer.findDuplicates(preview);
      expect(duplicates.keys, contains(2));

      final blocked = await importer.commitPreview(
        preview,
        sourceId: 'statement.csv',
        sourceLanguage: 'en',
      );
      expect(blocked.imported, 0);
      expect(blocked.duplicates, 1);
      expect(imports, 0);

      final confirmationToken = LocalCsvImporter.duplicateConfirmationToken(
        preview.rows.single,
        duplicates[2]!,
      );
      final confirmed = await importer.commitPreview(
        preview,
        sourceId: 'statement.csv',
        sourceLanguage: 'en',
        confirmedDuplicateTokens: {2: confirmationToken},
      );
      expect(confirmed.imported, 1);
      expect(confirmed.duplicates, 0);
      expect(imports, 1);
    },
  );

  test(
    'changed duplicate candidates invalidate an earlier confirmation',
    () async {
      final preview = CsvStatementPreview(
        rows: [
          CsvStatementRow(
            rowNumber: 2,
            date: '2026-08-09',
            description: 'Market',
            amount: '12.50',
            currency: 'USD',
            direction: TransactionDirection.expense,
            cardReference: null,
            externalReference: 'bank-1',
            original: 'original-row',
          ),
        ],
        errors: const [],
      );
      var checks = 0;
      var imports = 0;
      final importer = LocalCsvImporter.withHandler(
        (command) async {
          imports++;
          return ApplicationSuccess<TransactionDto>(_dto(command));
        },
        duplicateChecker: (command) async {
          checks++;
          return ApplicationSuccess(
            DuplicateTransactionCheckResult([
              _duplicateCandidate(checks == 1 ? 'candidate-a' : 'candidate-b'),
            ]),
          );
        },
      );

      final initialCandidates = await importer.findDuplicates(preview);
      final confirmationToken = LocalCsvImporter.duplicateConfirmationToken(
        preview.rows.single,
        initialCandidates[2]!,
      );

      final summary = await importer.commitPreview(
        preview,
        sourceId: 'statement.csv',
        sourceLanguage: 'en',
        confirmedDuplicateTokens: {2: confirmationToken},
      );

      expect(checks, 2);
      expect(summary.imported, 0);
      expect(summary.duplicates, 1);
      expect(imports, 0);
    },
  );

  test(
    'duplicate confirmation is scoped to the selected payment source',
    () async {
      final preview = CsvStatementPreview(
        rows: [
          CsvStatementRow(
            rowNumber: 2,
            date: '2026-08-09',
            description: 'Market',
            amount: '12.50',
            currency: 'USD',
            direction: TransactionDirection.expense,
            cardReference: null,
            externalReference: 'bank-1',
            original: 'original-row',
          ),
        ],
        errors: const [],
      );
      var imports = 0;
      final importer = LocalCsvImporter.withHandler(
        (command) async {
          imports++;
          return ApplicationSuccess<TransactionDto>(_dto(command));
        },
        duplicateChecker: (command) async => ApplicationSuccess(
          DuplicateTransactionCheckResult([_duplicateCandidate('existing')]),
        ),
      );

      final candidates = await importer.findDuplicates(
        preview,
        paymentSourceId: 'source-a',
      );
      final confirmationToken = LocalCsvImporter.duplicateConfirmationToken(
        preview.rows.single,
        candidates[2]!,
        paymentSourceId: 'source-a',
      );

      final summary = await importer.commitPreview(
        preview,
        sourceId: 'statement.csv',
        sourceLanguage: 'en',
        paymentSourceId: 'source-b',
        confirmedDuplicateTokens: {2: confirmationToken},
      );

      expect(summary.imported, 0);
      expect(summary.duplicates, 1);
      expect(imports, 0);
    },
  );
}

DuplicateTransactionCandidate _duplicateCandidate(String id) =>
    DuplicateTransactionCandidate(
      transaction: TransactionDto(
        id: id,
        amount: '12.50',
        currency: 'USD',
        direction: 'expense',
        status: 'active',
        reviewState: 'clear',
        transactionDate: '2026-08-09',
        description: 'Existing Market',
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
      ),
      confidence: .75,
      matchingReasons: const [
        'transaction date matches',
        'exact amount and currency match',
        'financial direction matches',
      ],
    );

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
