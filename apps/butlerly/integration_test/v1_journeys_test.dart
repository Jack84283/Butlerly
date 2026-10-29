import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/session/butlerly_session_guard.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_gateway.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/core/import/local_csv_importer.dart';
import 'package:butlerly/features/budgets/presentation/budgets_page.dart';
import 'package:butlerly/features/financial_profile/presentation/financial_profile_page.dart';
import 'package:butlerly/features/foundation/presentation/first_use_preferences_page.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/features/foundation/presentation/privacy_data_page.dart';
import 'package:butlerly/features/foundation/presentation/settings_page.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart'
    as share_platform;

import 'support/v1_integration_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late V1IntegrationHarness harness;
  final integrationLock = _IntegrationTestLock();
  final auxiliaryHarnesses = <V1IntegrationHarness>[];
  late void Function() releaseIntegrationLock;

  setUp(() async {
    releaseIntegrationLock = await integrationLock.acquire();
    try {
      harness = await V1IntegrationHarness.create();
    } catch (_) {
      releaseIntegrationLock();
      rethrow;
    }
  });

  tearDown(() async {
    try {
      for (final auxiliary in auxiliaryHarnesses.reversed) {
        await auxiliary.dispose();
      }
      auxiliaryHarnesses.clear();
      await harness.dispose();
    } finally {
      releaseIntegrationLock();
    }
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

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    appRouter.go('/launch');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(ButlerlySessionConfig.launchDuration);
    await tester.pump();
    expect(appRouter.routeInformationProvider.value.uri.path, '/');
    expect(find.byType(FirstUsePreferencesPage), findsOneWidget);
    final continueButton = find.byKey(
      const ValueKey('first-use-continue-locally'),
    );
    await tester.scrollUntilVisible(
      continueButton,
      400,
      scrollable: find
          .descendant(
            of: find.byType(FirstUsePreferencesPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(continueButton);
    await tester.pump();
    final maybeLaterButton = find.byKey(
      const ValueKey('first-use-maybe-later'),
    );
    await tester.scrollUntilVisible(
      maybeLaterButton,
      400,
      scrollable: find
          .descendant(
            of: find.byType(FirstUsePreferencesPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(maybeLaterButton);
    await tester.runAsync(() async {
      for (var attempt = 0; attempt < 50; attempt++) {
        final saved = await harness.finance.loadUserPreference();
        if (saved case ApplicationSuccess<UserPreference?>(
          value: final value,
        ) when value?.firstUseCompleted == true) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(find.byType(FirstUsePreferencesPage), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
    expect(appRouter.routeInformationProvider.value.uri.path, '/');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    await harness.restart();
    final reloaded = await harness.finance.loadUserPreference();
    expect(
      (reloaded as ApplicationSuccess<UserPreference?>)
          .value
          ?.firstUseCompleted,
      isTrue,
    );
  });

  testWidgets('fresh install can enter Financial Profile from setup', (
    tester,
  ) async {
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

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    appRouter.go('/launch');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(ButlerlySessionConfig.launchDuration);
    await tester.pump();
    expect(find.byType(FirstUsePreferencesPage), findsOneWidget);

    final continueButton = find.byKey(
      const ValueKey('first-use-continue-locally'),
    );
    await tester.scrollUntilVisible(
      continueButton,
      400,
      scrollable: find
          .descendant(
            of: find.byType(FirstUsePreferencesPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(continueButton);
    await tester.pump();
    final setupButton = find.byKey(const ValueKey('first-use-set-up-profile'));
    await tester.scrollUntilVisible(
      setupButton,
      400,
      scrollable: find
          .descendant(
            of: find.byType(FirstUsePreferencesPage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(setupButton);
    await tester.pumpAndSettle();

    expect(
      appRouter.routeInformationProvider.value.uri.path,
      '/financial-profile',
    );
    expect(find.byType(FinancialProfilePage), findsOneWidget);
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
    final amountField = find.byKey(const ValueKey('transaction-amount-field'));
    final descriptionField = find.byKey(
      const ValueKey('transaction-description-field'),
    );
    expect(amountField, findsOneWidget);
    await tester.enterText(amountField, '18.75');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.fling(find.byType(ListView).last, const Offset(0, -500), 1000);
    await tester.pump(const Duration(milliseconds: 500));
    expect(descriptionField, findsOneWidget);
    await tester.enterText(descriptionField, 'UI merchant');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
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
      final ocr = await LocalOcrService(
        _FixtureOcrRecognizer(),
      ).recognize('fixture.jpg');
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
      final staleResults = await harness.database.database.query(
        'analysis_rule_results',
        where: 'freshness = ?',
        whereArgs: ['stale'],
      );
      expect(staleResults, isNotEmpty);

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
        'budgets',
        'analysis_rule_activations',
        'analysis_rule_configurations',
      ]) {
        final rows = await harness.database.database.query(table);
        expect(rows, isEmpty, reason: table);
      }
    },
  );

  testWidgets('production budget settings destination works across layouts', (
    tester,
  ) async {
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
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final budgetId = 'layout-budget-e2e';
    expect(
      await harness.finance.manageBudgets!.save(
        Budget(
          id: budgetId,
          scope: 'overall',
          scopeId: null,
          currency: 'USD',
          amount: '250.00',
        ),
      ),
      isA<ApplicationSuccess<bool>>(),
    );
    var amount = '250.00';

    for (var index = 0; index < 3; index++) {
      final size = [
        const Size(390, 844),
        const Size(900, 1100),
        const Size(1200, 800),
      ][index];
      await _pumpProductionLayoutApp(tester, size);
      expect(find.byType(SettingsPage), findsOneWidget);

      for (var attempt = 0; attempt < 12; attempt++) {
        if (find.text('Budget Settings').evaluate().isNotEmpty) break;
        final scrollable = find.byType(CustomScrollView);
        if (scrollable.evaluate().isEmpty) break;
        await tester.drag(scrollable.first, const Offset(0, -300));
        await tester.pump();
      }
      expect(find.text('Budget Settings'), findsOneWidget);
      await tester.ensureVisible(find.text('Budget Settings'));
      await tester.pump();
      await tester.tap(find.text('Budget Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(BudgetsPage), findsOneWidget);
      final currentBudget = find.textContaining('USD $amount');
      expect(currentBudget, findsOneWidget);
      await tester.tap(currentBudget);
      await tester.pumpAndSettle();
      final amountField = find.byType(TextFormField);
      expect(amountField, findsOneWidget);
      final nextAmount = '${260 + index * 10}.00';
      await tester.enterText(amountField, nextAmount);
      await tester.tap(find.text('Save').last);
      await tester.pumpAndSettle();
      final saved = await harness.finance.manageBudgets!.list();
      expect(saved, isA<ApplicationSuccess<List<Budget>>>());
      expect(
        (saved as ApplicationSuccess<List<Budget>>).value
            .singleWhere((budget) => budget.id == budgetId)
            .amount,
        nextAmount,
      );
      amount = nextAmount;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      appRouter.go('/');
    }
  });

  testWidgets(
    'production backup and restore destination works across layouts',
    (tester) async {
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
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const password = 'correct horse battery staple';
      final isMobile =
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android;
      final originalSelector = FileSelectorPlatform.instance;
      if (!isMobile) {
        addTearDown(() => FileSelectorPlatform.instance = originalSelector);
      }

      for (final size in [
        const Size(390, 844),
        const Size(900, 1100),
        const Size(1200, 800),
      ]) {
        await _pumpProductionLayoutApp(tester, size);
        expect(find.byType(SettingsPage), findsOneWidget);

        for (var attempt = 0; attempt < 12; attempt++) {
          if (find.text('Backup & Restore').evaluate().isNotEmpty) break;
          final scrollable = find.byType(CustomScrollView);
          if (scrollable.evaluate().isEmpty) break;
          await tester.drag(scrollable.first, const Offset(0, -300));
          await tester.pump();
        }
        expect(find.text('Backup & Restore'), findsOneWidget);
        await tester.ensureVisible(find.text('Backup & Restore'));
        await tester.pump();
        await tester.tap(find.text('Backup & Restore'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(PrivacyDataPage), findsOneWidget);
        if (!isMobile) {
          final destination = File(
            path.join(
              harness.root.path,
              'layout-backup-${size.width.toInt()}.butlerly',
            ),
          );
          FileSelectorPlatform.instance = _FixtureFileSelector(
            XFile(destination.path),
            savePath: destination.path,
          );
          await tester.tap(find.text('Back up Butlerly'));
          await tester.pumpAndSettle();
          final fields = find.byType(TextField);
          expect(fields, findsNWidgets(2));
          await tester.enterText(fields.at(0), password);
          await tester.enterText(fields.at(1), password);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await tester.tap(find.text('Create encrypted backup'));
          await tester.pumpAndSettle();
          expect(await destination.exists(), isTrue);
          expect(await destination.length(), greaterThan(0));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        appRouter.go('/');
      }
    },
  );

  test('master data writes survive a real application restart', () async {
    final merchant = Merchant(
      id: MerchantId('merchant.e2e'),
      name: 'Integration Market',
    );
    final category = Category(
      id: CategoryId('category.e2e'),
      name: 'Integration category',
      origin: CategoryOrigin.user,
    );
    final tag = Tag(id: TagId('tag.e2e'), name: 'Integration tag');

    expect(
      await harness.finance.saveMerchant(merchant),
      isA<ApplicationSuccess<Merchant>>(),
    );
    expect(
      await harness.finance.saveCategory(category),
      isA<ApplicationSuccess<Category>>(),
    );
    expect(await harness.finance.saveTag(tag), isA<ApplicationSuccess<Tag>>());

    await harness.restart();

    final merchantsResult = await harness.finance.listMerchants();
    final categoriesResult = await harness.finance.listCategories();
    final tagsResult = await harness.finance.listTags();
    final merchants =
        (merchantsResult as ApplicationSuccess<List<Merchant>>).value;
    final categories =
        (categoriesResult as ApplicationSuccess<List<Category>>).value;
    final tags = (tagsResult as ApplicationSuccess<List<Tag>>).value;

    expect(merchants.any((value) => value.id == merchant.id), isTrue);
    expect(categories.any((value) => value.id == category.id), isTrue);
    expect(tags.any((value) => value.id == tag.id), isTrue);
  });

  test(
    'transaction rule persists and applies through the production service graph',
    () async {
      final category = Category(
        id: CategoryId('category.rule-e2e'),
        name: 'Fuel',
        origin: CategoryOrigin.user,
      );
      expect(
        await harness.finance.saveCategory(category),
        isA<ApplicationSuccess<Category>>(),
      );

      final now = DateTime.utc(2026, 9, 27, 12);
      final rule = TransactionRule(
        id: TransactionRuleId('rule.e2e'),
        name: 'Classify integration fuel',
        descriptionContains: 'fuel',
        assignCategoryId: category.id,
        createdAt: now,
        updatedAt: now,
      );
      expect(
        await harness.finance.saveTransactionRule!(rule),
        isA<ApplicationSuccess<TransactionRule>>(),
      );
      expect(
        await harness.finance.createTransaction(
          manualCommand(
            id: 'rule-transaction-e2e',
            description: 'Fuel station',
            date: '2026-09-27',
          ),
        ),
        isA<ApplicationSuccess<TransactionDto>>(),
      );

      await harness.restart();

      final rulesResult = await harness.finance.listTransactionRules!();
      final rules =
          (rulesResult as ApplicationSuccess<List<TransactionRule>>).value;
      expect(rules.any((value) => value.id == rule.id), isTrue);

      final transactionResult = await harness.finance.getTransaction(
        'rule-transaction-e2e',
      );
      final transaction =
          (transactionResult as ApplicationSuccess<TransactionDto>).value;
      expect(transaction.categoryId, category.id.value);
    },
  );

  test(
    'payment settlement persists with amount date source and status',
    () async {
      final source = paymentSource('settlement-source-e2e', 'Settlement card');
      expect(
        await harness.finance.savePaymentSource(source),
        isA<ApplicationSuccess<PaymentSource>>(),
      );

      final saved = await harness.finance.savePaymentSettlement!(
        id: 'settlement-e2e',
        paymentSourceId: source.id.value,
        payment: money('125.50', 'USD'),
        paymentDate: '2026-09-25',
        periodStart: '2026-08-26',
        periodEnd: '2026-09-25',
        description: 'Monthly card payment',
      );
      expect(saved, isA<ApplicationSuccess<PaymentSettlementDto>>());

      await harness.restart();

      final settlementsResult = await harness.finance.listPaymentSettlements!();
      final settlements =
          (settlementsResult as ApplicationSuccess<List<PaymentSettlementDto>>)
              .value;
      final settlement = settlements.singleWhere(
        (value) => value.id == 'settlement-e2e',
      );
      expect(settlement.payment.amount, DecimalValue.parse('125.50'));
      expect(settlement.paymentDate, '2026-09-25');
      expect(settlement.paymentSourceId, source.id.value);
      expect(settlement.status, PaymentSettlementStatus.open);
    },
  );

  test(
    'statement batch confirmation persists statement row and canonical transaction',
    () async {
      final source = paymentSource('statement-source-e2e', 'Statement card');
      expect(
        await harness.finance.savePaymentSource(source),
        isA<ApplicationSuccess<PaymentSource>>(),
      );

      final evidence = EvidenceItem(
        id: EvidenceId('statement-evidence-e2e'),
        type: EvidenceType.document,
        originalName: 'statement.pdf',
        mediaType: 'application/pdf',
        provenance: Provenance(
          id: ProvenanceId('statement-evidence-provenance-e2e'),
          sourceType: ProvenanceSourceType.scan,
          capturedAt: DateTime.utc(2026, 9, 27),
          originalRepresentation: 'statement.pdf',
        ),
        createdAt: DateTime.utc(2026, 9, 27),
      );
      expect(
        await harness.finance.storeEvidence(evidence),
        isA<ApplicationSuccess<EvidenceItem>>(),
      );

      final statement = FinancialStatement(
        id: 'statement-e2e',
        evidenceId: evidence.id.value,
        paymentSourceId: source.id.value,
        status: StatementStatus.ready,
        periodStart: DateTime.utc(2026, 9, 1),
        periodEnd: DateTime.utc(2026, 9, 30),
        createdAt: DateTime.utc(2026, 9, 27),
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final row = StatementRow(
        id: 'row-e2e',
        statementId: statement.id,
        position: 0,
        originalText: '2026-09-20 INTEGRATION MARKET 42.10',
        transactionDate: DateTime.utc(2026, 9, 20),
        description: 'Integration Market',
        amount: '42.10',
        currency: 'USD',
        direction: TransactionDirection.expense.name,
        confidence: .99,
        status: StatementRowStatus.pending,
        createdAt: DateTime.utc(2026, 9, 27),
        updatedAt: DateTime.utc(2026, 9, 27),
      );

      expect(
        await harness.finance.statementServices!.create(statement, [row]),
        isA<ApplicationSuccess<void>>(),
      );
      expect(
        await harness.finance.statementServices!.importBatch(statement, [
          row,
        ], source.id.value),
        isA<ApplicationSuccess<StatementImportSummary>>(),
      );

      await harness.restart();

      final transactionsResult = await harness.finance.listTransactions(
        const ListTransactionsQuery(text: 'Integration Market'),
      );
      final transactions =
          (transactionsResult as ApplicationSuccess<List<TransactionDto>>)
              .value;
      expect(transactions, hasLength(1));

      final rowsResult = await harness.finance.statementServices!.rows(
        statement.id,
      );
      final rows = (rowsResult as ApplicationSuccess<List<StatementRow>>).value;
      expect(rows.single.status, StatementRowStatus.saved);
      expect(rows.single.transactionId, isNotNull);
    },
  );

  testWidgets(
    'statement duplicate preview remains reviewable until an explicit link',
    (tester) async {
      final source = paymentSource(
        'statement-duplicate-source-e2e',
        'Statement duplicate card',
      );
      expect(
        await harness.finance.savePaymentSource(source),
        isA<ApplicationSuccess<PaymentSource>>(),
      );
      final existing = await harness.finance.createTransaction(
        manualCommand(
          id: 'statement-existing-e2e',
          description: 'Existing statement market',
          date: '2026-09-20',
          amount: '42.10',
          paymentSourceId: source.id.value,
        ),
      );
      expect(existing, isA<ApplicationSuccess<TransactionDto>>());

      final evidence = EvidenceItem(
        id: EvidenceId('statement-duplicate-evidence-e2e'),
        type: EvidenceType.document,
        originalName: 'duplicate-statement.pdf',
        mediaType: 'application/pdf',
        provenance: Provenance(
          id: ProvenanceId('statement-duplicate-provenance-e2e'),
          sourceType: ProvenanceSourceType.scan,
          capturedAt: DateTime.utc(2026, 9, 27),
          originalRepresentation: 'duplicate-statement.pdf',
        ),
        createdAt: DateTime.utc(2026, 9, 27),
      );
      expect(
        await harness.finance.storeEvidence(evidence),
        isA<ApplicationSuccess<EvidenceItem>>(),
      );
      final statement = FinancialStatement(
        id: 'statement-duplicate-e2e',
        evidenceId: evidence.id.value,
        paymentSourceId: source.id.value,
        status: StatementStatus.ready,
        periodStart: DateTime.utc(2026, 9, 1),
        periodEnd: DateTime.utc(2026, 9, 30),
        createdAt: DateTime.utc(2026, 9, 27),
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final row = StatementRow(
        id: 'statement-duplicate-row-e2e',
        statementId: statement.id,
        position: 0,
        originalText: '2026-09-20 IMPORTED MARKET 42.10',
        transactionDate: DateTime.utc(2026, 9, 20),
        description: 'Imported Market',
        amount: '42.10',
        currency: 'USD',
        direction: TransactionDirection.expense.name,
        confidence: .99,
        status: StatementRowStatus.pending,
        createdAt: DateTime.utc(2026, 9, 27),
        updatedAt: DateTime.utc(2026, 9, 27),
      );
      final statementServices = harness.finance.statementServices!;
      expect(
        await statementServices.create(statement, [row]),
        isA<ApplicationSuccess<void>>(),
      );
      final corrected = StatementRow(
        id: row.id,
        statementId: row.statementId,
        position: row.position,
        originalText: row.originalText,
        transactionDate: row.transactionDate,
        description: 'Imported Market',
        amount: row.amount,
        currency: row.currency,
        direction: row.direction,
        confidence: row.confidence,
        sourceContext: 'Local extraction; user corrected',
        status: row.status,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt.add(const Duration(seconds: 1)),
      );
      expect(
        await statementServices.correct(corrected),
        isA<ApplicationSuccess<void>>(),
      );

      final assessment = await statementServices.assessBatch(statement, [
        corrected,
      ], source.id.value);
      expect(
        (assessment as ApplicationSuccess<StatementImportAssessment>)
            .value
            .possibleDuplicateCount,
        1,
      );
      final imported = await statementServices.importBatch(statement, [
        corrected,
      ], source.id.value);
      expect(
        (imported as ApplicationSuccess<StatementImportSummary>)
            .value
            .possibleDuplicates,
        1,
      );
      final pending =
          (await statementServices.rows(statement.id)
                  as ApplicationSuccess<List<StatementRow>>)
              .value
              .single;
      expect(pending.status, StatementRowStatus.unresolved);
      expect(pending.reviewReason, 'statementDuplicateCandidate');
      expect(
        (await harness.finance.listDuplicateCandidateGroups!()
                as ApplicationSuccess<List<DuplicateCandidateGroup>>)
            .value
            .single
            .statementRows,
        contains(
          const DuplicateCandidateStatementRow(
            statementId: 'statement-duplicate-e2e',
            rowId: 'statement-duplicate-row-e2e',
          ),
        ),
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
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appRouter.go('/review?view=duplicates');
      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pump();
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.textContaining('Imported Market').evaluate().isNotEmpty) {
          break;
        }
      }
      for (var attempt = 0; attempt < 10; attempt++) {
        if (find.textContaining('Imported Market').evaluate().isNotEmpty) {
          break;
        }
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
        await tester.pump();
      }
      expect(find.textContaining('Imported Market'), findsOneWidget);
      expect(find.text('Possible duplicate group'), findsOneWidget);
      final transactionChoice = find.byType(Radio<TransactionId>);
      expect(transactionChoice, findsOneWidget);
      await tester.tap(transactionChoice);
      await tester.pump();
      await tester.tap(find.text('Link'));
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.text('No possible duplicates found').evaluate().isNotEmpty) {
          break;
        }
      }
      expect(find.text('No possible duplicates found'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();

      final linkedRow =
          (await harness.finance.statementServices!.rows(statement.id)
                  as ApplicationSuccess<List<StatementRow>>)
              .value
              .single;
      expect(linkedRow.status, StatementRowStatus.linked);
      expect(linkedRow.transactionId, 'statement-existing-e2e');
      expect(
        (await harness.finance.listDuplicateCandidateGroups!()
                as ApplicationSuccess<List<DuplicateCandidateGroup>>)
            .value
            .where(
              (group) => group.statementRows.any(
                (value) =>
                    value.statementId == 'statement-duplicate-e2e' &&
                    value.rowId == 'statement-duplicate-row-e2e',
              ),
            )
            .isEmpty,
        isTrue,
      );
      final transactions =
          (await harness.finance.listTransactions(
                    const ListTransactionsQuery(text: 'Existing statement'),
                  )
                  as ApplicationSuccess<List<TransactionDto>>)
              .value;
      expect(transactions, hasLength(1));
    },
  );

  test(
    'encrypted portable backup restores budgets, preferences and evidence',
    () async {
      const password = 'correct horse battery staple';
      final backup = File(path.join(harness.root.path, 'workspace.butlerly'));
      final workspace = _workspaceDataService(harness);
      final preference = UserPreference(
        locale: 'en',
        formattingLocale: 'en-US',
        regionCode: 'US',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'UTC',
        firstUseCompleted: true,
      );
      expect(
        await harness.finance.saveUserPreference(preference),
        isA<ApplicationSuccess<UserPreference>>(),
      );
      expect(
        await harness.finance.manageBudgets!.save(
          const Budget(
            id: 'backup-budget-e2e',
            scope: 'overall',
            scopeId: null,
            currency: 'USD',
            amount: '250.00',
          ),
        ),
        isA<ApplicationSuccess<bool>>(),
      );
      expect(
        await harness.finance.createReceiptTransaction(
          ReceiptTransactionCommand(
            id: 'backup-receipt-e2e',
            provenanceId: 'backup-receipt-provenance-e2e',
            money: money('7.25', 'USD'),
            transactionDate: '2026-09-28',
            originalRepresentation: 'BACKUP MARKET 7.25',
            rawCounterparty: 'Backup Market',
            description: 'Backup Market',
          ),
        ),
        isA<ApplicationSuccess<TransactionDto>>(),
      );
      final evidencePath = path.join(harness.evidence.path, 'backup.txt');
      await File(evidencePath).writeAsString('private evidence bytes');
      expect(
        await harness.finance.storeAndAttachEvidence(
          EvidenceItem(
            id: EvidenceId('backup-evidence-e2e'),
            type: EvidenceType.receiptImage,
            originalName: 'backup.jpg',
            mediaType: 'image/jpeg',
            localFileName: 'backup.txt',
            provenance: Provenance(
              id: ProvenanceId('backup-evidence-provenance-e2e'),
              sourceType: ProvenanceSourceType.scan,
              capturedAt: DateTime.utc(2026, 9, 28),
              originalRepresentation: 'private evidence bytes',
            ),
            createdAt: DateTime.utc(2026, 9, 28),
          ),
          AttachmentLink(
            id: AttachmentLinkId('backup-attachment-e2e'),
            transactionId: TransactionId('backup-receipt-e2e'),
            evidenceId: EvidenceId('backup-evidence-e2e'),
            createdAt: DateTime.utc(2026, 9, 28),
          ),
        ),
        isA<ApplicationSuccess<EvidenceItem>>(),
      );

      const customTimestamp = '2026-09-28T00:00:00.000Z';
      await harness.database.database.insert('categories', {
        'id': 'user.category.backup-e2e',
        'name': 'Backup category',
        'origin': 'user',
        'parent_id': null,
        'status': 'active',
        'created_at': customTimestamp,
        'updated_at': customTimestamp,
      });
      await harness.database.database.insert('category_translations', {
        'category_id': 'user.category.backup-e2e',
        'locale': 'en',
        'label': 'Backup category label',
      });
      await harness.database.database.insert('tags', {
        'id': 'user.tag.backup-e2e',
        'name': 'Backup tag',
        'status': 'active',
        'created_at': customTimestamp,
        'updated_at': customTimestamp,
      });
      await harness.database.database.insert('tag_translations', {
        'tag_id': 'user.tag.backup-e2e',
        'locale': 'en',
        'label': 'Backup tag label',
      });
      await harness.database.database.insert('reference_data', {
        'id': 'user.reference.backup-e2e',
        'code': 'backup-reference',
        'type': 'backup-test',
        'origin': 'user',
        'status': 'active',
      });
      await harness.database.database.insert('reference_data_translations', {
        'reference_data_id': 'user.reference.backup-e2e',
        'locale': 'en',
        'label': 'Backup reference label',
      });

      await workspace.createPortableBackup(backup.path, password: password);
      expect(await workspace.isEncryptedBackup(backup.path), isTrue);
      expect(
        await harness.finance.createTransaction(
          manualCommand(
            id: 'backup-obsolete-e2e',
            description: 'Should be removed by replace restore',
            date: '2026-09-29',
          ),
        ),
        isA<ApplicationSuccess<TransactionDto>>(),
      );

      await harness.database.close();
      await services.reset();
      final restoredHarness = await V1IntegrationHarness.create();
      auxiliaryHarnesses.add(restoredHarness);
      await restoredHarness.database.database.insert('categories', {
        'id': 'user.category.stale-e2e',
        'name': 'Stale category',
        'origin': 'user',
        'parent_id': null,
        'status': 'active',
        'created_at': customTimestamp,
        'updated_at': customTimestamp,
      });
      await restoredHarness.database.database.insert('category_translations', {
        'category_id': 'user.category.stale-e2e',
        'locale': 'en',
        'label': 'Stale category label',
      });
      await restoredHarness.database.database.insert('tags', {
        'id': 'user.tag.stale-e2e',
        'name': 'Stale tag',
        'status': 'active',
        'created_at': customTimestamp,
        'updated_at': customTimestamp,
      });
      await restoredHarness.database.database.insert('tag_translations', {
        'tag_id': 'user.tag.stale-e2e',
        'locale': 'en',
        'label': 'Stale tag label',
      });
      await restoredHarness.database.database.insert('reference_data', {
        'id': 'user.reference.stale-e2e',
        'code': 'stale-reference',
        'type': 'backup-test',
        'origin': 'user',
        'status': 'active',
      });
      await restoredHarness.database.database
          .insert('reference_data_translations', {
            'reference_data_id': 'user.reference.stale-e2e',
            'locale': 'en',
            'label': 'Stale reference label',
          });
      final restoredWorkspace = _workspaceDataService(restoredHarness);
      await restoredWorkspace.restore(
        backup.path,
        mode: LocalRestoreMode.replace,
        password: password,
      );
      await restoredHarness.restart();

      final restored = await restoredHarness.finance.getTransaction(
        'backup-receipt-e2e',
      );
      expect(restored, isA<ApplicationSuccess<TransactionDto>>());
      final missing = await restoredHarness.finance.getTransaction(
        'backup-obsolete-e2e',
      );
      expect(missing, isA<ApplicationFailure<TransactionDto>>());
      final budgets =
          (await restoredHarness.finance.manageBudgets!.list()
                  as ApplicationSuccess<List<Budget>>)
              .value;
      expect(budgets.single.amount, '250.00');
      final restoredPreference =
          (await restoredHarness.finance.loadUserPreference()
                  as ApplicationSuccess<UserPreference?>)
              .value;
      expect(restoredPreference?.locale, preference.locale);
      expect(restoredPreference?.formattingLocale, preference.formattingLocale);
      expect(restoredPreference?.regionCode, preference.regionCode);
      expect(restoredPreference?.baseCurrency, preference.baseCurrency);
      expect(restoredPreference?.timeZoneId, preference.timeZoneId);
      expect(
        restoredPreference?.firstUseCompleted,
        preference.firstUseCompleted,
      );
      final restoredEvidence =
          (await restoredHarness.finance.listEvidenceForTransaction(
                    'backup-receipt-e2e',
                  )
                  as ApplicationSuccess<List<EvidenceItem>>)
              .value;
      expect(restoredEvidence.single.id.value, 'backup-evidence-e2e');
      expect(
        await File(
          path.join(restoredHarness.evidence.path, 'backup.txt'),
        ).readAsString(),
        'private evidence bytes',
      );
      expect(
        (await restoredHarness.database.database.query(
          'category_translations',
          where: 'category_id = ?',
          whereArgs: ['user.category.backup-e2e'],
        )).single['label'],
        'Backup category label',
      );
      expect(
        (await restoredHarness.database.database.query(
          'tag_translations',
          where: 'tag_id = ?',
          whereArgs: ['user.tag.backup-e2e'],
        )).single['label'],
        'Backup tag label',
      );
      expect(
        (await restoredHarness.database.database.query(
          'reference_data_translations',
          where: 'reference_data_id = ?',
          whereArgs: ['user.reference.backup-e2e'],
        )).single['label'],
        'Backup reference label',
      );
      expect(
        await restoredHarness.database.database.query(
          'categories',
          where: 'id = ?',
          whereArgs: ['user.category.stale-e2e'],
        ),
        isEmpty,
      );
      expect(
        await restoredHarness.database.database.query(
          'tags',
          where: 'id = ?',
          whereArgs: ['user.tag.stale-e2e'],
        ),
        isEmpty,
      );
      expect(
        await restoredHarness.database.database.query(
          'reference_data',
          where: 'id = ?',
          whereArgs: ['user.reference.stale-e2e'],
        ),
        isEmpty,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'production backup restore page completes an encrypted replacement',
    (tester) async {
      const password = 'correct horse battery staple';
      final backup = File(path.join(harness.root.path, 'ui-restore.butlerly'));
      final workspace = _workspaceDataService(harness);
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
      await harness.finance.createTransaction(
        manualCommand(
          id: 'ui-restore-source-e2e',
          description: 'Restored through production page',
          date: '2026-10-02',
        ),
      );
      await workspace.createPortableBackup(backup.path, password: password);
      await harness.finance.createTransaction(
        manualCommand(
          id: 'ui-restore-obsolete-e2e',
          description: 'Removed through production page',
          date: '2026-10-03',
        ),
      );

      final originalSelector = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _FixtureFileSelector(XFile(backup.path));
      addTearDown(() => FileSelectorPlatform.instance = originalSelector);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appRouter.go('/privacy-data');
      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), password);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.text('Unlock').last);
      await tester.pumpAndSettle();
      expect(find.text('Replace'), findsOneWidget);
      await tester.tap(find.text('Replace').first);
      await tester.pumpAndSettle();
      expect(find.text('Replace'), findsOneWidget);
      await tester.tap(find.text('Replace').last);
      await tester.pumpAndSettle();

      expect(
        await harness.finance.getTransaction('ui-restore-source-e2e'),
        isA<ApplicationSuccess<TransactionDto>>(),
      );
      expect(
        await harness.finance.getTransaction('ui-restore-obsolete-e2e'),
        isA<ApplicationFailure<TransactionDto>>(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
    },
  );

  testWidgets(
    'production backup page creates an encrypted backup through file selection',
    (tester) async {
      const password = 'correct horse battery staple';
      final destination = File(
        path.join(harness.root.path, 'ui-created.butlerly'),
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
      await harness.finance.createTransaction(
        manualCommand(
          id: 'ui-backup-source-e2e',
          description: 'Created through backup page',
          date: '2026-10-04',
        ),
      );

      final isMobile =
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android;
      if (isMobile) {
        final sharePlatform = _FixtureSharePlatform();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _productionPrivacyPageApp(
            shareClient: share_plus.SharePlus.custom(sharePlatform),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Back up Butlerly'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        expect(fields, findsNWidgets(2));
        await tester.enterText(fields.at(0), password);
        await tester.enterText(fields.at(1), password);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.tap(find.text('Create encrypted backup'));
        await tester.pumpAndSettle();

        expect(sharePlatform.sharedPath, isNotNull);
        expect(sharePlatform.sawFileDuringShare, isTrue);
        expect(await File(sharePlatform.sharedPath!).exists(), isFalse);
        return;
      }

      final originalSelector = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _FixtureFileSelector(
        XFile(destination.path),
        savePath: destination.path,
      );
      addTearDown(() => FileSelectorPlatform.instance = originalSelector);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appRouter.go('/privacy-data');
      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back up Butlerly'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await tester.enterText(fields.at(0), password);
      await tester.enterText(fields.at(1), password);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.text('Create encrypted backup'));
      await tester.pumpAndSettle();

      expect(await destination.exists(), isTrue);
      expect(await destination.length(), greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
    },
  );

  testWidgets(
    'production statement capture imports through file selection and review',
    (tester) async {
      final source = paymentSource('statement-ui-source-e2e', 'Statement UI');
      expect(
        await harness.finance.savePaymentSource(source),
        isA<ApplicationSuccess<PaymentSource>>(),
      );
      final statementFile = File(
        path.join(harness.root.path, 'statement-ui.png'),
      )..writeAsBytesSync([1, 2, 3]);
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
      await services.unregister<OcrRecognizer>();
      services.registerSingleton<OcrRecognizer>(
        _FixtureStatementOcrRecognizer(),
      );

      final originalSelector = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _FixtureFileSelector(
        XFile(statementFile.path),
      );
      addTearDown(() => FileSelectorPlatform.instance = originalSelector);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appRouter.go('/statements');
      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Import data').first);
      for (var attempt = 0; attempt < 100; attempt++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (find.byType(ListTile).evaluate().isNotEmpty) {
          break;
        }
      }
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(find.textContaining('Imported UI Market'), findsOneWidget);

      await tester.tap(find.text('Import data').last);
      await tester.pumpAndSettle();
      expect(find.text('Import data'), findsNWidgets(2));
      await tester.tap(find.text('Import data').last);
      await tester.pumpAndSettle();
      if (find.text('Done').evaluate().isNotEmpty) {
        await tester.tap(find.text('Done').last);
        await tester.pumpAndSettle();
      }

      final statements =
          (await harness.finance.statementServices!.list()
                  as ApplicationSuccess<List<FinancialStatement>>)
              .value;
      final rows =
          (await harness.finance.statementServices!.rows(statements.single.id)
                  as ApplicationSuccess<List<StatementRow>>)
              .value;
      expect(rows.single.status, StatementRowStatus.saved);
      expect(
        await harness.finance.listTransactions(
          const ListTransactionsQuery(text: 'Imported UI Market'),
        ),
        isA<ApplicationSuccess<List<TransactionDto>>>(),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump();
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

/// Integration tests share the process-wide service locator and router. Keep
/// each harness lifetime isolated even when the integration runner schedules
/// multiple test cases concurrently.
final class _IntegrationTestLock {
  Future<void> _tail = Future<void>.value();

  Future<void Function()> acquire() async {
    final previous = _tail;
    final gate = Completer<void>();
    _tail = gate.future;
    await previous;
    var released = false;
    return () {
      if (released) return;
      released = true;
      gate.complete();
    };
  }
}

Future<void> _pumpProductionLayoutApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  appRouter.go('/settings');
  await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Widget _productionPrivacyPageApp({share_plus.SharePlus? shareClient}) {
  return ProviderScope(
    child: MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: PrivacyDataPage(shareClient: shareClient),
    ),
  );
}

final class _FixtureFileSelector extends FileSelectorPlatform {
  _FixtureFileSelector(this.file, {this.savePath});

  final XFile file;
  final String? savePath;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => file;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => savePath == null ? null : FileSaveLocation(savePath!);
}

final class _FixtureSharePlatform extends share_platform.SharePlatform {
  String? sharedPath;
  bool sawFileDuringShare = false;

  @override
  Future<share_plus.ShareResult> share(share_plus.ShareParams params) async {
    final file = params.files!.single;
    sharedPath = file.path;
    sawFileDuringShare = await File(file.path).exists();
    return const share_plus.ShareResult(
      'shared',
      share_plus.ShareResultStatus.success,
    );
  }
}

final class _FixtureStatementOcrRecognizer implements OcrRecognizer {
  @override
  Future<OcrAvailability> availability() async => OcrAvailability.available;

  @override
  Future<OcrDocument> recognize(OcrRequest request) async => OcrDocument(
    pages: const [
      OcrPage(
        index: 0,
        observations: [
          OcrObservation(
            text: 'Statement period: 2026-09-01 - 2026-09-30',
            confidence: .99,
            left: .05,
            top: .05,
            width: .8,
            height: .03,
            order: 0,
          ),
          OcrObservation(
            text: 'CARD ****1234',
            confidence: .99,
            left: .05,
            top: .12,
            width: .3,
            height: .03,
            order: 1,
          ),
          OcrObservation(
            text: '09/20',
            confidence: .99,
            left: .05,
            top: .25,
            width: .1,
            height: .03,
            order: 2,
          ),
          OcrObservation(
            text: 'Imported UI Market',
            confidence: .99,
            left: .2,
            top: .25,
            width: .35,
            height: .03,
            order: 3,
          ),
          OcrObservation(
            text: '-42.10 USD',
            confidence: .99,
            left: .7,
            top: .25,
            width: .2,
            height: .03,
            order: 4,
          ),
        ],
      ),
    ],
    diagnostics: const OcrDiagnostics(
      sourceKind: OcrSourceKind.image,
      sourceOpened: true,
      pageCount: 1,
      observationCount: 5,
      recognizedLineCount: 5,
      observationsWithBounds: 5,
      visionObservationsRecognized: 5,
    ),
    fullText:
        'Statement period: 2026-09-01 - 2026-09-30\n'
        'CARD ****1234\n'
        '09/20 Imported UI Market -42.10 USD',
  );
}

final class _FixtureOcrRecognizer implements OcrRecognizer {
  @override
  Future<OcrAvailability> availability() async => OcrAvailability.available;

  @override
  Future<OcrDocument> recognize(OcrRequest request) async => OcrDocument(
    pages: const [
      OcrPage(
        index: 0,
        observations: [
          OcrObservation(
            text: 'MARKET',
            confidence: .99,
            left: .1,
            top: .1,
            width: .5,
            height: .1,
            order: 0,
          ),
          OcrObservation(
            text: 'TOTAL 12.34',
            confidence: .98,
            left: .1,
            top: .3,
            width: .5,
            height: .1,
            order: 1,
          ),
        ],
      ),
    ],
    diagnostics: const OcrDiagnostics(
      sourceKind: OcrSourceKind.image,
      sourceOpened: true,
      pageCount: 1,
      observationCount: 2,
      recognizedLineCount: 2,
      observationsWithBounds: 2,
      visionObservationsRecognized: 2,
    ),
    fullText: 'MARKET\nTOTAL 12.34',
  );
}

WorkspaceDataService _workspaceDataService(V1IntegrationHarness harness) {
  return WorkspaceDataService(
    LocalWorkspaceDataGateway(
      LocalBackupManager(harness.database, harness.data),
      harness.data,
    ),
    refreshSystemData: () async {
      await harness.database.reseedSystemData();
      await harness.installBuiltInRules();
    },
  );
}
