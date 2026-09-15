import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly/features/foundation/presentation/receipt_capture_page.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../transactions/transaction_lifecycle_test.dart'
    show
        MemoryCategories,
        MemoryEvidence,
        MemoryMerchants,
        MemoryPaymentSources,
        MemoryTags,
        MemoryUserPreferences;

void main() {
  testWidgets('consumes injected OCR and exposes missing date for review', (
    tester,
  ) async {
    final events = <String>[];
    final transactions = _ReceiptTransactionRepository();
    final finance = _finance(transactions);
    final fixturePath = _fixturePath();
    final source = XFile(fixturePath, name: 'receipt.png');
    final preserved = _preservedReceipt;

    _resetView(tester);

    await tester.pumpWidget(
      _localizedApp(
        ReceiptCapturePage(
          finance: finance,
          evidenceStore: _evidenceStore(finance),
          pickImage: (_) async {
            events.add('picker');
            return source;
          },
          preserveEvidence: (_) async {
            events.add('preserve');
            return preserved;
          },
          fileForPreserved: (_) async {
            events.add('fileForPreserved');
            final file = File(fixturePath);
            events.add('file-exists-${file.existsSync()}');
            return file;
          },
          discardPreserved: (_) async {},
          ocrRecognizer: _FakeOcrRecognizer(events),
          loadInitialData: _emptyInitialData,
        ),
      ),
    );
    await tester.pump();
    await _captureAndAcceptReceipt(tester);

    expect(
      events,
      containsAllInOrder([
        'picker',
        'preserve',
        'fileForPreserved',
        'ocr-start',
        'ocr-complete',
      ]),
    );
    expect(find.text('Reading receipt'), findsNothing);
    expect(find.byType(TextFormField), findsWidgets);
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('12.34'), findsOneWidget);

    final saveReceipt = find.widgetWithText(
      FilledButton,
      'Save receipt transaction',
    );
    expect(saveReceipt, findsOneWidget);
    await _scrollToAndTap(tester, saveReceipt);
    await tester.pumpAndSettle();

    expect(find.text('Date needs review'), findsWidgets);
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saves recognized receipt after transaction and evidence commit', (
    tester,
  ) async {
    final transactions = _ReceiptTransactionRepository();
    final finance = _finance(transactions);
    final fixturePath = _fixturePath();
    final source = XFile(fixturePath, name: 'receipt.png');
    String? attachedTransactionId;
    bool? routeResult;

    _resetView(tester);

    await _openReceiptRoute(
      tester,
      ReceiptCapturePage(
        finance: finance,
        evidenceStore: _evidenceStore(finance),
        pickImage: (_) async => source,
        preserveEvidence: (_) async => _preservedReceipt,
        fileForPreserved: (_) async => File(fixturePath),
        discardPreserved: (_) async {},
        attachPreserved: (transactionId, _) async {
          attachedTransactionId = transactionId;
          return _receiptEvidence('evidence-success');
        },
        ocr: (_) async => ReceiptOcrResult(
          rawText: 'Test Merchant\n09/15/2026\nTOTAL 12.34 USD',
          merchant: 'Test Merchant',
          amount: '12.34',
          currency: 'USD',
          date: DateTime(2026, 9, 15),
        ),
        loadInitialData: _emptyInitialData,
      ),
      onResult: (value) => routeResult = value,
    );
    await _captureAndAcceptReceipt(tester);

    final saveReceipt = find.widgetWithText(
      FilledButton,
      'Save receipt transaction',
    );
    await _scrollToAndTap(tester, saveReceipt);
    await tester.pumpAndSettle();

    expect(routeResult, isTrue);
    expect(transactions.values, hasLength(1));
    expect(attachedTransactionId, transactions.values.keys.single);
    expect(transactions.values.values.single.transactionDate, '2026-09-15');
    expect(find.byType(ReceiptCapturePage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed evidence attach rolls new transaction back for retry', (
    tester,
  ) async {
    final transactions = _ReceiptTransactionRepository();
    final finance = _finance(transactions);
    final fixturePath = _fixturePath();
    final source = XFile(fixturePath, name: 'receipt.png');

    _resetView(tester);

    await tester.pumpWidget(
      _localizedApp(
        ReceiptCapturePage(
          finance: finance,
          evidenceStore: _evidenceStore(finance),
          pickImage: (_) async => source,
          preserveEvidence: (_) async => _preservedReceipt,
          fileForPreserved: (_) async => File(fixturePath),
          discardPreserved: (_) async {},
          attachPreserved: (_, _) async => null,
          ocr: (_) async => ReceiptOcrResult(
            rawText: 'Test Merchant\n09/15/2026\nTOTAL 12.34 USD',
            merchant: 'Test Merchant',
            amount: '12.34',
            currency: 'USD',
            date: DateTime(2026, 9, 15),
          ),
          loadInitialData: _emptyInitialData,
        ),
      ),
    );
    await tester.pump();
    await _captureAndAcceptReceipt(tester);

    final saveReceipt = find.widgetWithText(
      FilledButton,
      'Save receipt transaction',
    );
    await _scrollToAndTap(tester, saveReceipt);
    await tester.pumpAndSettle();

    expect(transactions.values, isEmpty);
    expect(find.byType(ReceiptCapturePage), findsOneWidget);
    expect(find.text('Evidence could not be stored.'), findsOneWidget);
    expect(find.text('Save receipt transaction'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'rollback failure exits saved transaction instead of allowing duplicate retry',
    (tester) async {
      final transactions = _ReceiptTransactionRepository(failDelete: true);
      final finance = _finance(transactions);
      final fixturePath = _fixturePath();
      final source = XFile(fixturePath, name: 'receipt.png');
      bool? routeResult;

      _resetView(tester);

      await _openReceiptRoute(
        tester,
        ReceiptCapturePage(
          finance: finance,
          evidenceStore: _evidenceStore(finance),
          pickImage: (_) async => source,
          preserveEvidence: (_) async => _preservedReceipt,
          fileForPreserved: (_) async => File(fixturePath),
          discardPreserved: (_) async {},
          attachPreserved: (_, _) async => null,
          ocr: (_) async => ReceiptOcrResult(
            rawText: 'Test Merchant\n09/15/2026\nTOTAL 12.34 USD',
            merchant: 'Test Merchant',
            amount: '12.34',
            currency: 'USD',
            date: DateTime(2026, 9, 15),
          ),
          loadInitialData: _emptyInitialData,
        ),
        onResult: (value) => routeResult = value,
      );
      await _captureAndAcceptReceipt(tester);

      final saveReceipt = find.widgetWithText(
        FilledButton,
        'Save receipt transaction',
      );
      await _scrollToAndTap(tester, saveReceipt);
      await tester.pumpAndSettle();

      expect(routeResult, isTrue);
      expect(transactions.values, hasLength(1));
      expect(find.byType(ReceiptCapturePage), findsNothing);
      expect(find.text('Evidence could not be stored.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

const _preservedReceipt = PreservedEvidenceSource(
  originalName: 'receipt.png',
  localFileName: 'receipt.png',
  mediaType: 'image/png',
);

String _fixturePath() =>
    '${Directory.current.path}/test/features/analysis/goldens/analysis_empty_390x844.png';

FinanceServices _finance(TransactionRepository transactions) => FinanceServices(
  transactions,
  MemoryPaymentSources(),
  MemoryMerchants(),
  MemoryCategories(),
  MemoryTags(),
  MemoryEvidence(),
  MemoryUserPreferences(),
);

LocalEvidenceStore _evidenceStore(FinanceServices finance) => LocalEvidenceStore(
  LocalDataManager(
    LocalDatabase(logger: AppLogger()),
    localEvidenceDirectory: Directory.systemTemp,
  ),
  finance,
);

Future<ReceiptCaptureInitialData> _emptyInitialData() async =>
    const ReceiptCaptureInitialData(
      preference: null,
      snapshot: TransactionMasterDataSnapshot(
        presentation: TransactionMasterData(),
        merchants: [],
        categories: [],
        tags: [],
        paymentSources: [],
      ),
    );

Widget _localizedApp(Widget home) => MaterialApp(
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: const [Locale('en')],
  home: home,
);

void _resetView(WidgetTester tester) {
  tester.view.viewInsets = FakeViewPadding.zero;
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  addTearDown(tester.view.reset);
}

Future<void> _openReceiptRoute(
  WidgetTester tester,
  ReceiptCapturePage page, {
  required ValueChanged<bool?> onResult,
}) async {
  await tester.pumpWidget(
    _localizedApp(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => page),
                );
                onResult(result);
              },
              child: const Text('Open receipt'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open receipt'));
  await tester.pumpAndSettle();
}

Future<void> _captureAndAcceptReceipt(WidgetTester tester) async {
  await tester.tap(find.text('Choose from Photos'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final useReceipt = find.widgetWithText(FilledButton, 'Use receipt');
  expect(useReceipt, findsOneWidget);
  await tester.ensureVisible(useReceipt);
  await tester.pumpAndSettle();
  await tester.tap(useReceipt);
  for (var index = 0; index < 6; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() async {
    await File(_fixturePath()).exists();
  });
  for (var index = 0; index < 3; index++) {
    await tester.pump();
  }
  expect(tester.takeException(), isNull);
}

Future<void> _scrollToAndTap(WidgetTester tester, Finder target) async {
  final scrollable = find.ancestor(
    of: target,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsWidgets);
  await tester.scrollUntilVisible(
    target,
    400,
    scrollable: scrollable.first,
  );
  await tester.pumpAndSettle();
  await tester.tap(target);
}

EvidenceItem _receiptEvidence(String id) {
  final now = DateTime.utc(2026, 9, 15, 12);
  return EvidenceItem(
    id: EvidenceId(id),
    type: EvidenceType.receiptImage,
    originalName: 'receipt.png',
    mediaType: 'image/png',
    localFileName: 'receipt.png',
    provenance: Provenance(
      id: ProvenanceId('provenance-$id'),
      sourceType: ProvenanceSourceType.scan,
      capturedAt: now,
      originalRepresentation: 'receipt.png',
    ),
    createdAt: now,
  );
}

final class _ReceiptTransactionRepository implements TransactionRepository {
  _ReceiptTransactionRepository({this.failDelete = false});

  final bool failDelete;
  final values = <String, Transaction>{};

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values.values.where((transaction) {
        if (query.status != null && transaction.status != query.status) {
          return false;
        }
        if (query.direction != null &&
            transaction.direction != query.direction) {
          return false;
        }
        if (query.currency != null &&
            transaction.money.currency.value != query.currency) {
          return false;
        }
        if (query.from != null || query.to != null) {
          final dateText = transaction.transactionDate;
          final date = dateText == null ? null : DateTime.tryParse(dateText);
          if (date == null) return false;
          if (query.from != null && date.isBefore(query.from!)) return false;
          if (query.to != null && date.isAfter(query.to!)) return false;
        }
        return true;
      }).toList();

  @override
  Future<void> removePermanently(TransactionId id) async {
    if (failDelete) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'forced rollback failure',
      );
    }
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
    values[transaction.id.value] = transaction;
  }
}

final class _FakeOcrRecognizer implements OcrRecognizer {
  _FakeOcrRecognizer(this.events);
  final List<String> events;

  @override
  Future<OcrAvailability> availability() async => OcrAvailability.available;

  @override
  Future<OcrDocument> recognize(OcrRequest request) async {
    events.add('ocr-start');
    final observations = <OcrObservation>[
      const OcrObservation(text: 'Test Merchant', confidence: .9, order: 0),
      const OcrObservation(text: 'TOTAL 12.34 USD', confidence: .9, order: 1),
    ];
    events.add('ocr-complete');
    return OcrDocument(
      pages: [OcrPage(index: 0, observations: observations)],
      diagnostics: OcrDiagnostics(
        sourceKind: OcrSourceKind.image,
        sourceOpened: true,
        pageCount: 1,
        observationCount: 2,
        recognizedLineCount: 2,
        observationsWithBounds: 0,
      ),
    );
  }
}