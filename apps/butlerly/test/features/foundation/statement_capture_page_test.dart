import 'dart:io';

import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/evidence/platform_ocr_recognizer.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/features/foundation/presentation/statement_capture_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);
  setUpAll(() async {
    await initializeDateFormatting('en');
  });
  const channel = MethodChannel('butlerly/local_ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late Directory evidenceDirectory;
  late File original;
  late LocalDatabase database;
  late FinanceServices finance;
  const originalBytes = [0, 1, 2, 3, 4, 5, 255];

  setUp(() async {
    await services.reset();
    root = await Directory.systemTemp.createTemp('butlerly-statement-capture-');
    evidenceDirectory = Directory('${root.path}/evidence');
    original = File('${root.path}/statement.heic');
    await original.writeAsBytes(originalBytes);
    database = LocalDatabase(
      logger: AppLogger(),
      factory: databaseFactoryFfi,
      databaseDirectory: root.path,
    );
    await database.initialize();
    configureDependencies(
      configuration: const AppConfiguration(),
      database: database,
      logger: AppLogger(),
    );
    finance = services<FinanceServices>();
    await services.unregister<LocalEvidenceStore>();
    services.registerSingleton<LocalEvidenceStore>(
      LocalEvidenceStore(
        LocalDataManager(database, localEvidenceDirectory: evidenceDirectory),
        finance,
      ),
    );
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    await services.reset();
    await database.close();
    await root.delete(recursive: true);
  });

  Future<void> capture(
    WidgetTester tester, {
    Size? viewport,
    double textScale = 1,
    Locale locale = const Locale('en'),
    ThemeData? theme,
    OcrRecognizer? ocrRecognizer,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MediaQuery(
          data: MediaQueryData(
            size:
                viewport ??
                tester.view.physicalSize / tester.view.devicePixelRatio,
            textScaler: TextScaler.linear(textScale),
          ),
          child: StatementCapturePage(
            pickImage: (_) async => XFile(original.path),
            pickFile: () async => XFile(original.path),
            ocrRecognizer: ocrRecognizer,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.photo_library_outlined));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    debugDefaultTargetPlatformOverride = null;

    var completed = false;
    for (var attempt = 0; attempt < 500; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(Card).evaluate().isNotEmpty) {
        completed = true;
        break;
      }
    }
    if (!completed) {
      fail('Statement capture UI did not finish reloading.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  }

  test('statement file picker uses supported platform filters', () {
    final ios = statementFileTypeGroupForPlatform(TargetPlatform.iOS);
    final android = statementFileTypeGroupForPlatform(TargetPlatform.android);

    expect(ios.uniformTypeIdentifiers, contains('com.adobe.pdf'));
    expect(ios.uniformTypeIdentifiers, contains('public.image'));
    expect(android.extensions, isNot(contains('pdf')));
    expect(android.extensions, contains('jpg'));
  });

  testWidgets('existing statement file uses the local OCR intake path', (
    tester,
  ) async {
    const rawText = '2026-08-12 MERCHANT -123.45 USD';
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'text': rawText,
        'observations': [
          {
            'text': rawText,
            'confidence': .9,
            'left': .1,
            'top': .3,
            'width': .8,
            'height': .03,
            'pageIndex': 0,
            'order': 0,
          },
        ],
      },
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: StatementCapturePage(
          pickImage: (_) async => XFile(original.path),
          pickFile: () async => XFile(original.path),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.file_open_outlined));
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    debugDefaultTargetPlatformOverride = null;
    var completed = false;
    for (var attempt = 0; attempt < 500; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(Card).evaluate().isNotEmpty) {
        completed = true;
        break;
      }
    }
    if (!completed) {
      fail('Statement file intake UI did not finish reloading.');
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    late List<FinancialStatement> statements;
    await tester.runAsync(() async {
      statements =
          (await finance.statementServices!.list()
                  as ApplicationSuccess<List<FinancialStatement>>)
              .value;
    });
    expect(statements, hasLength(1));
    expect(statements.single.originalFilename, 'statement.heic');
    expect(tester.takeException(), isNull);
  });

  test('identical statement source is idempotent after restart', () async {
    final store = services<LocalEvidenceStore>();
    final first = await store.preserve(XFile(original.path));
    final evidence = await store.storePreservedStatement(first);
    expect(evidence, isNotNull);
    final created = await finance.statementServices!.create(
      FinancialStatement(
        id: 'statement-idempotent',
        evidenceId: evidence!.id.value,
        status: StatementStatus.needsSource,
        originalFilename: 'statement.heic',
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
      ),
      const [],
    );
    expect(created, isA<ApplicationSuccess<void>>());

    // Simulate an older installed database whose evidence provenance predates
    // source-fingerprint persistence.
    await database.database.update(
      'provenances',
      {'source_id': null},
      where: 'id = ?',
      whereArgs: [evidence.provenance.id.value],
    );

    final retry = await store.preserve(XFile(original.path));
    final found = await store.findStatementBySourceFingerprint(
      retry.sourceFingerprint!,
    );
    expect(found?.id, 'statement-idempotent');
    await store.discardPreserved(retry);

    await database.close();
    await database.initialize();
    await services.reset();
    configureDependencies(
      configuration: const AppConfiguration(),
      database: database,
      logger: AppLogger(),
    );
    finance = services<FinanceServices>();
    await services.unregister<LocalEvidenceStore>();
    services.registerSingleton<LocalEvidenceStore>(
      LocalEvidenceStore(
        LocalDataManager(database, localEvidenceDirectory: evidenceDirectory),
        finance,
      ),
    );
    final afterRestart = services<LocalEvidenceStore>();
    final retryAfterRestart = await afterRestart.preserve(XFile(original.path));
    final foundAfterRestart = await afterRestart
        .findStatementBySourceFingerprint(retryAfterRestart.sourceFingerprint!);
    expect(foundAfterRestart?.id, 'statement-idempotent');
    await afterRestart.discardPreserved(retryAfterRestart);
    expect(await database.database.query('financial_statements'), hasLength(1));
    expect(await database.database.query('evidence_items'), hasLength(1));
  });

  test(
    'recovers a statement after evidence publication before statement save',
    () async {
      final store = services<LocalEvidenceStore>();
      final createdAt = DateTime.utc(2026, 8, 9, 12);
      final preserved = await store.preserve(XFile(original.path));
      final evidence = await store.storePreservedStatement(
        preserved,
        pendingStatementId: 'statement-pending-recovery',
        pendingOriginalFilename: original.path,
        pendingCreatedAt: createdAt,
      );
      expect(evidence, isNotNull);

      await database.close();
      await services.reset();
      await database.initialize();
      configureDependencies(
        configuration: const AppConfiguration(),
        database: database,
        logger: AppLogger(),
      );
      finance = services<FinanceServices>();
      await services.unregister<LocalEvidenceStore>();
      services.registerSingleton<LocalEvidenceStore>(
        LocalEvidenceStore(
          LocalDataManager(database, localEvidenceDirectory: evidenceDirectory),
          finance,
        ),
      );

      final afterRestart = services<LocalEvidenceStore>();
      expect(await afterRestart.recoverPendingStatementCaptures(), 1);
      final statements =
          (await finance.statementServices!.list(includeArchived: true)
                  as ApplicationSuccess<List<FinancialStatement>>)
              .value;
      expect(statements, hasLength(1));
      expect(statements.single.id, 'statement-pending-recovery');
      expect(statements.single.evidenceId, evidence!.id.value);
      expect(statements.single.extractionMessage, 'statementProcessingFailed');
      final published = await afterRestart.fileFor(evidence);
      expect(published, isNotNull);
      expect(await published!.exists(), isTrue);
      expect(await afterRestart.recoverPendingStatementCaptures(), 0);
    },
  );

  test(
    'published statement evidence remains retryable after save failure',
    () async {
      final store = services<LocalEvidenceStore>();
      final createdAt = DateTime.utc(2026, 8, 9, 12);
      final source = await store.preserve(XFile(original.path));
      final evidence = await store.storePreservedStatement(
        source,
        pendingStatementId: 'statement-retryable',
        pendingOriginalFilename: original.path,
        pendingCreatedAt: createdAt,
      );
      expect(evidence, isNotNull);
      final published = await store.fileFor(evidence!);
      expect(published, isNotNull);
      expect(await published!.exists(), isTrue);

      expect(
        await store.rollbackPendingStatementCaptureForRetry(
          statementId: 'statement-retryable',
          source: source,
          evidence: evidence,
        ),
        isTrue,
      );
      expect(await published.exists(), isFalse);
      expect(
        await File(
          '${evidenceDirectory.path}.pending/${source.localFileName}',
        ).exists(),
        isTrue,
      );
      final removed = await finance.getEvidence(evidence.id.value);
      expect(removed, isA<ApplicationSuccess<EvidenceItem?>>());
      expect((removed as ApplicationSuccess<EvidenceItem?>).value, isNull);

      final retryEvidence = await store.storePreservedStatement(
        source,
        pendingStatementId: 'statement-retryable',
        pendingOriginalFilename: original.path,
        pendingCreatedAt: createdAt,
        planned: evidence,
      );
      expect(retryEvidence?.id, evidence.id);
      final created = await finance.statementServices!.create(
        FinancialStatement(
          id: 'statement-retryable',
          evidenceId: evidence.id.value,
          status: StatementStatus.needsSource,
          originalFilename: original.path,
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        const [],
      );
      expect(created, isA<ApplicationSuccess<void>>());
      expect(
        await store.completePendingStatementCapture('statement-retryable'),
        isTrue,
      );
      expect(
        await database.database.query('financial_statements'),
        hasLength(1),
      );
      expect(await database.database.query('evidence_items'), hasLength(1));
    },
  );

  testWidgets('capture failures reset busy state so capture can be retried', (
    tester,
  ) async {
    await capture(tester, ocrRecognizer: const UnsupportedOcrRecognizer());
    expect(
      find.text(
        'Statement processing failed because of a technical OCR error.',
      ),
      findsOneWidget,
    );
    expect(
      find.byIcon(Icons.photo_library_outlined),
      findsOneWidget,
      reason: 'The capture action remains available after a failed attempt.',
    );
  });

  testWidgets('persisted OCR failures can be retried', (tester) async {
    final recognizer = _RetryingOcrRecognizer();
    await capture(tester, ocrRecognizer: recognizer);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    recognizer.fail = false;
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(ButlerlyLoadingState).evaluate().isEmpty) {
        break;
      }
    }
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    late List<FinancialStatement> statements;
    await tester.runAsync(() async {
      statements =
          (await finance.statementServices!.list()
                  as ApplicationSuccess<List<FinancialStatement>>)
              .value;
    });
    expect(statements, hasLength(1));
    expect(
      statements.single.extractionMessage,
      isNot('statementProcessingFailed'),
    );
    late List<Map<String, Object?>> evidenceItems;
    await tester.runAsync(() async {
      evidenceItems = await database.database.query('evidence_items');
    });
    expect(evidenceItems, hasLength(1));
  });

  testWidgets(
    'statement review and correction remain operable at narrow 2x text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const rawText = '2026-08-12 MERCHANT -123.45 USD';
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'text': rawText,
          'observations': [
            {
              'text': rawText,
              'confidence': .9,
              'left': .1,
              'top': .3,
              'width': .8,
              'height': .03,
              'pageIndex': 0,
              'order': 0,
            },
          ],
        },
      );
      await capture(
        tester,
        viewport: const Size(320, 568),
        textScale: 2,
        locale: const Locale('zh', 'CN'),
        theme: AppTheme.darkFor(ButlerlyColorTheme.skyBlue),
      );
      await tester.runAsync(() async {
        await tester.tap(find.byType(ListTile).first);
      });
      final editButton = find.byIcon(Icons.edit_outlined);
      var reviewLoaded = false;
      for (var attempt = 0; attempt < 50; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (editButton.evaluate().isNotEmpty) {
          reviewLoaded = true;
          break;
        }
      }
      expect(reviewLoaded, isTrue, reason: 'Statement review did not load.');
      await tester.scrollUntilVisible(
        editButton,
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(editButton);
      await tester.pumpAndSettle();
      expect(find.text('更正提取的行'), findsOneWidget);
      expect(find.text('保存更正'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
      expect(find.byType(Scrollable), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('保存更正'),
        240,
        scrollable: find.byType(Scrollable).last,
      );
      final saveButton = find.ancestor(
        of: find.text('保存更正'),
        matching: find.byType(FilledButton),
      );
      expect(tester.getRect(saveButton).height, greaterThanOrEqualTo(44));
      expect(tester.getRect(saveButton).bottom, lessThanOrEqualTo(568));
      expect(tester.takeException(), isNull);
    },
  );

  for (final entry in <(String, String, String)>[
    ('', 'No readable text was found in this image.', 'noText'),
    (
      'Welcome to your statement',
      'Text was recognized, but no transaction rows could be identified.',
      'textWithoutCandidates',
    ),
    (
      'technical',
      'Statement processing failed because of a technical OCR error.',
      'technicalOcrFailure',
    ),
  ]) {
    testWidgets('capture and review distinguish ${entry.$3}', (tester) async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'recognizeText');
        final localPath = (call.arguments as Map)['path'] as String;
        expect(localPath, startsWith(evidenceDirectory.path));
        expect(await File(localPath).readAsBytes(), originalBytes);
        if (entry.$1 == 'technical') {
          throw PlatformException(
            code: 'ocr_failed',
            details: {'stage': 'visionRecognition'},
          );
        }
        return {'text': entry.$1, 'observations': <Object>[]};
      });
      await capture(tester);
      expect(find.text(entry.$2), findsOneWidget);
      final diagnostics = find.byIcon(Icons.bug_report_outlined);
      if (diagnostics.evaluate().isNotEmpty) {
        await tester.tap(diagnostics);
        await tester.pumpAndSettle();
        expect(find.textContaining('Outcome: ${entry.$3}'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.textContaining('Statement ·').last);
      var openedReview = false;
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 10));
        if (find.text('Review statement import').evaluate().isNotEmpty) {
          openedReview = true;
          break;
        }
      }
      if (!openedReview) {
        fail('Statement review did not finish opening.');
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('statement-review-content')),
          matching: find.text(entry.$2),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'unreadable description remains Needs Review after capture and batch import',
    (tester) async {
      const rawText = '2026-08-12 ??? -123.45 USD';
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'text': rawText,
          'observations': [
            {
              'text': rawText,
              'confidence': .9,
              'left': .1,
              'top': .3,
              'width': .8,
              'height': .03,
              'pageIndex': 0,
              'order': 0,
            },
          ],
        },
      );
      await capture(tester);
      await tester.runAsync(() async {
        expect(
          await finance.savePaymentSource(
            PaymentSource(
              id: PaymentSourceId('review-source'),
              name: 'Card',
              type: PaymentSourceType.card,
            ),
          ),
          isA<ApplicationSuccess<PaymentSource>>(),
        );
        final statement =
            (await finance.statementServices!.list()
                    as ApplicationSuccess<List<FinancialStatement>>)
                .value
                .single;
        final rows =
            (await finance.statementServices!.rows(statement.id)
                    as ApplicationSuccess<List<StatementRow>>)
                .value;
        expect(rows.single.description, isNull);
        final imported =
            (await finance.statementServices!.importBatch(
                      statement,
                      rows,
                      'review-source',
                    )
                    as ApplicationSuccess<StatementImportSummary>)
                .value;
        expect(imported.imported, 1);
        expect(imported.needsReview, 1);
        expect(rows.single.status, StatementRowStatus.unresolved);
        expect(rows.single.confidence, lessThanOrEqualTo(.5));
        await database.close();
        await database.initialize();
        await services.reset();
        configureDependencies(
          configuration: const AppConfiguration(),
          database: database,
          logger: AppLogger(),
        );
        finance = services<FinanceServices>();
        final review =
            (await finance.listReviewItems()
                    as ApplicationSuccess<List<ReviewItemDto>>)
                .value;
        expect(review, hasLength(2));
        expect(
          review.where(
            (item) => item.reason == ReviewIssueReason.merchantNeedsReview.name,
          ),
          hasLength(1),
        );
        expect(
          review
              .where(
                (item) =>
                    item.reason != ReviewIssueReason.merchantNeedsReview.name,
              )
              .single
              .description,
          isNull,
        );
        final persistedRow = (await database.database.query(
          'statement_rows',
        )).single;
        expect(persistedRow['original_text'], rawText);
        expect(persistedRow['status'], StatementRowStatus.saved.name);
      });
    },
  );

  testWidgets(
    'unresolved OCR and original source survive capture and SQLite reload',
    (tester) async {
      const rawText = 'PRIVATE MERCHANT 18.25';
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'text': rawText,
          'observations': [
            {
              'text': rawText,
              'confidence': .49,
              'left': .1,
              'top': .3,
              'width': .8,
              'height': .03,
              'pageIndex': 0,
              'order': 0,
            },
          ],
        },
      );
      await capture(tester);
      expect(
        find.text('Some transaction-like rows were found but need review.'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        final statements =
            (await finance.statementServices!.list()
                    as ApplicationSuccess<List<FinancialStatement>>)
                .value;
        final statement = statements.single;
        final rows =
            (await finance.statementServices!.rows(statement.id)
                    as ApplicationSuccess<List<StatementRow>>)
                .value;
        expect(rows.single.status, StatementRowStatus.unresolved);
        expect(rows.single.transactionDate, isNull);
        expect(rows.single.amount, '18.25');
        expect(rows.single.originalText, rawText);
        expect(rows.single.currency, isNull);
        expect(rows.single.direction, isNull);
        final extraction =
            (await finance.getExtractionForEvidence(statement.evidenceId)
                    as ApplicationSuccess<Extraction?>)
                .value;
        expect(extraction?.values['rawText'], rawText);
        expect(statement.rawTextReference, statement.evidenceId);
        final preserved = await evidenceDirectory
            .list()
            .where((file) => file is File)
            .cast<File>()
            .single;
        expect(await preserved.readAsBytes(), originalBytes);
        expect(await original.readAsBytes(), originalBytes);

        await database.close();
        await database.initialize();
        final persistedRows = await database.database.query('statement_rows');
        expect(persistedRows.single['original_text'], rawText);
        expect(persistedRows.single['transaction_date'], isNull);
        expect(await database.database.query('extractions'), hasLength(1));
      });
    },
  );
}

final class _RetryingOcrRecognizer implements OcrRecognizer {
  bool fail = true;

  @override
  Future<OcrAvailability> availability() async => OcrAvailability.available;

  @override
  Future<OcrDocument> recognize(OcrRequest request) async {
    if (fail) {
      throw const OcrException(
        code: OcrFailureCode.technicalFailure,
        stage: 'test',
      );
    }
    const line = '2026-08-12 MERCHANT -123.45 USD';
    return const OcrDocument(
      pages: [
        OcrPage(
          index: 0,
          observations: [OcrObservation(text: line, confidence: .9, order: 0)],
        ),
      ],
      diagnostics: OcrDiagnostics(
        sourceKind: OcrSourceKind.image,
        sourceOpened: true,
        pageCount: 1,
        observationCount: 1,
        recognizedLineCount: 1,
        observationsWithBounds: 0,
      ),
      fullText: line,
    );
  }
}
