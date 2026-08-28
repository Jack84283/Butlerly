import 'dart:io';

import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly/features/foundation/presentation/receipt_capture_page.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import '../transactions/transaction_lifecycle_test.dart' show
    MemoryCategories,
    MemoryDuplicateGroups,
    MemoryEvidence,
    MemoryMerchants,
    MemoryPaymentSources,
    MemoryTags,
    MemoryTransactionRepository,
    MemoryUserPreferences;
import 'package:butlerly/core/di/finance_services.dart';

void main() {
  testWidgets('consumes injected OCR and exposes editable receipt form', (
    tester,
  ) async {
    final events = <String>[];
    final transactions = MemoryTransactionRepository();
    final finance = FinanceServices(
      transactions,
      MemoryPaymentSources(),
      MemoryMerchants(),
      MemoryCategories(),
      MemoryTags(),
      MemoryEvidence(),
      MemoryUserPreferences(),
      duplicateGroups: MemoryDuplicateGroups(transactions),
    );
    services.registerSingleton<LocalEvidenceStore>(
      LocalEvidenceStore(
        LocalDataManager(
          LocalDatabase(logger: AppLogger()),
          localEvidenceDirectory: Directory.systemTemp,
        ),
        finance,
      ),
    );
    final fixturePath =
        '${Directory.current.path}/test/features/analysis/goldens/analysis_empty_390x844.png';
    final source = XFile(fixturePath, name: 'receipt.png');
    final preserved = const PreservedEvidenceSource(
      originalName: 'receipt.png',
      localFileName: 'receipt.png',
      mediaType: 'image/png',
    );
    var ocrStarted = false;
    var ocrCompleted = false;

    tester.view.viewInsets = FakeViewPadding.zero;
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: ReceiptCapturePage(
          finance: finance,
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
          ocr: (_) async {
            ocrStarted = true;
            events.add('ocr-start');
            final result = ReceiptOcrResult(
              merchant: 'Test Merchant',
              amount: '12.34',
              currency: 'USD',
              date: DateTime(2026, 8, 28),
              rawText: 'Test Merchant 12.34 USD',
            );
            ocrCompleted = true;
            events.add('ocr-complete');
            return result;
          },
          loadInitialData: () async => const ReceiptCaptureInitialData(
            preference: null,
            snapshot: TransactionMasterDataSnapshot(
              presentation: TransactionMasterData(),
              merchants: [],
              categories: [],
              tags: [],
              paymentSources: [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Choose from Photos'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final useReceipt = find.text('Use receipt');
    expect(useReceipt, findsOneWidget);
    await tester.ensureVisible(useReceipt);
    await tester.tap(useReceipt);
    for (var index = 0; index < 6; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      await File(fixturePath).exists();
    });
    for (var index = 0; index < 3; index++) {
      await tester.pump();
    }
    final postProcessException = tester.takeException();
    expect(postProcessException, isNull);

    expect(events, containsAllInOrder([
      'picker',
      'preserve',
      'fileForPreserved',
      'ocr-start',
      'ocr-complete',
    ]));
    expect(ocrStarted, isTrue);
    expect(ocrCompleted, isTrue);
    expect(find.text('Reading receipt'), findsNothing);
    expect(find.byType(TextFormField), findsWidgets);
    expect(find.text('12.34'), findsOneWidget);
    expect(find.text('Save receipt transaction'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
