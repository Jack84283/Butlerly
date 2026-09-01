import 'dart:io';

import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/core/config/app_configuration.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/logging/app_logger.dart';
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
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.photo_library_outlined));
      for (var attempt = 0; attempt < 100; attempt++) {
        if ((await database.database.query(
          'financial_statements',
        )).isNotEmpty) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail('Statement capture did not complete.');
    });
    debugDefaultTargetPlatformOverride = null;

    var completed = false;
    for (var attempt = 0; attempt < 50; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      if (find.textContaining('Statement ·').evaluate().isNotEmpty) {
        completed = true;
        break;
      }
    }
    if (!completed) {
      fail('Statement capture UI did not finish reloading.');
    }
    expect(tester.takeException(), isNull);
  }

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
        await tester.tap(find.byType(Card).first);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byIcon(Icons.edit_outlined),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byIcon(Icons.edit_outlined));
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
      await tester.runAsync(() async {
        await tester.tap(find.textContaining('Statement ·').last);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(find.text(entry.$2), findsOneWidget);
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
        expect(review, hasLength(1));
        expect(review.single.reason, 'uncertain');
        expect(review.single.amount, '123.45');
        expect(
          (await database.database.query(
            'statement_rows',
          )).single['original_text'],
          rawText,
        );
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
        expect(rows.single.currency, 'USD');
        expect(rows.single.direction, 'expense');
        expect(
          rows.single.sourceContext,
          contains('statement intake default applied'),
        );
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
