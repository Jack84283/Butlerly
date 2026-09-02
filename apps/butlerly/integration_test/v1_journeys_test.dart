import 'dart:convert';
import 'dart:io';

import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/core/import/local_csv_importer.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;

import 'support/v1_integration_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late V1IntegrationHarness harness;

  setUp(() async {
    harness = await V1IntegrationHarness.create();
  });

  tearDown(() async {
    await harness.dispose();
  });

  testWidgets('fresh install preferences become usable and persist', (
    tester,
  ) async {
    final preference = await harness.finance.loadUserPreference();
    expect(preference, isA<ApplicationSuccess<UserPreference?>>());
    expect((preference as ApplicationSuccess<UserPreference?>).value, isNull);
    await harness.finance.saveUserPreference(
      UserPreference(
        locale: 'en',
        formattingLocale: 'en-US',
        regionCode: 'US',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'UTC',
        firstUseCompleted: false,
      ),
    );

    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();
    expect(find.text('Set up your local workspace'), findsOneWidget);
    await tester.tap(find.text('Continue locally'));
    await tester.pumpAndSettle();

    await harness.restart();
    final reloaded = await harness.finance.loadUserPreference();
    expect(
      (reloaded as ApplicationSuccess<UserPreference?>)
          .value
          ?.firstUseCompleted,
      isTrue,
    );
  });

  testWidgets('real UI creates and saves a local transaction', (tester) async {
    await harness.finance.saveUserPreference(
      UserPreference(
        locale: 'en',
        formattingLocale: 'en-US',
        regionCode: 'US',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'UTC',
        firstUseCompleted: true,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: TransactionEditorPage(finance: harness.finance)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsAtLeastNWidgets(4));
    await tester.enterText(find.byType(TextFormField).at(0), '18.75');
    await tester.enterText(find.byType(TextFormField).at(2), 'UI merchant');
    await tester.fling(find.byType(ListView).last, const Offset(0, -500), 1000);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Save locally'), findsOneWidget);
    await tester.tap(find.text('Save locally'));
    await tester.pump(const Duration(milliseconds: 500));

    final saved = await harness.finance.listTransactions(
      const ListTransactionsQuery(text: 'UI merchant'),
    );
    expect(
      (saved as ApplicationSuccess<List<TransactionDto>>).value,
      hasLength(1),
    );
  });

  test(
    'payment source and transaction survive an application restart',
    () async {
      final source = paymentSource('source-e2e', 'Everyday card');
      expect(
        await harness.finance.savePaymentSource(source),
        isA<ApplicationSuccess>(),
      );
      expect(
        await harness.finance.createTransaction(
          manualCommand(
            id: 'transaction-e2e',
            description: 'Restart merchant',
            date: '2026-08-20',
            paymentSourceId: source.id.value,
          ),
        ),
        isA<ApplicationSuccess<TransactionDto>>(),
      );

      await harness.restart();
      final transactions = await harness.finance.listTransactions(
        const ListTransactionsQuery(text: 'Restart merchant'),
      );
      expect(
        (transactions as ApplicationSuccess<List<TransactionDto>>)
            .value
            .single
            .id,
        'transaction-e2e',
      );
      final sources = await harness.finance.listPaymentSources();
      expect(
        (sources as ApplicationSuccess<List<PaymentSource>>).value.single.name,
        'Everyday card',
      );
    },
  );

  test(
    'CSV preview, malformed row, duplicate handling and commit persist',
    () async {
      final importer = LocalCsvImporter(harness.finance);
      final file = XFile.fromData(
        utf8.encode(
          'date,description,amount,currency,direction\n'
          '2026-08-20,Coffee,4.50,USD,expense\n'
          'bad-date,Broken,not-money,USD,expense\n',
        ),
        name: 'fixture.csv',
        mimeType: 'text/csv',
      );
      final preview = await importer.preview(file);
      expect(preview.rows, hasLength(2));
      expect(preview.validCount, 1);
      expect(preview.errors, hasLength(1));

      final first = await importer.commitPreview(
        preview,
        sourceId: 'fixture.csv',
        sourceLanguage: 'en',
      );
      expect(first.imported, 1);
      // Preview validation owns malformed-row errors; commit only attempts
      // valid rows and therefore reports no additional storage failures.
      expect(first.failed, 0);
      final duplicate = await importer.commitPreview(
        preview,
        sourceId: 'fixture.csv',
        sourceLanguage: 'en',
      );
      expect(duplicate.imported, 0);
      expect(duplicate.duplicates, 1);

      await harness.restart();
      final rows = await harness.finance.listTransactions(
        const ListTransactionsQuery(text: 'Coffee'),
      );
      expect(
        (rows as ApplicationSuccess<List<TransactionDto>>).value,
        hasLength(1),
      );
    },
  );

  test(
    'receipt OCR contract, evidence attachment and reconciliation persist',
    () async {
      const channel = MethodChannel('butlerly/local_ocr');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'recognizeText');
            return {
              'text': 'MARKET\nTOTAL 12.34',
              'observations': [
                {
                  'text': 'MARKET',
                  'confidence': .99,
                  'left': 0.1,
                  'top': 0.1,
                  'width': .5,
                  'height': .1,
                  'pageIndex': 0,
                  'order': 0,
                },
                {
                  'text': 'TOTAL 12.34',
                  'confidence': .98,
                  'left': 0.1,
                  'top': 0.3,
                  'width': .5,
                  'height': .1,
                  'pageIndex': 0,
                  'order': 1,
                },
              ],
              'diagnostics': {
                'sourceKind': 'image',
                'sourceOpened': true,
                'pageCount': 1,
                'observationCount': 2,
                'visionObservationCount': 2,
                'recognizedLineCount': 2,
                'observationsWithBounds': 2,
              },
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final ocr = await const LocalOcrService().recognize('fixture.jpg');
      expect(ocr.amount, '12.34');
      expect(ocr.merchant, 'MARKET');
      final receipt = await harness.finance.createReceiptTransaction(
        ReceiptTransactionCommand(
          id: 'receipt-e2e',
          provenanceId: 'receipt-e2e-provenance',
          money: money('12.34', 'USD'),
          transactionDate: '2026-08-20',
          originalRepresentation: ocr.rawText,
          rawCounterparty: ocr.merchant,
          description: ocr.merchant,
        ),
      );
      expect(receipt, isA<ApplicationSuccess<TransactionDto>>());

      final evidencePath = path.join(harness.evidence.path, 'receipt.txt');
      await File(evidencePath).writeAsString(ocr.rawText);
      final evidence = EvidenceItem(
        id: EvidenceId('evidence-e2e'),
        type: EvidenceType.receiptImage,
        originalName: 'receipt.jpg',
        mediaType: 'image/jpeg',
        localFileName: 'receipt.txt',
        provenance: Provenance(
          id: ProvenanceId('evidence-e2e-provenance'),
          sourceType: ProvenanceSourceType.scan,
          capturedAt: DateTime.utc(2026, 8, 20),
          originalRepresentation: ocr.rawText,
        ),
        createdAt: DateTime.utc(2026, 8, 20),
      );
      final attached = await harness.finance.storeAndAttachEvidence(
        evidence,
        AttachmentLink(
          id: AttachmentLinkId('attachment-e2e'),
          transactionId: TransactionId('receipt-e2e'),
          evidenceId: evidence.id,
          createdAt: DateTime.utc(2026, 8, 20),
        ),
      );
      expect(attached, isA<ApplicationSuccess<EvidenceItem>>());

      await harness.finance.createPaymentTransaction(
        PaymentTransactionCommand(
          id: 'payment-e2e',
          provenanceId: 'payment-e2e-provenance',
          money: money('12.34', 'USD'),
          direction: TransactionDirection.expense,
          transactionDate: '2026-08-20',
          originalRepresentation: 'bank fixture',
          sourceId: 'statement-fixture',
          description: 'MARKET',
          sourceType: TransactionSourceType.import,
          provenanceSourceType: ProvenanceSourceType.import,
        ),
      );
      expect(
        await harness.finance.refreshReconciliationCandidates(),
        isA<ApplicationSuccess>(),
      );
      final candidates = await harness.finance.listReconciliationCandidates();
      final candidate =
          (candidates as ApplicationSuccess<List<ReconciliationCandidate>>)
              .value
              .single;
      expect(
        await harness.finance.confirmReconciliation(candidate),
        isA<ApplicationSuccess>(),
      );

      await harness.restart();
      final links = await harness.finance.listReconciliationLinks();
      expect(
        (links as ApplicationSuccess<List<ReconciliationLink>>).value,
        hasLength(1),
      );
      final storedEvidence = await harness.finance.listEvidenceForTransaction(
        'receipt-e2e',
      );
      expect(
        (storedEvidence as ApplicationSuccess<List<EvidenceItem>>).value,
        hasLength(1),
      );
    },
  );

  test(
    'search edit, analysis invalidation, export and erase survive real boundaries',
    () async {
      await harness.finance.createTransaction(
        manualCommand(
          id: 'analysis-e2e',
          description: 'Before edit',
          date: '2026-08-20',
          amount: '20.00',
        ),
      );
      final found = await harness.finance.listTransactions(
        const ListTransactionsQuery(text: 'Before edit'),
      );
      final transaction =
          (found as ApplicationSuccess<List<TransactionDto>>).value.single;
      expect(
        await harness.finance.updateTransaction(
          UpdateTransactionCommand(
            id: transaction.id,
            timing: transaction.occurredAt == null
                ? const UnknownTransactionTime(
                    UnknownTransactionTimeReason.unknown,
                  )
                : KnownTransactionTime(transaction.occurredAt!),
            money: money(transaction.amount, transaction.currency),
            direction: TransactionDirection.values.byName(
              transaction.direction,
            ),
            transactionDate: transaction.transactionDate,
            description: 'After edit',
            rawCounterparty: 'After edit',
          ),
        ),
        isA<ApplicationSuccess<TransactionDto>>(),
      );

      await harness.finance.saveUserPreference(
        UserPreference(
          locale: 'en',
          formattingLocale: 'en-US',
          regionCode: 'US',
          baseCurrency: CurrencyCode('USD'),
          timeZoneId: 'UTC',
          firstUseCompleted: true,
        ),
      );
      await harness.installBuiltInRules();
      final calculation = await harness.finance.calculateAnalysisOverview!
          .currentMonth(DateTime.utc(2026, 8, 21));
      expect(calculation, isA<ApplicationSuccess<List<RuleExecutionResult>>>());
      await harness.finance.createTransaction(
        manualCommand(
          id: 'analysis-e2e-2',
          description: 'After analysis',
          date: '2026-08-20',
          amount: '30.00',
        ),
      );
      expect(
        await harness.finance.invalidateAnalysis!.call(
          AnalysisInvalidationReason.transactionCreated,
          DateTime.utc(2026, 8, 21),
        ),
        isA<ApplicationSuccess>(),
      );

      await harness.restart();
      final recalculated = await harness.finance.calculateAnalysisOverview!
          .currentMonth(DateTime.utc(2026, 8, 21));
      expect(
        recalculated,
        isA<ApplicationSuccess<List<RuleExecutionResult>>>(),
      );

      await File(
        path.join(harness.evidence.path, 'analysis.txt'),
      ).writeAsString('derived evidence fixture');
      final exported = await harness.data.exportAll();
      final json =
          jsonDecode(
                await File(
                  path.join(exported.directory.path, 'butlerly-export.json'),
                ).readAsString(),
              )
              as Map<String, Object?>;
      final tables = json['tables']! as Map<String, Object?>;
      expect(tables['transactions'], isNotEmpty);
      expect(tables['provenances'], isNotEmpty);
      expect(
        File(
          path.join(exported.directory.path, 'evidence', 'analysis.txt'),
        ).existsSync(),
        isTrue,
      );

      await harness.data.eraseAll();
      await harness.restart();
      for (final table in const [
        'transactions',
        'provenances',
        'evidence_items',
        'attachment_links',
        'analysis_findings',
        'analysis_rule_results',
        'user_preferences',
      ]) {
        final rows = await harness.database.database.query(table);
        expect(rows, isEmpty, reason: table);
      }
    },
  );

  test(
    'unsupported native OCR is an explicit recoverable platform failure',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('butlerly/local_ocr'),
            (_) async => throw MissingPluginException(),
          );
      expect(
        () => const LocalOcrService().recognize('unavailable.jpg'),
        throwsA(
          isA<LocalOcrException>().having(
            (error) => error.code,
            'code',
            'native_ocr_unavailable',
          ),
        ),
      );
    },
  );
}
