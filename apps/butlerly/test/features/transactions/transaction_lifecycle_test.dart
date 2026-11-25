import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/core/audio/butlerly_sound_feedback.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_compact_section_selector.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_panel_footer.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_transaction_table.dart';
import 'package:butlerly/design_system/components/butlerly_issuer_autocomplete.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/add_page.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/features/foundation/presentation/master_data_page.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/features/foundation/presentation/review_page.dart';
import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_count_label.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_row.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/features/tools/presentation/payment_settlements_page.dart';
import 'package:butlerly/features/tools/presentation/tools_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en'));
  late MemoryTransactionRepository repository;
  late MemoryEvidence evidenceRepository;
  late MemoryDuplicateGroups duplicateGroups;
  late MemoryStatements statementRepository;
  late MemoryPaymentSources paymentSources;
  late MemoryMerchants merchants;
  late MemoryCategories categories;
  late MemoryTags tags;
  late MemoryMerchantAliases merchantAliases;
  late MemoryMerchantPatterns merchantPatterns;
  late MemoryMerchantMatchingConfiguration merchantMatchingConfiguration;
  late MemoryPaymentSettlements paymentSettlements;

  setUp(() async {
    await services.reset();
    repository = MemoryTransactionRepository();
    evidenceRepository = MemoryEvidence();
    duplicateGroups = MemoryDuplicateGroups(repository);
    statementRepository = MemoryStatements(repository);
    paymentSources = MemoryPaymentSources();
    merchants = MemoryMerchants();
    categories = MemoryCategories();
    tags = MemoryTags();
    merchantAliases = MemoryMerchantAliases();
    merchantPatterns = MemoryMerchantPatterns();
    merchantMatchingConfiguration = MemoryMerchantMatchingConfiguration(
      merchants,
      merchantAliases,
      merchantPatterns,
    );
    paymentSettlements = MemoryPaymentSettlements()
      ..transactionRepository = repository;
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        repository,
        paymentSources,
        merchants,
        categories,
        tags,
        evidenceRepository,
        MemoryUserPreferences(),
        duplicateGroups: duplicateGroups,
        statements: statementRepository,
        merchantAliases: merchantAliases,
        merchantNormalizationPatterns: merchantPatterns,
        merchantMatchingConfiguration: merchantMatchingConfiguration,
        paymentSettlements: paymentSettlements,
      ),
    );
  });

  tearDown(() => services.reset());

  for (final enabled in [false, true]) {
    for (final updating in [false, true]) {
      testWidgets(
        'transaction ${updating ? 'update' : 'create'} feedback enabled=$enabled',
        (tester) async {
          final finance = services<FinanceServices>();
          await finance.saveUserPreference(
            UserPreference(
              locale: 'en',
              formattingLocale: 'en-US',
              regionCode: 'US',
              baseCurrency: CurrencyCode('USD'),
              timeZoneId: 'UTC',
              transactionSaveSoundEnabled: enabled,
              firstUseCompleted: true,
            ),
          );
          TransactionDto? existing;
          if (updating) {
            final created = await finance.createTransaction(
              CreateTransactionCommand(
                id: 'feedback-original',
                provenanceId: 'feedback-original-provenance',
                timing: KnownTransactionTime(DateTime.utc(2026, 11, 6, 12)),
                money: Money(
                  amount: DecimalValue.parse('20.00'),
                  currency: CurrencyCode('USD'),
                ),
                direction: TransactionDirection.expense,
                description: 'Original',
              ),
            );
            expect(created, isA<ApplicationSuccess<TransactionDto>>());
            existing = (created as ApplicationSuccess<TransactionDto>).value;
          }
          final playedAssets = <String>[];
          ButlerlySoundFeedback.playbackForTesting = (assetPath) async {
            playedAssets.add(assetPath);
          };
          addTearDown(() => ButlerlySoundFeedback.playbackForTesting = null);
          // Ensure the preference is loaded before the editor reads it.
          final container = ProviderContainer();
          addTearDown(container.dispose);
          await container.read(userPreferenceProvider.future);
          var completed = false;
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                home: Scaffold(
                  body: TransactionEditorPage(
                    finance: finance,
                    existing: existing,
                    onComplete: (result) =>
                        completed = result is TransactionEditorSaved,
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (!updating) {
            await tester.enterText(
              find.byKey(const ValueKey('transaction-amount-field')),
              '17.00',
            );
          }
          await _scrollEditorToSave(tester);
          await tester.tap(
            find.byKey(const ValueKey('transaction-save-locally')),
          );
          await tester.pumpAndSettle();
          expect(completed, isTrue);
          expect(
            playedAssets,
            enabled
                ? <String>[
                    updating
                        ? ButlerlySoundFeedback.updatedSoundAssetPath
                        : ButlerlySoundFeedback.createdSoundAssetPath,
                  ]
                : <String>[],
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('Wide Transactions opens the existing detail in a side panel', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final finance = services<FinanceServices>();
    final created = await finance.createTransaction(
      CreateTransactionCommand(
        id: 'panel-transaction',
        provenanceId: 'panel-transaction-source',
        timing: KnownTransactionTime(DateTime.utc(2026, 10, 14, 12)),
        money: Money(
          amount: DecimalValue.parse('19.75'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        transactionDate: '2026-10-14',
        description: 'Panel coffee',
      ),
    );
    expect(created, isA<ApplicationSuccess<TransactionDto>>());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionsPage(
            query: const ListTransactionsQuery(
              transactionIds: ['panel-transaction'],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(
      const ValueKey('desktop-transaction-row-panel-transaction'),
    );
    expect(row, findsOneWidget);
    expect(find.byType(ButlerlyDesktopTransactionSection), findsOneWidget);
    expect(find.byType(ButlerlyDesktopInnerCard), findsOneWidget);
    final transactionsCard = tester.getRect(
      find.byType(ButlerlyDesktopInnerCard),
    );
    final transactionsDateHeader = tester.getRect(find.text('Date'));
    expect(
      transactionsDateHeader.left - transactionsCard.left,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      transactionsDateHeader.top - transactionsCard.top,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      find.byKey(const ValueKey('desktop-transaction-detail-panel')),
      findsNothing,
    );

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-transaction-detail-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-detail-summary-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-detail-edit-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-detail-delete-button')),
      findsOneWidget,
    );
    expect(find.byType(ButlerlyDesktopPanelFooter), findsOneWidget);
    expect(row, findsOneWidget);

    // Edit keeps the same panel and leaves the transactions table mounted.
    await tester.tap(
      find.byKey(const ValueKey('transaction-detail-edit-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-transaction-detail-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-editor-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-save-locally')),
      findsOneWidget,
    );
    expect(find.byType(ButlerlyDesktopPanelFooter), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transaction-detail-summary-card')),
      findsNothing,
    );
    expect(row, findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('transaction-editor-cancel-panel')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transaction-detail-summary-card')),
      findsOneWidget,
    );

    // Saving returns to the current detail in place with updated values.
    await tester.tap(
      find.byKey(const ValueKey('transaction-detail-edit-button')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-description-field')),
      'Panel coffee edited',
    );
    await tester.tap(find.byKey(const ValueKey('transaction-save-locally')));
    await tester.pumpAndSettle();
    expect(find.text('Panel coffee edited'), findsWidgets);
    expect(
      find.byKey(const ValueKey('desktop-transaction-detail-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-detail-summary-card')),
      findsOneWidget,
    );
    expect(row, findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('transaction-detail-close-panel')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-transaction-detail-panel')),
      findsNothing,
    );
    expect(row, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Landscape 950px Search matches desktop Home layout mode and table',
    (tester) async {
      // Home and the desktop shell already treat a tablet landscape viewport
      // below the 1024px width breakpoint as wide. Search must do the same.
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(950, 700);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final finance = services<FinanceServices>();
      final created = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'landscape-desktop-search',
          provenanceId: 'landscape-desktop-search-source',
          timing: KnownTransactionTime(DateTime.utc(2026, 10, 12, 12)),
          money: Money(
            amount: DecimalValue.parse('8.25'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          transactionDate: '2026-10-12',
          description: 'Landscape tablet search',
        ),
      );
      expect(created, isA<ApplicationSuccess<TransactionDto>>());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchPage(
              initialQuery: const ListTransactionsQuery(
                transactionIds: ['landscape-desktop-search'],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ButlerlyDesktopTransactionTableCard), findsOneWidget);
      expect(find.byType(ButlerlyDesktopTransactionTable), findsOneWidget);
      expect(find.byType(ButlerlyDesktopInnerCard), findsOneWidget);
      expect(find.byType(TransactionRow), findsNothing);
      final compactWideCard = tester.getRect(
        find.byType(ButlerlyDesktopInnerCard),
      );
      final compactWideDateHeader = tester.getRect(find.text('Date'));
      expect(
        compactWideDateHeader.left - compactWideCard.left,
        closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
      );
      expect(
        compactWideDateHeader.top - compactWideCard.top,
        closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
      );
      expect(
        tester.widget<ButlerlyPage>(find.byType(ButlerlyPage)).fullWidth,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Wide Search retains results when its detail panel closes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 1100);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final finance = services<FinanceServices>();
    final created = await finance.createTransaction(
      CreateTransactionCommand(
        id: 'search-panel-transaction',
        provenanceId: 'search-panel-source',
        timing: KnownTransactionTime(DateTime.utc(2026, 10, 12, 12)),
        money: Money(
          amount: DecimalValue.parse('6.25'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        transactionDate: '2026-10-12',
        description: 'Search panel coffee',
      ),
    );
    expect(created, isA<ApplicationSuccess<TransactionDto>>());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPage(
            initialQuery: const ListTransactionsQuery(
              transactionIds: ['search-panel-transaction'],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Search panel coffee'), findsOneWidget);
    expect(find.byType(ButlerlyDesktopInnerCard), findsOneWidget);
    expect(find.byType(ButlerlyDesktopTransactionTable), findsOneWidget);
    expect(find.byType(ButlerlyDesktopTransactionTableCard), findsOneWidget);
    expect(find.byType(TransactionRow), findsNothing);
    expect(find.text('Merchant'), findsOneWidget);
    final cardBounds = tester.getRect(find.byType(ButlerlyDesktopInnerCard));
    final tableBounds = tester.getRect(
      find.byKey(const ValueKey('desktop-transactions-table')),
    );
    expect(
      tableBounds.left - cardBounds.left,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      cardBounds.right - tableBounds.right,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      tableBounds.top - cardBounds.top,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      cardBounds.bottom - tableBounds.bottom,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    final searchDateHeader = tester.getRect(find.text('Date'));
    expect(
      searchDateHeader.left - cardBounds.left,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      searchDateHeader.top - cardBounds.top,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      find.byKey(const ValueKey('desktop-transaction-detail-panel')),
      findsNothing,
    );

    await tester.tap(find.text('Search panel coffee'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-transaction-detail-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-detail-amount-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('search-pinned-controls')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('transaction-detail-edit-button')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-transaction-detail-panel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-editor-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('search-pinned-controls')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('transaction-editor-cancel-panel')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transaction-detail-amount-card')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('transaction-detail-close-panel')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-transaction-detail-panel')),
      findsNothing,
    );
    expect(find.text('Search panel coffee'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'row detail and edit preserve transaction master-data references',
    (tester) async {
      final finance = services<FinanceServices>();
      merchants.values['merchant-cafe'] = Merchant(
        id: MerchantId('merchant-cafe'),
        name: 'Corner Cafe',
      );
      categories.values['category-food'] = Category(
        id: CategoryId('category-food'),
        name: 'Food',
        origin: CategoryOrigin.user,
      );
      categories.values['subcategory-dining'] = Category(
        id: CategoryId('subcategory-dining'),
        name: 'Dining',
        origin: CategoryOrigin.user,
        parentId: CategoryId('category-food'),
      );
      paymentSources.values['source-visa'] = PaymentSource(
        id: PaymentSourceId('source-visa'),
        name: 'Visa',
        type: PaymentSourceType.card,
      );
      final created = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'master-data-consistency',
          provenanceId: 'master-data-consistency-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 9, 20, 12)),
          money: Money(
            amount: DecimalValue.parse('24.50'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          transactionDate: '2026-09-20',
          description: 'Lunch',
          merchantId: 'merchant-cafe',
          categoryId: 'category-food',
          subcategoryId: 'subcategory-dining',
          paymentSourceId: 'source-visa',
        ),
      );
      final transaction = (created as ApplicationSuccess<TransactionDto>).value;

      await tester.pumpWidget(const MaterialApp(home: TransactionsPage()));
      await tester.pumpAndSettle();

      expect(find.text('Corner Cafe'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Dining'), findsOneWidget);
      expect(find.text('Visa'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transaction-row-payment-source')),
        findsOneWidget,
      );

      await tester.tap(find.text('Corner Cafe'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('transaction-detail-summary-card')),
        findsOneWidget,
      );
      expect(find.text('Corner Cafe'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Dining'), findsOneWidget);
      expect(find.text('Visa'), findsOneWidget);

      await _tapTransactionDetailEdit(tester);
      final editorScrollable = _transactionEditorScrollable(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('transaction-editor-description-card')),
        160,
        scrollable: editorScrollable,
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-description-field')),
        'Updated lunch',
      );
      await _scrollEditorToSave(tester);
      await tester.tap(find.text('Save locally'));
      await tester.pumpAndSettle();
      await _scrollTransactionDetailToTop(tester);

      final refreshed = await finance.getTransaction(transaction.id);
      final saved = (refreshed as ApplicationSuccess<TransactionDto>).value;
      expect(saved.merchantId, 'merchant-cafe');
      expect(saved.categoryId, 'category-food');
      expect(saved.subcategoryId, 'subcategory-dining');
      expect(saved.paymentSourceId, 'source-visa');

      expect(
        find.byKey(const ValueKey('transaction-detail-summary-card')),
        findsOneWidget,
      );
      expect(find.text('Corner Cafe'), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Dining'), findsOneWidget);
      expect(find.text('Visa'), findsOneWidget);
    },
  );

  testWidgets(
    'legacy child category normalizes in editor without losing classification',
    (tester) async {
      final finance = services<FinanceServices>();
      categories.values['category-food'] = Category(
        id: CategoryId('category-food'),
        name: 'Food',
        origin: CategoryOrigin.user,
      );
      categories.values['subcategory-dining'] = Category(
        id: CategoryId('subcategory-dining'),
        name: 'Dining',
        origin: CategoryOrigin.user,
        parentId: CategoryId('category-food'),
      );
      final legacy = Transaction(
        id: TransactionId('legacy-category-shape'),
        timing: KnownTransactionTime(DateTime.utc(2026, 9, 20, 12)),
        money: Money(
          amount: DecimalValue.parse('18.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.manual,
        transactionDate: '2026-09-20',
        description: 'Legacy lunch',
        categoryId: CategoryId('subcategory-dining'),
        provenance: [
          Provenance(
            id: ProvenanceId('legacy-category-shape-provenance'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: DateTime.utc(2026, 9, 20, 12),
          ),
        ],
        createdAt: DateTime.utc(2026, 9, 20, 12),
        updatedAt: DateTime.utc(2026, 9, 20, 12),
      );
      await repository.save(legacy);

      await tester.pumpWidget(
        MaterialApp(
          home: _EditorHarness(
            finance: finance,
            existing: TransactionDto.fromDomain(legacy),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      await _scrollEditorToMasterData(tester);
      _expectEditorSelection(tester, 'Food');
      _expectEditorSelection(tester, 'Dining');

      await _scrollEditorToSave(tester);
      await tester.tap(find.text('Save locally'));
      await tester.pumpAndSettle();

      final refreshed = await finance.getTransaction('legacy-category-shape');
      final saved = (refreshed as ApplicationSuccess<TransactionDto>).value;
      expect(saved.categoryId, 'category-food');
      expect(saved.subcategoryId, 'subcategory-dining');
    },
  );

  testWidgets(
    'editor keeps selected archived master-data references visible and intact',
    (tester) async {
      final finance = services<FinanceServices>();
      merchants.values['merchant-old'] = Merchant(
        id: MerchantId('merchant-old'),
        name: 'Old Merchant',
        status: MerchantStatus.archived,
      );
      categories.values['category-old'] = Category(
        id: CategoryId('category-old'),
        name: 'Old Category',
        origin: CategoryOrigin.user,
        status: CategoryStatus.archived,
      );
      categories.values['subcategory-old'] = Category(
        id: CategoryId('subcategory-old'),
        name: 'Old Subcategory',
        origin: CategoryOrigin.user,
        parentId: CategoryId('category-old'),
        status: CategoryStatus.archived,
      );
      paymentSources.values['source-old'] = PaymentSource(
        id: PaymentSourceId('source-old'),
        name: 'Old Card',
        type: PaymentSourceType.card,
        status: PaymentSourceStatus.archived,
      );
      final now = DateTime.utc(2026, 9, 20, 12);
      final existing = Transaction(
        id: TransactionId('archived-master-data'),
        timing: KnownTransactionTime(now),
        money: Money(
          amount: DecimalValue.parse('42.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.manual,
        transactionDate: '2026-09-20',
        description: 'Archived references',
        merchantId: MerchantId('merchant-old'),
        categoryId: CategoryId('category-old'),
        subcategoryId: CategoryId('subcategory-old'),
        paymentSourceId: PaymentSourceId('source-old'),
        provenance: [
          Provenance(
            id: ProvenanceId('archived-master-data-provenance'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await repository.save(existing);

      await tester.pumpWidget(
        MaterialApp(
          home: _EditorHarness(
            finance: finance,
            existing: TransactionDto.fromDomain(existing),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      await _scrollEditorToMasterData(tester);
      for (final selectedLabel in [
        'Old Merchant',
        'Old Category',
        'Old Subcategory',
        'Old Card',
      ]) {
        _expectEditorSelection(tester, selectedLabel);
      }

      await _scrollEditorToSave(tester);
      await tester.tap(find.text('Save locally'));
      await tester.pumpAndSettle();

      final refreshed = await finance.getTransaction('archived-master-data');
      final saved = (refreshed as ApplicationSuccess<TransactionDto>).value;
      expect(saved.merchantId, 'merchant-old');
      expect(saved.categoryId, 'category-old');
      expect(saved.subcategoryId, 'subcategory-old');
      expect(saved.paymentSourceId, 'source-old');
    },
  );

  testWidgets(
    'editor clears a stored subcategory whose parent mismatches category',
    (tester) async {
      final finance = services<FinanceServices>();
      categories.values['category-food-mismatch'] = Category(
        id: CategoryId('category-food-mismatch'),
        name: 'Food mismatch',
        origin: CategoryOrigin.user,
      );
      categories.values['category-travel-mismatch'] = Category(
        id: CategoryId('category-travel-mismatch'),
        name: 'Travel mismatch',
        origin: CategoryOrigin.user,
      );
      categories.values['subcategory-airfare-mismatch'] = Category(
        id: CategoryId('subcategory-airfare-mismatch'),
        name: 'Airfare mismatch',
        origin: CategoryOrigin.user,
        parentId: CategoryId('category-travel-mismatch'),
      );
      final now = DateTime.utc(2026, 9, 20, 12);
      final existing = Transaction(
        id: TransactionId('mismatched-category-shape'),
        timing: KnownTransactionTime(now),
        money: Money(
          amount: DecimalValue.parse('88.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.manual,
        transactionDate: '2026-09-20',
        description: 'Mismatched classification',
        categoryId: CategoryId('category-food-mismatch'),
        subcategoryId: CategoryId('subcategory-airfare-mismatch'),
        provenance: [
          Provenance(
            id: ProvenanceId('mismatched-category-shape-provenance'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await repository.save(existing);

      await tester.pumpWidget(
        MaterialApp(
          home: _EditorHarness(
            finance: finance,
            existing: TransactionDto.fromDomain(existing),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      await _scrollEditorToMasterData(tester);
      _expectEditorSelection(tester, 'Food mismatch');
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              widget.controller.text == 'Airfare mismatch',
        ),
        findsNothing,
      );

      await _scrollEditorToSave(tester);
      await tester.tap(find.text('Save locally'));
      await tester.pumpAndSettle();

      final refreshed = await finance.getTransaction(
        'mismatched-category-shape',
      );
      final saved = (refreshed as ApplicationSuccess<TransactionDto>).value;
      expect(saved.categoryId, 'category-food-mismatch');
      expect(saved.subcategoryId, isNull);
    },
  );

  testWidgets(
    'editor infers the parent for a known orphaned subcategory reference',
    (tester) async {
      final finance = services<FinanceServices>();
      categories.values['category-travel-orphan'] = Category(
        id: CategoryId('category-travel-orphan'),
        name: 'Travel orphan',
        origin: CategoryOrigin.user,
      );
      categories.values['subcategory-airfare-orphan'] = Category(
        id: CategoryId('subcategory-airfare-orphan'),
        name: 'Airfare orphan',
        origin: CategoryOrigin.user,
        parentId: CategoryId('category-travel-orphan'),
      );
      final now = DateTime.utc(2026, 9, 20, 12);
      final existing = Transaction(
        id: TransactionId('orphaned-subcategory-shape'),
        timing: KnownTransactionTime(now),
        money: Money(
          amount: DecimalValue.parse('101.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.manual,
        transactionDate: '2026-09-20',
        description: 'Orphaned subcategory classification',
        subcategoryId: CategoryId('subcategory-airfare-orphan'),
        provenance: [
          Provenance(
            id: ProvenanceId('orphaned-subcategory-shape-provenance'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await repository.save(existing);

      await tester.pumpWidget(
        MaterialApp(
          home: _EditorHarness(
            finance: finance,
            existing: TransactionDto.fromDomain(existing),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();

      await _scrollEditorToMasterData(tester);
      _expectEditorSelection(tester, 'Travel orphan');
      _expectEditorSelection(tester, 'Airfare orphan');

      await _scrollEditorToSave(tester);
      await tester.tap(find.text('Save locally'));
      await tester.pumpAndSettle();

      final refreshed = await finance.getTransaction(
        'orphaned-subcategory-shape',
      );
      final saved = (refreshed as ApplicationSuccess<TransactionDto>).value;
      expect(saved.categoryId, 'category-travel-orphan');
      expect(saved.subcategoryId, 'subcategory-airfare-orphan');
    },
  );

  testWidgets(
    'editor clears a stored subcategory whose parent mismatches category',
    (tester) async {
      final finance = services<FinanceServices>();
      categories.values['category-food-organize-mismatch'] = Category(
        id: CategoryId('category-food-organize-mismatch'),
        name: 'Food organize mismatch',
        origin: CategoryOrigin.user,
      );
      categories.values['category-travel-organize-mismatch'] = Category(
        id: CategoryId('category-travel-organize-mismatch'),
        name: 'Travel organize mismatch',
        origin: CategoryOrigin.user,
      );
      categories.values['subcategory-airfare-organize-mismatch'] = Category(
        id: CategoryId('subcategory-airfare-organize-mismatch'),
        name: 'Airfare organize mismatch',
        origin: CategoryOrigin.user,
        parentId: CategoryId('category-travel-organize-mismatch'),
      );
      final now = DateTime.utc(2026, 9, 20, 12);
      final existing = Transaction(
        id: TransactionId('mismatched-organizer-shape'),
        timing: KnownTransactionTime(now),
        money: Money(
          amount: DecimalValue.parse('91.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.manual,
        transactionDate: '2026-09-20',
        description: 'Mismatched organizer classification',
        categoryId: CategoryId('category-food-organize-mismatch'),
        subcategoryId: CategoryId('subcategory-airfare-organize-mismatch'),
        provenance: [
          Provenance(
            id: ProvenanceId('mismatched-organizer-shape-provenance'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await repository.save(existing);

      await tester.pumpWidget(
        MaterialApp(
          home: TransactionDetailPage(
            finance: finance,
            transaction: TransactionDto.fromDomain(existing),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapTransactionDetailEdit(tester);
      await _scrollEditorToMasterData(tester);

      _expectEditorSelection(tester, 'Food organize mismatch');
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              widget.controller.text == 'Airfare organize mismatch',
        ),
        findsNothing,
      );

      await _tapEditorSave(tester);

      final refreshed = await finance.getTransaction(
        'mismatched-organizer-shape',
      );
      final saved = (refreshed as ApplicationSuccess<TransactionDto>).value;
      expect(saved.categoryId, 'category-food-organize-mismatch');
      expect(saved.subcategoryId, isNull);
    },
  );

  testWidgets(
    'editor keeps selected archived category hierarchy visible and intact',
    (tester) async {
      final finance = services<FinanceServices>();
      categories.values['category-old-organize'] = Category(
        id: CategoryId('category-old-organize'),
        name: 'Archived Parent',
        origin: CategoryOrigin.user,
        status: CategoryStatus.archived,
      );
      categories.values['subcategory-old-organize'] = Category(
        id: CategoryId('subcategory-old-organize'),
        name: 'Archived Child',
        origin: CategoryOrigin.user,
        parentId: CategoryId('category-old-organize'),
        status: CategoryStatus.archived,
      );
      final now = DateTime.utc(2026, 9, 20, 12);
      final existing = Transaction(
        id: TransactionId('archived-organizer-category'),
        timing: KnownTransactionTime(now),
        money: Money(
          amount: DecimalValue.parse('17.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.manual,
        transactionDate: '2026-09-20',
        description: 'Archived organizer',
        categoryId: CategoryId('category-old-organize'),
        subcategoryId: CategoryId('subcategory-old-organize'),
        provenance: [
          Provenance(
            id: ProvenanceId('archived-organizer-category-provenance'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: now,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await repository.save(existing);

      await tester.pumpWidget(
        MaterialApp(
          home: TransactionDetailPage(
            finance: finance,
            transaction: TransactionDto.fromDomain(existing),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _tapTransactionDetailEdit(tester);
      await _scrollEditorToMasterData(tester);

      for (final selectedLabel in ['Archived Parent', 'Archived Child']) {
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is EditableText &&
                widget.controller.text == selectedLabel,
          ),
          findsOneWidget,
        );
      }

      await _tapEditorSave(tester);

      final refreshed = await finance.getTransaction(
        'archived-organizer-category',
      );
      final saved = (refreshed as ApplicationSuccess<TransactionDto>).value;
      expect(saved.categoryId, 'category-old-organize');
      expect(saved.subcategoryId, 'subcategory-old-organize');
    },
  );

  testWidgets('transaction detail refreshes evidence after a receipt scan', (
    tester,
  ) async {
    final transaction = TransactionDto(
      id: 'receipt-transaction',
      amount: '12.50',
      currency: 'USD',
      direction: 'expense',
      status: 'active',
      reviewState: 'clear',
      transactionDate: '2026-08-21',
      createdAt: DateTime.utc(2026, 8, 21),
      updatedAt: DateTime.utc(2026, 8, 21),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TransactionDetailPage(
          finance: services<FinanceServices>(),
          transaction: transaction,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transaction-detail-evidence-card')),
      240,
      scrollable: _transactionDetailScrollable(tester),
    );
    await tester.pumpAndSettle();
    expect(find.text('No evidence is attached locally.'), findsOneWidget);
    expect(find.text('Attach receipt'), findsNothing);
    expect(find.text('Attach file'), findsNothing);
    expect(find.text('Attach receipt or file'), findsNothing);
    expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing);

    notifyTransactionChanged();
    await tester.pumpAndSettle();
    expect(find.text('No evidence is attached locally.'), findsOneWidget);
    expect(evidenceRepository.listCalls, 2);
  });

  testWidgets('image evidence uses a localized view action label', (
    tester,
  ) async {
    final capturedAt = DateTime.utc(2026, 8, 21);
    evidenceRepository.items = [
      EvidenceItem(
        id: EvidenceId('image-evidence'),
        type: EvidenceType.receiptImage,
        originalName: 'IMG_4837.jpg',
        mediaType: 'image/jpeg',
        localFileName: 'stored-image.jpg',
        provenance: Provenance(
          id: ProvenanceId('image-provenance'),
          sourceType: ProvenanceSourceType.scan,
          capturedAt: capturedAt,
          originalRepresentation: 'IMG_4837.jpg',
        ),
        createdAt: capturedAt,
      ),
    ];
    final transaction = TransactionDto(
      id: 'image-transaction',
      amount: '12.50',
      currency: 'USD',
      direction: 'expense',
      status: 'active',
      reviewState: 'clear',
      transactionDate: '2026-08-21',
      createdAt: capturedAt,
      updatedAt: capturedAt,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TransactionDetailPage(
          finance: services<FinanceServices>(),
          transaction: transaction,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transaction-detail-evidence-card')),
      240,
      scrollable: _transactionDetailScrollable(tester),
    );
    await tester.pumpAndSettle();

    expect(find.text('View image'), findsOneWidget);
    expect(find.text('IMG_4837.jpg'), findsNothing);
    expect(find.text('image/jpeg'), findsNothing);
    expect(find.byType(ButlerlySecondaryTextAction), findsNothing);
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.title, isA<Text>());
    expect(tile.onTap, isNotNull);
    expect(evidenceRepository.items.single.originalName, 'IMG_4837.jpg');
  });

  testWidgets('transaction detail uses the card-based hierarchy', (
    tester,
  ) async {
    final transaction = TransactionDto(
      id: 'card-detail',
      amount: '128.45',
      currency: 'USD',
      direction: 'expense',
      status: 'active',
      reviewState: 'clear',
      description: 'Whole Foods Market',
      transactionDate: '2026-08-21',
      createdAt: DateTime.utc(2026, 8, 21),
      updatedAt: DateTime.utc(2026, 8, 21),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: TransactionDetailPage(
          finance: services<FinanceServices>(),
          transaction: transaction,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final summaryCard = find.byKey(
      const ValueKey('transaction-detail-summary-card'),
    );
    expect(summaryCard, findsOneWidget);
    expect(
      find.descendant(
        of: summaryCard,
        matching: find.text('Whole Foods Market'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summaryCard, matching: find.text('128.45')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summaryCard, matching: find.text('USD')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-detail-classification-card')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('transaction-detail-amount-card')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transaction-detail-notes-card')),
      200,
      scrollable: _transactionDetailScrollable(tester),
    );
    await tester.pumpAndSettle();
    final notesCard = find.byKey(
      const ValueKey('transaction-detail-notes-card'),
    );
    expect(notesCard, findsOneWidget);
    expect(
      find.descendant(of: notesCard, matching: find.text('Notes & Tags')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: notesCard, matching: find.text('Notes')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: notesCard, matching: find.text('Tags')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: notesCard, matching: find.text('Not set')),
      findsNWidgets(2),
    );
  });

  testWidgets('Add editor back exposes a localized semantic action', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(path: '/add', builder: (_, _) => const AddPage()),
        GoRoute(
          path: '/transactions/add',
          builder: (_, _) =>
              TransactionEditorPage(finance: services<FinanceServices>()),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: ThemeData.dark(),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    router.push<void>('/transactions/add');
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(TransactionEditorPage));
    final label = MaterialLocalizations.of(context).backButtonTooltip;
    expect(label, isNot('Back'));
    final back = find.bySemanticsLabel(label);
    expect(back, findsOneWidget);
    final node = tester.getSemantics(back);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    await tester.pumpAndSettle();
    expect(find.byType(AddPage), findsOneWidget);
  });

  testWidgets('Add editor exposes localized editable fields', (tester) async {
    for (var index = 0; index < 9; index++) {
      await tags.save(Tag(id: TagId('entry-tag-$index'), name: 'Tag $index'));
    }
    final router = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(path: '/add', builder: (_, _) => const AddPage()),
        GoRoute(
          path: '/transactions/add',
          builder: (_, _) =>
              TransactionEditorPage(finance: services<FinanceServices>()),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        theme: ThemeData.dark(),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    router.push<void>('/transactions/add');
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(TransactionEditorPage));
    for (final field in const [
      'amount',
      'currency',
      'descriptionOptional',
      'notesOptional',
      'searchTags',
    ]) {
      final label = context.l10n.text(field);
      final input = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );
      final editable = find.descendant(
        of: input,
        matching: find.byType(EditableText),
      );
      await tester.scrollUntilVisible(
        input,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final node = tester.getSemantics(editable);
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isTextField, isTrue, reason: field);
      expect(data.label, label, reason: field);
      expect(data.hasAction(SemanticsAction.focus), isTrue, reason: field);
      node.owner!.performAction(node.id, SemanticsAction.focus);
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(editable)
            .getSemanticsData()
            .flagsCollection
            .isFocused,
        Tristate.isTrue,
        reason: field,
      );
      expect(
        tester
            .getSemantics(editable)
            .getSemanticsData()
            .hasAction(SemanticsAction.setText),
        isTrue,
        reason: field,
      );
    }
  });

  testWidgets('creates, edits, and permanently deletes locally', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/add',
      routes: [
        GoRoute(path: '/add', builder: (_, _) => const AddPage()),
        GoRoute(
          path: '/transactions/add',
          builder: (_, _) =>
              TransactionEditorPage(finance: services<FinanceServices>()),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add transaction manually'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('transaction-direction-income')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('transaction-amount-field')),
      '12.50',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transaction-editor-description-card')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-description-field')),
      'Lunch',
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-notes-field')),
      'Team meal',
    );
    await tester.scrollUntilVisible(
      find.text('Save locally'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: TransactionsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Lunch'), findsOneWidget);
    expect(
      repository.values.values.single.direction,
      TransactionDirection.income,
    );
    expect(repository.values.values.single.notes, 'Team meal');
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transaction-detail-summary-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-detail-edit-button')),
      findsNothing,
    );
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Organize transaction'), findsNothing);
    expect(find.text('Assign payment source'), findsNothing);
    expect(find.text('Archive transaction'), findsNothing);
    expect(find.text('Restore transaction'), findsNothing);
    expect(find.text('Team meal'), findsOneWidget);
    final editButton = find.byKey(
      const ValueKey('transaction-detail-edit-button'),
    );
    final deleteButton = find.byKey(
      const ValueKey('transaction-detail-delete-button'),
    );
    await tester.scrollUntilVisible(
      editButton,
      200,
      scrollable: _transactionDetailScrollable(tester),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: editButton, matching: find.text('Edit')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: deleteButton, matching: find.text('Delete')),
      findsOneWidget,
    );

    await _tapTransactionDetailEdit(tester);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transaction-editor-description-card')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('transaction-description-field')),
      'Corrected lunch',
    );
    await tester.scrollUntilVisible(
      find.text('Save locally'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();
    await _scrollTransactionDetailToTop(tester);
    expect(
      find.byKey(const ValueKey('transaction-detail-summary-card')),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(
      deleteButton,
      200,
      scrollable: _transactionDetailScrollable(tester),
    );
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    final confirmDelete = find.text('Delete permanently').last;
    await tester.ensureVisible(confirmDelete);
    await tester.tap(confirmDelete);
    await tester.pumpAndSettle();

    expect(repository.values, isEmpty);
  });

  testWidgets('searches local transactions by assigned category', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'lunch',
        provenanceId: 'manual-lunch',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 8)),
        money: Money(
          amount: DecimalValue.parse('12.50'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Lunch',
        merchantId: 'test-canonical-merchant',
      ),
    );
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'bus',
        provenanceId: 'manual-bus',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 7)),
        money: Money(
          amount: DecimalValue.parse('3.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Bus',
      ),
    );
    await finance.saveCategory(
      Category(
        id: CategoryId('dining'),
        name: 'Dining',
        origin: CategoryOrigin.user,
      ),
    );
    await finance.assignCategory('lunch', 'dining');

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SearchPage())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
    final categoryFilter = find.byKey(const ValueKey('search-category-filter'));
    await tester.scrollUntilVisible(
      categoryFilter,
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(categoryFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('apply-search-filters')),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('apply-search-filters')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), 'Lunch');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Lunch'), findsAtLeastNWidgets(1));
    expect(find.text('Bus'), findsNothing);
    expect(find.text('1 transaction'), findsNWidgets(2));
  });

  testWidgets('Search can apply the undated transaction filter', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SearchPage())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
    final undatedFilter = find.byKey(const ValueKey('search-undated-filter'));
    await tester.ensureVisible(undatedFilter);
    await tester.tap(undatedFilter);
    await tester.ensureVisible(
      find.byKey(const ValueKey('apply-search-filters')),
    );
    await tester.tap(find.byKey(const ValueKey('apply-search-filters')));
    await tester.pumpAndSettle();

    expect(repository.lastQuery?.includeUndated, isTrue);
    expect(find.text('Clear filters'), findsOneWidget);
  });

  testWidgets('transaction count uses singular and plural labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            TransactionCountText(count: 1),
            TransactionCountText(count: 23),
          ],
        ),
      ),
    );

    expect(find.text('1 transaction'), findsOneWidget);
    expect(find.text('23 transactions'), findsOneWidget);
  });

  testWidgets('cancelling Search filters preserves the active filter state', (
    tester,
  ) async {
    await services<FinanceServices>().saveCategory(
      Category(
        id: CategoryId('cancel-category'),
        name: 'Dining',
        origin: CategoryOrigin.user,
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SearchPage())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
    final categoryFilter = find.byKey(const ValueKey('search-category-filter'));
    await tester.scrollUntilVisible(
      categoryFilter,
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(categoryFilter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    final filterButton = tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byIcon(Icons.tune_rounded),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(filterButton.isSelected, isFalse);
    expect(find.byKey(const ValueKey('apply-search-filters')), findsNothing);
  });

  testWidgets('clearing period filters also clears Home undated fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchPage(
            initialQuery: ListTransactionsQuery(
              from: DateTime(2026, 8, 1),
              to: DateTime(2026, 8, 31),
              timeZoneId: 'America/Los_Angeles',
              includeUndated: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Clear filters'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune_rounded).first);
    await tester.pumpAndSettle();
    final clearFilters = find.text('Clear filters').last;
    await tester.ensureVisible(clearFilters);
    await tester.tap(clearFilters);
    await tester.pumpAndSettle();

    expect(repository.lastQuery?.includeUndated, isFalse);
    expect(repository.lastQuery?.occurredAtFrom, isNull);
    expect(repository.lastQuery?.occurredAtToExclusive, isNull);
  });

  testWidgets('keyboard submission and clear text update Search immediately', (
    tester,
  ) async {
    await services<FinanceServices>().createTransaction(
      CreateTransactionCommand(
        id: 'keyboard-search',
        provenanceId: 'keyboard-search-provenance',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 9)),
        money: Money(
          amount: DecimalValue.parse('12.50'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Keyboard Search Match',
      ),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SearchPage())),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(EditableText), 'Keyboard Search');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Keyboard Search Match'), findsAtLeastNWidgets(1));
    expect(find.text('1 transaction'), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Keyboard Search Match'), findsAtLeastNWidgets(1));
    expect(find.text('1 transaction'), findsNWidgets(2));
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets(
    'Transactions and Search tighten header-to-sticky spacing while Review stays primary',
    (tester) async {
      for (final page in const <Widget>[TransactionsPage(), SearchPage()]) {
        await tester.pumpWidget(MaterialApp(home: page));
        await tester.pumpAndSettle();

        final butlerlyPage = tester.widget<ButlerlyPage>(
          find.byType(ButlerlyPage),
        );
        expect(
          butlerlyPage.pinnedSpacing,
          same(ButlerlyPinnedPageSpacing.tightHeader),
        );
        expect(
          butlerlyPage.pinnedSpacing.headerBottomGap,
          ButlerlySpacing.none,
        );
        expect(
          butlerlyPage.pinnedSpacing.pinnedTopGap,
          ButlerlySpacing.pinnedPageTopGap,
        );
      }

      await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
      await tester.pumpAndSettle();
      final reviewPage = tester.widget<ButlerlyPage>(find.byType(ButlerlyPage));
      expect(reviewPage.pinnedSpacing, same(ButlerlyPinnedPageSpacing.primary));
    },
  );

  testWidgets(
    'Transactions and Search pinned headers stay within 44px at ultra-narrow widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(88, 400);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      for (final width in [80.0, 88.0]) {
        tester.view.physicalSize = Size(width, 400);
        for (final page in const <Widget>[TransactionsPage(), SearchPage()]) {
          await tester.pumpWidget(MaterialApp(home: page));
          await tester.pumpAndSettle();

          expect(
            tester.takeException(),
            isNull,
            reason: '${page.runtimeType} pinned header overflowed at $width px',
          );
          final controlsKey = page is TransactionsPage
              ? const ValueKey('transactions-pinned-controls')
              : const ValueKey('search-pinned-controls');
          final controlsRect = tester.getRect(find.byKey(controlsKey));
          expect(
            controlsRect.height,
            closeTo(ButlerlySize.searchPinnedHeaderHeight, 0.1),
          );
        }
      }
    },
  );

  testWidgets('primary pinned-page spacing renders all four requested gaps', (
    tester,
  ) async {
    const pinnedKey = ValueKey('spacing-test-pinned');
    const bodyKey = ValueKey('spacing-test-body');

    await tester.pumpWidget(
      const MaterialApp(
        home: ButlerlyPage(
          title: 'Spacing',
          pinnedSpacing: ButlerlyPinnedPageSpacing.primary,
          pinnedHeader: SizedBox(
            key: pinnedKey,
            height: ButlerlySize.minimumTarget,
          ),
          children: [
            SizedBox(key: bodyKey, height: ButlerlySize.minimumTarget),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sliverAppBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    final appBarBottom = tester.getBottomLeft(find.byType(AppBar)).dy;
    final pinnedRect = tester.getRect(find.byKey(pinnedKey));
    final bodyRect = tester.getRect(find.byKey(bodyKey));

    expect(
      sliverAppBar.bottom?.preferredSize.height,
      ButlerlySpacing.pinnedPageHeaderBottomGap,
    );
    expect(
      pinnedRect.top - appBarBottom,
      closeTo(ButlerlySpacing.pinnedPageTopGap, 0.01),
    );
    expect(
      bodyRect.top - pinnedRect.bottom,
      closeTo(
        ButlerlySpacing.pinnedPageBottomGap +
            ButlerlySpacing.pinnedPageBodyTopGap,
        0.01,
      ),
    );
  });

  testWidgets('Home refreshes when a transaction changes outside its route', (
    tester,
  ) async {
    HomePage.debugCurrentDate = DateTime.utc(2026, 8, 15, 12);
    addTearDown(() => HomePage.debugCurrentDate = null);

    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await tester.pumpAndSettle();
    expect(find.text('New global transaction'), findsNothing);

    await services<FinanceServices>().createTransaction(
      CreateTransactionCommand(
        id: 'global-add',
        provenanceId: 'manual-global-add',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 11)),
        money: Money(
          amount: DecimalValue.parse('18.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'New global transaction',
      ),
    );
    notifyTransactionChanged();
    await tester.pumpAndSettle();

    expect(find.text('New global transaction'), findsOneWidget);
  });

  testWidgets(
    'Home recent transaction uses merchant title matching amount size and hides tags',
    (tester) async {
      HomePage.debugCurrentDate = DateTime.utc(2026, 8, 15, 12);
      addTearDown(() => HomePage.debugCurrentDate = null);

      final finance = services<FinanceServices>();
      await finance.saveMerchant(
        Merchant(id: MerchantId('home-merchant'), name: 'Home Market'),
      );
      await finance.saveTag(Tag(id: TagId('home-tag'), name: 'Home Weekly'));
      await finance.createTransaction(
        CreateTransactionCommand(
          id: 'home-merchant-row',
          provenanceId: 'manual-home-merchant-row',
          timing: KnownTransactionTime(DateTime.utc(2026, 8, 11)),
          money: Money(
            amount: DecimalValue.parse('19.75'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'Home description fallback',
        ),
      );
      await finance.assignMerchant('home-merchant-row', 'home-merchant');
      await finance.addTag('home-merchant-row', 'home-tag');

      await tester.pumpWidget(const MaterialApp(home: HomePage()));
      await tester.pumpAndSettle();

      expect(find.text('Home Market'), findsOneWidget);
      expect(find.text('Home description fallback'), findsNothing);
      expect(find.text('Home Weekly'), findsNothing);

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('home-recent-card')),
          matching: find.byIcon(Icons.chevron_right_rounded),
        ),
        findsNothing,
      );

      final title = tester.widget<Text>(find.text('Home Market'));
      final amount = tester.widget<Text>(find.text(r'-$19.75'));
      expect(amount.style?.fontSize, title.style?.fontSize);
      final headerAction = find.byKey(const Key('home-recent-view-all'));
      expect(
        tester.getTopLeft(find.text('Home Market')).dy -
            tester.getBottomRight(headerAction).dy,
        closeTo(ButlerlySpacing.micro, 0.01),
        reason: 'Keep the compact recent-row gap below the 44 px action target',
      );
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Home Market'));
      await tester.pumpAndSettle();

      final row = find.bySemanticsLabel(RegExp(r'^Home Market, -'));
      expect(row, findsOneWidget);
      final node = tester.getSemantics(row);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pumpAndSettle();
      expect(find.byType(TransactionDetailPage), findsOneWidget);
    },
  );

  testWidgets('Transactions rows use the Home dashboard row style', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.saveMerchant(
      Merchant(id: MerchantId('merchant-row'), name: 'Corner Market'),
    );
    await finance.saveCategory(
      Category(
        id: CategoryId('category-row'),
        name: 'Groceries',
        origin: CategoryOrigin.user,
      ),
    );
    await finance.saveTag(Tag(id: TagId('tag-row'), name: 'Weekly'));
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'organized-row',
        provenanceId: 'manual-organized-row',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 11)),
        money: Money(
          amount: DecimalValue.parse('31.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Organized row',
      ),
    );
    await finance.assignMerchant('organized-row', 'merchant-row');
    await finance.assignCategory('organized-row', 'category-row');
    await finance.addTag('organized-row', 'tag-row');
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'organized-row-previous-day',
        provenanceId: 'manual-organized-row-previous-day',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 10)),
        money: Money(
          amount: DecimalValue.parse('12.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Previous day',
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: TransactionsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Corner Market'), findsOneWidget);
    expect(find.text('Organized row'), findsNothing);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Weekly'), findsNothing);
    expect(find.text('2 transactions'), findsNWidgets(2));
    expect(find.text('\$43.00'), findsNWidgets(2));
    expect(find.text('Aug 11, 2026'), findsOneWidget);
    expect(find.text('Aug 10, 2026'), findsOneWidget);
    final monthCard = find.byKey(
      const ValueKey('transaction-month-card-2026-08'),
    );
    expect(monthCard, findsOneWidget);
    expect(
      find.descendant(of: monthCard, matching: find.byType(Card)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(of: monthCard, matching: find.byType(ExpansionTile)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: monthCard, matching: find.text('2 transactions')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: monthCard, matching: find.text('\$43.00')),
      findsOneWidget,
    );
    expect(find.byType(ButlerlyRecordRow), findsNWidgets(2));
    final rows = tester.widgetList<ButlerlyRecordRow>(
      find.byType(ButlerlyRecordRow),
    );
    for (final row in rows) {
      expect(row.variant, ButlerlyTransactionRowVariant.dashboard);
      expect(row.showCategoryPill, isTrue);
      expect(row.amountIncludesCurrency, isTrue);
      expect(row.showNavigationIndicator, isFalse);
      expect(row.tags, isEmpty);
    }
    final controlsBottom = tester.getBottomLeft(
      find.byKey(const ValueKey('transactions-pinned-controls')),
    );
    final firstRowTop = tester.getTopLeft(find.byType(ButlerlyRecordRow).first);
    expect(
      firstRowTop.dy - controlsBottom.dy,
      greaterThanOrEqualTo(ButlerlySpacing.section),
    );
  });

  testWidgets('resolves an active local review issue', (tester) async {
    final finance = services<FinanceServices>();
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'reviewable',
        provenanceId: 'manual-reviewable',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 9)),
        money: Money(
          amount: DecimalValue.parse('12.50'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Lunch',
        merchantId: 'test-canonical-merchant',
      ),
    );
    final stored = repository.values['reviewable']!;
    final reviewCreatedAt = stored.updatedAt.add(const Duration(seconds: 1));
    repository.values['reviewable'] = stored.addReviewIssue(
      ReviewIssue(
        id: ReviewIssueId('review-1'),
        transactionId: TransactionId('reviewable'),
        reason: ReviewIssueReason.uncertain,
        createdAt: reviewCreatedAt,
      ),
      reviewCreatedAt,
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReviewPage())),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('compact-section-2')));
    await tester.tap(find.byKey(const ValueKey('compact-section-2')));
    await tester.pumpAndSettle();
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Resolve'), findsNothing);
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();

    expect(find.text('You’re all caught up'), findsOneWidget);
  });

  testWidgets(
    'Transactions reuses Search controls and filters while preserving content',
    (tester) async {
      await services<FinanceServices>().createTransaction(
        CreateTransactionCommand(
          id: 'tab-income',
          provenanceId: 'manual-tab-income',
          timing: KnownTransactionTime(DateTime.utc(2026, 8, 9)),
          money: Money(
            amount: DecimalValue.parse('100.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.income,
          description: 'Tab income',
        ),
      );
      await services<FinanceServices>().createTransaction(
        CreateTransactionCommand(
          id: 'tab-expense',
          provenanceId: 'manual-tab-expense',
          timing: KnownTransactionTime(DateTime.utc(2026, 8, 8)),
          money: Money(
            amount: DecimalValue.parse('25.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'Tab expense',
        ),
      );
      await services<FinanceServices>().createTransaction(
        CreateTransactionCommand(
          id: 'old-expense',
          provenanceId: 'manual-old-expense',
          timing: KnownTransactionTime(DateTime.utc(2026, 4, 8)),
          money: Money(
            amount: DecimalValue.parse('15.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'Older expense',
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: TransactionsPage()));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('transactions-pinned-controls')),
        findsOneWidget,
      );
      expect(find.byType(ButlerlyTransactionSearchControls), findsOneWidget);
      expect(find.byType(ButlerlyCompactSectionSelector), findsNothing);
      expect(find.text('Tab income'), findsOneWidget);
      expect(find.text('Tab expense'), findsOneWidget);
      expect(find.text('Older expense'), findsNothing);

      await tester.enterText(
        find.byKey(const ValueKey('transactions-search-field')),
        'income',
      );
      await tester.pump();
      expect(find.text('Tab income'), findsOneWidget);
      expect(find.text('Tab expense'), findsNothing);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Tab income'), findsOneWidget);
      expect(find.text('Tab expense'), findsOneWidget);

      await tester.tap(find.byTooltip('Filters (2)'));
      await tester.pumpAndSettle();
      expect(find.byType(ButlerlyTransactionFilterSheet), findsOneWidget);
      await tester.ensureVisible(find.text('Clear filters'));
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(find.text('April 2026'), findsOneWidget);
      await tester.tap(find.text('April 2026'));
      await tester.pumpAndSettle();
      expect(find.text('Older expense'), findsOneWidget);
    },
  );

  testWidgets(
    'bounded Transactions route refetches when undated filter expands results',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TransactionsPage(
            query: ListTransactionsQuery(
              from: DateTime(2026, 10, 1),
              to: DateTime(2026, 10, 31),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.lastQuery?.from, DateTime(2026, 10, 1));
      expect(repository.lastQuery?.to, DateTime(2026, 10, 31));
      expect(repository.lastQuery?.includeUndated, isFalse);

      await tester.tap(find.byIcon(Icons.tune_rounded).first);
      await tester.pumpAndSettle();
      final undatedFilter = find.byKey(const ValueKey('search-undated-filter'));
      await tester.ensureVisible(undatedFilter);
      await tester.tap(undatedFilter);
      await tester.ensureVisible(
        find.byKey(const ValueKey('apply-search-filters')),
      );
      await tester.tap(find.byKey(const ValueKey('apply-search-filters')));
      await tester.pumpAndSettle();

      expect(repository.lastQuery?.from, DateTime(2026, 10, 1));
      expect(repository.lastQuery?.to, DateTime(2026, 10, 31));
      expect(repository.lastQuery?.includeUndated, isTrue);
    },
  );

  testWidgets(
    'Search applies the scoped financial timezone to occurred-at boundaries',
    (tester) async {
      final finance = services<FinanceServices>();
      repository.filterOccurredAtQueries = true;
      await finance.saveUserPreference(
        UserPreference(
          locale: 'en',
          formattingLocale: 'en-US',
          regionCode: 'US',
          baseCurrency: CurrencyCode('USD'),
          // Deliberately differ from the scoped query timezone below.
          timeZoneId: 'UTC',
          firstUseCompleted: true,
        ),
      );
      await finance.createTransaction(
        CreateTransactionCommand(
          id: 'search-timezone-boundary',
          provenanceId: 'search-timezone-boundary-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 10, 1, 6, 30)),
          money: Money(
            amount: DecimalValue.parse('12.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'Pacific boundary expense',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SearchPage(
              initialQuery: ListTransactionsQuery(
                from: DateTime(2026, 10, 1),
                to: DateTime(2026, 10, 1),
                timeZoneId: 'America/Los_Angeles',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 06:30Z is September 30 in Los Angeles, so the scoped October 1
      // search must exclude it. Falling back to the configured UTC timezone
      // would incorrectly include the transaction.
      expect(find.text('Pacific boundary expense'), findsNothing);
    },
  );

  testWidgets('Review transaction views use the canonical record list', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'review-canonical',
        provenanceId: 'manual-review-canonical',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 9)),
        money: Money(
          amount: DecimalValue.parse('12.50'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Canonical review row',
        merchantId: 'test-canonical-merchant',
      ),
    );
    final stored = repository.values['review-canonical']!;
    repository.values['review-canonical'] = stored.addReviewIssue(
      ReviewIssue(
        id: ReviewIssueId('review-canonical-issue'),
        transactionId: TransactionId('review-canonical'),
        reason: ReviewIssueReason.uncertain,
        createdAt: stored.updatedAt.add(const Duration(seconds: 1)),
        detail: 'Needs a category',
      ),
      stored.updatedAt.add(const Duration(seconds: 1)),
    );
    final router = GoRouter(
      initialLocation: '/review',
      routes: [
        GoRoute(
          path: '/review',
          builder: (context, state) => ReviewPage(
            showPossibleDuplicates:
                state.uri.queryParameters['view'] == 'duplicates',
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SegmentedButton), findsNothing);
    final uncategorizedPosition = tester.getTopLeft(
      find.byKey(const ValueKey('compact-section-0')),
    );
    final duplicatesPosition = tester.getTopLeft(
      find.byKey(const ValueKey('compact-section-1')),
    );
    final needsReviewPosition = tester.getTopLeft(
      find.byKey(const ValueKey('compact-section-2')),
    );
    expect(uncategorizedPosition.dx, lessThan(duplicatesPosition.dx));
    expect(duplicatesPosition.dx, lessThan(needsReviewPosition.dx));
    expect(find.text('(1)'), findsNothing);
    expect(find.text('Possible duplicates (0)'), findsOneWidget);
    expect(find.text('Canonical review row'), findsOneWidget);
    await tester.tap(find.text('Canonical review row'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailPage), findsOneWidget);
    expect(repository.values['review-canonical']?.categoryId, isNull);
    expect(repository.values['review-canonical']?.reviewIssues, hasLength(1));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    router.go('/review?view=duplicates');
    await tester.pumpAndSettle();
    expect(find.text('Rescan possible duplicates'), findsNothing);
    expect(
      tester
          .widget<ButlerlyCompactSectionSelector>(
            find.byType(ButlerlyCompactSectionSelector),
          )
          .selectedIndex,
      1,
    );
    expect(find.text('Canonical review row'), findsNothing);
    router.go('/review');
    await tester.pumpAndSettle();
    expect(find.text('Canonical review row'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('compact-section-2')));
    await tester.tap(find.byKey(const ValueKey('compact-section-2')));
    await tester.pumpAndSettle();
    expect(find.byType(ButlerlyCard), findsNWidgets(2));
    expect(find.byType(ButlerlyRecordRow), findsOneWidget);
    expect(find.text('Needs a category'), findsOneWidget);
    expect(find.text('Resolve'), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('compact-section-0')));
    await tester.tap(find.byKey(const ValueKey('compact-section-0')));
    await tester.pumpAndSettle();
    expect(find.byType(ButlerlyTransactionList), findsOneWidget);
    expect(find.byType(ButlerlyRecordRow), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Home-scoped Review keeps review items inside the selected period',
    (tester) async {
      final finance = services<FinanceServices>();
      repository.filterPeriodQueries = true;
      for (final entry in [
        ('review-in-period', 'In-period review', '2026-09-05'),
        ('review-outside-period', 'Outside-period review', '2026-08-05'),
      ]) {
        final created = await finance.createTransaction(
          CreateTransactionCommand(
            id: entry.$1,
            provenanceId: '${entry.$1}-provenance',
            timing: KnownTransactionTime(
              DateTime.parse('${entry.$3}T12:00:00Z'),
            ),
            transactionDate: entry.$3,
            money: Money(
              amount: DecimalValue.parse('12.50'),
              currency: CurrencyCode('USD'),
            ),
            direction: TransactionDirection.expense,
            description: entry.$2,
          ),
        );
        expect(created, isA<ApplicationSuccess<TransactionDto>>());
        final transaction = repository.values[entry.$1]!;
        repository.values[entry.$1] = transaction.addReviewIssue(
          ReviewIssue(
            id: ReviewIssueId('${entry.$1}-issue'),
            transactionId: TransactionId(entry.$1),
            reason: ReviewIssueReason.uncertain,
            createdAt: transaction.updatedAt.add(const Duration(seconds: 1)),
          ),
          transaction.updatedAt.add(const Duration(seconds: 1)),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: ReviewPage(
            reviewScope: ReviewPeriodScope.fromDateValues(
              startDate: '2026-09-01',
              endDate: '2026-09-16',
              timeZoneId: 'UTC',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('In-period review'), findsOneWidget);
      expect(find.text('Outside-period review'), findsNothing);
      expect(find.byType(ButlerlyCompactSectionSelector), findsNothing);
    },
  );

  testWidgets(
    'Review rejects a partial period scope instead of broadening it',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ReviewPage(
            showNeedsReview: true,
            reviewScope: ReviewPeriodScope.invalid(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review items could not be loaded'), findsOneWidget);
      expect(find.byType(ButlerlyCompactSectionSelector), findsNothing);
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets(
    'Review rejects an invalid calendar date instead of normalizing it',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ReviewPage(
            showNeedsReview: true,
            reviewScope: ReviewPeriodScope.invalid(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Review items could not be loaded'), findsOneWidget);
      expect(find.byType(ButlerlyCompactSectionSelector), findsNothing);
    },
  );

  testWidgets('Review rejects an invalid reason instead of broadening it', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ReviewPage(
          showNeedsReview: true,
          invalidReviewReason: true,
          reviewScope: ReviewPeriodScope.unscoped(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Review items could not be loaded'), findsOneWidget);
    expect(find.byType(ButlerlyCompactSectionSelector), findsNothing);
  });

  testWidgets('Review groups dates and shows one issue per transaction', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    for (var i = 0; i < 3; i++) {
      await finance.createTransaction(
        CreateTransactionCommand(
          id: 'group-$i',
          provenanceId: 'group-p-$i',
          timing: KnownTransactionTime(DateTime.utc(2026, 9, i == 2 ? 3 : 4)),
          transactionDate: i == 2 ? '2026-09-03' : '2026-09-04',
          money: Money(
            amount: DecimalValue.parse('42.18'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'Grouped merchant $i',
          merchantId: 'test-canonical-merchant',
        ),
      );
      var stored = repository.values['group-$i']!;
      for (var issue = 0; issue < 2; issue++) {
        final at = stored.updatedAt.add(const Duration(seconds: 1));
        stored = stored.addReviewIssue(
          ReviewIssue(
            id: ReviewIssueId('group-$i-issue-$issue'),
            transactionId: stored.id,
            reason: ReviewIssueReason.conflict,
            createdAt: at,
            detail: issue == 0
                ? 'Receipt amount differs from transaction'
                : 'Secondary issue',
          ),
          at,
        );
      }
      repository.values['group-$i'] = stored;
    }
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReviewPage())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ButlerlyCard), findsNWidgets(2));
    expect(find.text('Category and subcategory are missing'), findsNWidgets(3));
    await tester.tap(find.byKey(const ValueKey('compact-section-2')));
    await tester.pumpAndSettle();
    expect(find.byType(ButlerlyCard), findsNWidgets(2));
    expect(find.byType(ButlerlyRecordRow), findsNWidgets(3));
    expect(
      find.text('Receipt amount differs from transaction'),
      findsNWidgets(3),
    );
    expect(find.text('Secondary issue'), findsNothing);
    expect(find.text('Resolve'), findsNothing);
    await tester.tap(find.text('Grouped merchant 0'));
    await tester.pumpAndSettle();
    expect(find.text('Secondary issue'), findsOneWidget);
    expect(find.text('Resolve'), findsNWidgets(2));
    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    expect(find.byType(TransactionDetailPage), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Resolve'), findsNothing);
    expect(find.byType(ButlerlyRecordRow), findsNWidgets(3));
  });

  testWidgets('normalization completion after leaving detail is safe', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.saveUserPreference(
      UserPreference(
        locale: 'en',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'UTC',
      ),
    );
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'normalize-review',
        provenanceId: 'normalize-p',
        timing: KnownTransactionTime(DateTime.utc(2026, 9, 4)),
        money: Money(
          amount: DecimalValue.parse('42.18'),
          currency: CurrencyCode('EUR'),
        ),
        direction: TransactionDirection.expense,
        description: 'Normalize me',
        merchantId: 'test-canonical-merchant',
      ),
    );
    final stored = repository.values['normalize-review']!;
    repository.values['normalize-review'] = stored.addReviewIssue(
      ReviewIssue(
        id: ReviewIssueId('normalize-issue'),
        transactionId: stored.id,
        reason: ReviewIssueReason.normalizationMissing,
        createdAt: stored.updatedAt,
      ),
      stored.updatedAt,
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReviewPage())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compact-section-2')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Normalize me'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '50');
    final pending = Completer<void>();
    repository.saveGate = pending.future;
    await tester.tap(find.text('Confirm'));
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ReviewPage), findsOneWidget);
    expect(find.text('Normalize me'), findsNothing);
    expect(repository.values['normalize-review']!.normalizedMoney, isNotEmpty);
  });

  testWidgets('Review tabs select each existing review view', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ReviewPage())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ButlerlyCompactSectionSelector), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(SegmentedButton), findsNothing);
    expect(
      find
          .byType(SliverPersistentHeader)
          .evaluate()
          .where(
            (element) => (element.widget as SliverPersistentHeader).pinned,
          ),
      isNotEmpty,
    );

    await tester.tap(find.byKey(const ValueKey('compact-section-0')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ButlerlyCompactSectionSelector>(
            find.byType(ButlerlyCompactSectionSelector),
          )
          .selectedIndex,
      0,
    );
    expect(find.text('You’re all caught up'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('compact-section-1')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ButlerlyCompactSectionSelector>(
            find.byType(ButlerlyCompactSectionSelector),
          )
          .selectedIndex,
      1,
    );
    expect(find.text('No possible duplicates found'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('compact-section-2')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ButlerlyCompactSectionSelector>(
            find.byType(ButlerlyCompactSectionSelector),
          )
          .selectedIndex,
      2,
    );
    expect(find.text('You’re all caught up'), findsOneWidget);
  });

  testWidgets('Review duplicates query selects the duplicate mode on entry', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/review?view=duplicates',
      routes: [
        GoRoute(
          path: '/review',
          builder: (context, state) => ReviewPage(
            showPossibleDuplicates:
                state.uri.queryParameters['view'] == 'duplicates',
          ),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Rescan possible duplicates'), findsNothing);
    expect(
      tester
          .widget<ButlerlyCompactSectionSelector>(
            find.byType(ButlerlyCompactSectionSelector),
          )
          .selectedIndex,
      1,
    );
    router.go('/review');
    await tester.pumpAndSettle();
    expect(find.text('Rescan possible duplicates'), findsNothing);
    expect(find.text('You’re all caught up'), findsOneWidget);
  });

  testWidgets('Review mode labels stay centered at narrow text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(320, 568),
            textScaler: TextScaler.linear(1.5),
          ),
          child: ReviewPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('Review reloads when a transaction change is notified', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'review-refresh',
        provenanceId: 'manual-review-refresh',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 9)),
        money: Money(
          amount: DecimalValue.parse('12.50'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Refresh me',
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('compact-section-0')));
    await tester.tap(find.byKey(const ValueKey('compact-section-0')));
    await tester.pumpAndSettle();
    expect(find.text('Refresh me'), findsOneWidget);
    expect(find.text('(1)'), findsNothing);
    expect(find.text('(0)'), findsNothing);
    expect(find.text('Possible duplicates (0)'), findsOneWidget);
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'review-refresh-added',
        provenanceId: 'manual-review-refresh-added',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 10)),
        money: Money(
          amount: DecimalValue.parse('8.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Added after refresh',
      ),
    );
    notifyTransactionChanged();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('compact-section-0')));
    await tester.tap(find.byKey(const ValueKey('compact-section-0')));
    await tester.pumpAndSettle();
    expect(find.text('Added after refresh'), findsOneWidget);
    expect(find.text('(2)'), findsNothing);
    expect(find.text('(0)'), findsNothing);
    expect(find.text('Possible duplicates (0)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Possible Duplicates review shows groups and resolves Keep Both',
    (tester) async {
      final first = _editorTransaction('review-duplicate-a');
      final second = _editorTransaction('review-duplicate-b');
      paymentSources.values['source-internal-1'] = PaymentSource(
        id: PaymentSourceId('source-internal-1'),
        name: 'Travel card',
        type: PaymentSourceType.card,
      );
      final now = DateTime.now().toUtc();
      final firstWithSource = first.assignPaymentSource(
        PaymentSourceId('source-internal-1'),
        now,
      );
      final masterData = await TransactionMasterDataProvider(
        services<FinanceServices>(),
      ).load();
      expect(masterData.paymentSources.single.name, 'Travel card');
      expect(firstWithSource.paymentSourceId?.value, 'source-internal-1');
      await repository.save(firstWithSource);
      await repository.save(second);
      await services<FinanceServices>()
          .scanExistingTransactionsForDuplicates!();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ReviewPage(showPossibleDuplicates: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Possible duplicate group'), findsOneWidget);
      expect(find.text('Rescan possible duplicates'), findsNothing);
      expect(find.byType(Radio<TransactionId>), findsNWidgets(2));
      expect(find.text('Keep both'), findsOneWidget);
      expect(
        find.textContaining('Travel card', skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.textContaining('source-internal-1', skipOffstage: false),
        findsNothing,
      );

      await tester.tap(find.text('Keep both'));
      await tester.pumpAndSettle();

      expect(find.text('No possible duplicates found'), findsOneWidget);
      expect(
        duplicateGroups.groups.single.status,
        DuplicateCandidateGroupStatus.keepBoth,
      );
      expect(
        repository.values.keys,
        containsAll([firstWithSource.id.value, second.id.value]),
      );
    },
  );

  testWidgets(
    'statement duplicate candidates are visible in Possible Duplicates and link explicitly',
    (tester) async {
      final existing = _editorTransaction('statement-review-existing');
      await repository.save(existing);
      final now = existing.createdAt;
      final statement = FinancialStatement(
        id: 'statement-review',
        evidenceId: 'statement-review-evidence',
        status: StatementStatus.ready,
        createdAt: now,
        updatedAt: now,
      );
      final row = StatementRow(
        id: 'statement-review-row',
        statementId: statement.id,
        position: 0,
        originalText: 'Existing merchant 25 USD',
        transactionDate: DateTime.parse(existing.transactionDate!),
        description: 'Existing merchant',
        amount: '25.00',
        currency: 'USD',
        direction: TransactionDirection.expense.name,
        status: StatementRowStatus.unresolved,
        reviewReason: 'statementDuplicateCandidate',
        createdAt: now,
        updatedAt: now,
      );
      await statementRepository.saveStatementWithRows(statement, [row]);
      final duplicateKey = DuplicateTransactionKey(
        transactionDate: existing.transactionDate!,
        amount: existing.money.amount,
        currency: 'USD',
        direction: TransactionDirection.expense.name,
      );
      await duplicateGroups.save(
        DuplicateCandidateGroup(
          id: 'duplicate:${duplicateKey.canonical}',
          transactionIds: [existing.id],
          duplicateKey: duplicateKey,
          status: DuplicateCandidateGroupStatus.unresolved,
          statementRows: [
            DuplicateCandidateStatementRow(
              statementId: statement.id,
              rowId: row.id,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: ReviewPage(showPossibleDuplicates: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Existing merchant 25 USD'), findsOneWidget);
      expect(find.text('Link'), findsOneWidget);
      expect(find.text('Create New'), findsOneWidget);
      await tester.tap(find.text('Create New'));
      await tester.pump();
      expect(
        find.text('Assign a payment source before creating a new transaction.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();

      expect(find.text('No possible duplicates found'), findsOneWidget);
      expect(
        (await statementRepository.listRows(statement.id)).single.status,
        StatementRowStatus.linked,
      );
      expect(
        (await statementRepository.listRows(statement.id)).single.transactionId,
        existing.id.value,
      );
      expect(repository.values, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Possible Duplicates consolidate choice records metadata without mutating records',
    (tester) async {
      final first = _editorTransaction('consolidate-a');
      final second = _editorTransaction('consolidate-b');
      await repository.save(first);
      await repository.save(second);
      await services<FinanceServices>()
          .scanExistingTransactionsForDuplicates!();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ReviewPage(showPossibleDuplicates: true)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ButlerlyTransactionList), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.byType(ButlerlyButtonBar), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Keep both'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Consolidate / use one'),
        findsOneWidget,
      );
      final candidate = find.byType(TransactionRow).last;
      await tester.ensureVisible(candidate);
      await tester.tap(candidate);
      await tester.pump();
      final consolidate = find.text('Consolidate / use one');
      await tester.ensureVisible(consolidate);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Consolidate / use one'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.tap(consolidate);
      await tester.pumpAndSettle();

      expect(
        duplicateGroups.groups.single.status,
        DuplicateCandidateGroupStatus.consolidated,
      );
      expect(
        duplicateGroups.groups.single.selectedTransactionId?.value,
        second.id.value,
      );
      expect(repository.values['consolidate-a'], same(first));
      expect(repository.values['consolidate-b'], same(second));
    },
  );

  testWidgets(
    'Possible Duplicates can permanently repair a stale relationship',
    (tester) async {
      final first = _editorTransaction('stale-review-a');
      final second = _editorTransaction('stale-review-b');
      await repository.save(first);
      await repository.save(second);
      await duplicateGroups.save(
        DuplicateCandidateGroup(
          id: 'duplicate:stale-review',
          transactionIds: [first.id, second.id],
          duplicateKey: DuplicateTransactionKey(
            transactionDate: first.transactionDate!,
            amount: first.money.amount,
            currency: first.money.currency.value,
            direction: first.direction.name,
          ),
          status: DuplicateCandidateGroupStatus.unresolved,
          integrityIssue: const DuplicateCandidateGroupIntegrityIssue(
            code: 'staleDuplicateGroup',
            detail: 'The saved relationship no longer matches current facts.',
          ),
          createdAt: first.createdAt,
          updatedAt: first.updatedAt,
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ReviewPage(showPossibleDuplicates: true)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Clear stale duplicate relationship'), findsOneWidget);
      expect(
        find.textContaining(
          'Your transactions and source evidence stay unchanged.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Clear stale duplicate relationship'));
      await tester.pumpAndSettle();

      expect(find.text('No possible duplicates found'), findsOneWidget);
      expect(duplicateGroups.groups, isEmpty);
      expect(repository.values, containsPair(first.id.value, first));
      expect(repository.values, containsPair(second.id.value, second));
    },
  );

  testWidgets('loading Possible Duplicates does not run a historical scan', (
    tester,
  ) async {
    await repository.save(_editorTransaction('review-load-a'));
    await repository.save(_editorTransaction('review-load-b'));
    final finance = services<FinanceServices>();
    await finance.scanExistingTransactionsForDuplicates!();
    duplicateGroups.fullScanCalls = 0;
    final notificationBeforeRescan = transactionChanges.value;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReviewPage(showPossibleDuplicates: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Possible duplicate group'), findsOneWidget);
    expect(duplicateGroups.fullScanCalls, 0);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 320));
    await tester.pumpAndSettle();
    expect(duplicateGroups.fullScanCalls, 1);
    expect(transactionChanges.value, notificationBeforeRescan);
  });

  for (final desktop in [false, true]) {
    testWidgets(
      '${desktop ? 'desktop' : 'compact'} wallet editor retains branded provider icons',
      (tester) async {
        tester.view.physicalSize = desktop
            ? const Size(1440, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final finance = services<FinanceServices>();
        await finance.savePaymentSource(
          PaymentSource(
            id: PaymentSourceId('paypal-source'),
            name: 'PayPal',
            type: PaymentSourceType.wallet,
            network: 'paypal',
          ),
        );

        await tester.pumpWidget(const MaterialApp(home: PaymentSourcesPage()));
        await tester.pumpAndSettle();

        // The saved payment source uses its branded mark in the list.
        expect(find.byType(ButlerlyPaymentSourceIcon), findsOneWidget);
        await tester.tap(find.text('PayPal').first);
        await tester.pumpAndSettle();

        final picker = tester.widget<ButlerlySelectField<String>>(
          find.byType(ButlerlySelectField<String>),
        );
        expect(picker.value, 'paypal');
        expect(picker.leadingIcon, isA<ButlerlyPaymentMarkIcon>());
        for (final provider in ['alipay', 'paypal', 'venmo', 'wechatPay']) {
          final entry = picker.entries.singleWhere(
            (entry) => entry.value == provider,
          );
          expect(
            entry.leadingIcon,
            isA<ButlerlyPaymentMarkIcon>(),
            reason: 'Missing $provider brand mark in provider menu',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final desktop in [false, true]) {
    testWidgets(
      '${desktop ? 'desktop' : 'compact'} issuer autocomplete saves canonical name',
      (tester) async {
        tester.view.physicalSize = desktop
            ? const Size(1440, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final finance = services<FinanceServices>();
        await tester.pumpWidget(const MaterialApp(home: PaymentSourcesPage()));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Add payment source'));
        await tester.pumpAndSettle();

        final issuerField = find.descendant(
          of: find.byType(ButlerlyIssuerAutocomplete),
          matching: find.byType(TextField),
        );
        expect(issuerField, findsOneWidget);
        await tester.enterText(find.byType(TextField).first, 'My account');
        await tester.enterText(issuerField, 'BoA');
        await tester.pumpAndSettle();
        expect(find.text('Bank of America'), findsWidgets);
        await tester.tap(find.text('Bank of America').last);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        final result = await finance.listPaymentSources();
        expect(result, isA<ApplicationSuccess<List<PaymentSource>>>());
        final records =
            (result as ApplicationSuccess<List<PaymentSource>>).value;
        expect(records.single.issuer, 'Bank of America');
        expect(records.single.type, PaymentSourceType.account);
      },
    );
  }

  testWidgets('creates and archives a local payment source', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PaymentSourcesPage()));
    await tester.pumpAndSettle();

    final revision = paymentSourceChanges.value;
    await tester.tap(find.byTooltip('Add payment source'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(paymentSourceChanges.value, revision);

    await tester.tap(find.byTooltip('Add payment source'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Travel card');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Travel card'), findsOneWidget);
    expect(paymentSourceChanges.value, revision + 1);
    await tester.tap(find.byTooltip('Archive payment source'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Archived'), findsOneWidget);
  });

  for (final action in ['Use existing', 'Create anyway', 'dismiss']) {
    testWidgets('compact duplicate payment source: $action', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final existing = PaymentSource(
        id: PaymentSourceId('existing-account'),
        name: 'Existing account',
        type: PaymentSourceType.account,
        lastFour: '8421',
      );
      await paymentSources.save(existing);
      final revision = paymentSourceChanges.value;

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PaymentSourcesPage())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add payment source'));
      await tester.pumpAndSettle();
      final name = find.byType(TextField).first;
      final lastFour = find.byType(TextField).at(2);
      await tester.enterText(name, 'New account');
      await tester.enterText(lastFour, '8421');
      final save = find.widgetWithText(FilledButton, 'Save');
      if (action == 'Create anyway') {
        final lookup = Completer<void>();
        paymentSources.listCompletion = lookup.future;
        final listCalls = paymentSources.listCalls;
        await tester.tap(save);
        await tester.tap(save);
        await tester.pump();

        expect(paymentSources.listCalls, listCalls + 1);
        expect(tester.widget<FilledButton>(save).onPressed, isNull);
        expect(find.text('Payment source already exists'), findsNothing);
        expect(paymentSources.saveCalls, 1);
        lookup.complete();
      } else {
        await tester.tap(save);
      }
      await tester.pumpAndSettle();

      expect(find.text('Payment source already exists'), findsOneWidget);
      expect(paymentSources.values.values, [existing]);
      expect(paymentSourceChanges.value, revision);

      if (action == 'dismiss') {
        await tester.binding.handlePopRoute();
      } else if (action == 'Create anyway') {
        final persistence = Completer<void>();
        paymentSources.saveCompletion = persistence.future;
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        final saving = find.widgetWithText(FilledButton, 'Saving…');
        expect(tester.widget<FilledButton>(saving).onPressed, isNull);
        expect(paymentSources.saveCalls, 2);
        expect(paymentSources.values.values, [existing]);
        expect(paymentSourceChanges.value, revision);
        persistence.complete();
      } else {
        await tester.tap(find.text(action));
      }
      await tester.pumpAndSettle();

      expect(find.text('Payment source already exists'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      if (action == 'dismiss') {
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        expect(tester.widget<TextField>(name).controller!.text, 'New account');
        expect(tester.widget<TextField>(lastFour).controller!.text, '8421');
      } else {
        expect(find.text('Save'), findsNothing);
      }
      if (action == 'Create anyway') {
        final created = paymentSources.values.values.singleWhere(
          (source) => source.id != existing.id,
        );
        expect(created.name, 'New account');
        expect(created.lastFour, '8421');
        expect(paymentSources.values.values, [existing, created]);
        expect(paymentSourceChanges.value, revision + 1);
      } else {
        expect(paymentSources.values.values, [existing]);
        expect(paymentSourceChanges.value, revision);
      }
    });
  }

  for (final desktop in [false, true]) {
    testWidgets(
      '${desktop ? 'desktop' : 'compact'} payment source lookup failure blocks save',
      (tester) async {
        tester.view.physicalSize = desktop
            ? const Size(1440, 900)
            : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: PaymentSourcesPage())),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Add payment source'));
        await tester.pumpAndSettle();
        final name = find.byType(TextField).first;
        final lastFour = find.byType(TextField).at(2);
        await tester.enterText(name, 'Draft account');
        await tester.enterText(lastFour, '8421');
        final save = find.widgetWithText(FilledButton, 'Save');
        final revision = paymentSourceChanges.value;
        paymentSources.failList = true;

        await tester.tap(save);
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Could not check for duplicate payment sources. Try again.',
          ),
          findsOneWidget,
        );
        expect(find.text('Payment source could not be saved.'), findsNothing);
        expect(
          tester.widget<TextField>(name).controller!.text,
          'Draft account',
        );
        expect(tester.widget<TextField>(lastFour).controller!.text, '8421');
        expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
        expect(paymentSources.saveCalls, 0);
        expect(paymentSources.values, isEmpty);
        expect(paymentSourceChanges.value, revision);

        paymentSources.failList = false;
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(paymentSources.saveCalls, 1);
        expect(paymentSources.values.values.single.name, 'Draft account');
        expect(paymentSources.values.values.single.lastFour, '8421');
        expect(paymentSourceChanges.value, revision + 1);
      },
    );
  }

  testWidgets('compact payment source persistence failure allows retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PaymentSourcesPage())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add payment source'));
    await tester.pumpAndSettle();
    final name = find.byType(TextField).first;
    await tester.enterText(name, 'Draft account');
    final save = find.widgetWithText(FilledButton, 'Save');
    final revision = paymentSourceChanges.value;
    paymentSources.failSave = true;

    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(find.text('Payment source could not be saved.'), findsOneWidget);
    expect(tester.widget<TextField>(name).controller!.text, 'Draft account');
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(paymentSources.saveCalls, 1);
    expect(paymentSources.values, isEmpty);
    expect(paymentSourceChanges.value, revision);

    paymentSources.failSave = false;
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Payment source could not be saved.'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(paymentSources.saveCalls, 2);
    expect(paymentSources.values.values.single.name, 'Draft account');
    expect(paymentSourceChanges.value, revision + 1);
  });

  for (final width in [390.0, 1200.0]) {
    testWidgets('Payment source cancellation respects save stage at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PaymentSourcesPage())),
      );
      await tester.pumpAndSettle();
      final revision = paymentSourceChanges.value;
      final add = find.byTooltip('Add payment source');
      final save = find.widgetWithText(FilledButton, 'Save');
      final cancel = find.widgetWithText(OutlinedButton, 'Cancel');
      Future<void> openDraft() async {
        await tester.tap(add);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Draft source');
      }

      await openDraft();
      final lookup = Completer<void>();
      paymentSources.listCompletion = lookup.future;
      await tester.tap(save);
      await tester.pump();
      if (width == 390) {
        await tester.drag(
          find.byKey(const ValueKey('butlerly-bottom-sheet-drag-handle')),
          const Offset(0, 150),
        );
      } else {
        await tester.tap(cancel);
      }
      lookup.complete();
      paymentSources.listCompletion = null;
      await tester.pumpAndSettle();
      expect(paymentSources.saveCalls, 0);
      expect(paymentSourceChanges.value, revision);
      expect(save, findsNothing);

      await openDraft();
      paymentSources.failSave = true;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Payment source could not be saved.'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        'Draft source',
      );
      expect(tester.widget<OutlinedButton>(cancel).onPressed, isNotNull);
      expect(paymentSourceChanges.value, revision);
      paymentSources.failSave = false;
      final write = Completer<void>();
      paymentSources.saveCompletion = write.future;
      await tester.tap(save);
      if (width == 390) {
        await tester.idle();
        expect(paymentSources.saveCalls, 2);
        await tester.binding.handlePopRoute();
      }
      await tester.pumpAndSettle();
      expect(paymentSources.saveCalls, 2);
      expect(find.text('Saving…'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(cancel).onPressed, isNull);
      await tester.tap(cancel);
      if (width == 390) {
        await tester.binding.handlePopRoute();
        await tester.tapAt(const Offset(10, 10));
        await tester.drag(
          find.byKey(const ValueKey('butlerly-bottom-sheet-drag-handle')),
          const Offset(0, 800),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Saving…'), findsOneWidget);
      expect(paymentSourceChanges.value, revision);

      write.complete();
      await tester.pumpAndSettle();
      expect(find.text('Saving…'), findsNothing);
      expect(save, findsNothing);
      expect(paymentSources.values.values.single.name, 'Draft source');
      expect(paymentSourceChanges.value, revision + 1);
      expect(find.text('Draft source'), findsOneWidget);
    });
  }

  testWidgets('credit cards require and display exactly four digits', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.savePaymentSource(
      PaymentSource(
        id: PaymentSourceId('legacy-card'),
        name: 'Travel card',
        type: PaymentSourceType.card,
        displayIdentity: 'Travel card',
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PaymentSourcesPage())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Travel card'));
    await tester.pumpAndSettle();
    expect(find.text('Edit payment source'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter exactly four digits.'), findsOneWidget);
    expect(find.text('Edit payment source'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(2), '8421');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Travel card •••• 8421'), findsOneWidget);
    final result = await finance.listPaymentSources();
    expect(result, isA<ApplicationSuccess<List<PaymentSource>>>());
    final values = (result as ApplicationSuccess<List<PaymentSource>>).value;
    expect(values.single.type, PaymentSourceType.card);
    expect(values.single.lastFour, '8421');
  });

  testWidgets(
    'Desktop settlements keep transaction drill-down in the right panel',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final finance = services<FinanceServices>();
      final source = PaymentSource(
        id: PaymentSourceId('settlement-panel-source'),
        name: 'Panel credit card',
        type: PaymentSourceType.card,
      );
      await finance.savePaymentSource(source);
      await paymentSettlements.save(
        PaymentSettlement(
          id: PaymentSettlementId('settlement-panel-next'),
          paymentSourceId: source.id,
          payment: Money(
            amount: DecimalValue.parse('80.00'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-10-15',
          periodStart: '2026-10-01',
          periodEnd: '2026-10-15',
          status: PaymentSettlementStatus.open,
          createdAt: DateTime.utc(2026, 10, 15),
          updatedAt: DateTime.utc(2026, 10, 15),
        ),
      );
      await paymentSettlements.save(
        PaymentSettlement(
          id: PaymentSettlementId('settlement-panel'),
          paymentSourceId: source.id,
          payment: Money(
            amount: DecimalValue.parse('100.00'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-09-15',
          periodStart: '2026-09-01',
          periodEnd: '2026-09-15',
          status: PaymentSettlementStatus.open,
          createdAt: DateTime.utc(2026, 9, 15),
          updatedAt: DateTime.utc(2026, 9, 15),
        ),
      );
      final created = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'settlement-period-transaction',
          provenanceId: 'settlement-period-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 9, 10, 12)),
          money: Money(
            amount: DecimalValue.parse('25.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          transactionDate: '2026-09-10',
          description: 'Period purchase',
          paymentSourceId: source.id.value,
        ),
      );
      expect(created, isA<ApplicationSuccess<TransactionDto>>());
      paymentSettlements.periodTransactions.add(
        repository.values['settlement-period-transaction']!,
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
      );
      await tester.pumpAndSettle();

      final settlementRow = find.byKey(
        const ValueKey('desktop-payment-settlement-settlement-panel'),
      );
      expect(settlementRow, findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop-transaction-detail-panel')),
        findsNothing,
      );

      await tester.tap(settlementRow);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-transaction-detail-panel')),
        findsOneWidget,
      );
      expect(find.byType(PaymentSettlementDetailPage), findsOneWidget);
      expect(find.byType(TransactionRow), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop-payment-settlement-edit-button')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-payment-settlement-actions-button')),
        findsOneWidget,
      );
      expect(find.byType(ButlerlyDesktopPanelFooter), findsOneWidget);
      expect(settlementRow, findsOneWidget);
      final originalDetailState = tester.state(
        find.byType(PaymentSettlementDetailPage),
      );

      await tester.tap(find.byType(TransactionRow));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('transaction-detail-summary-card')),
        findsOneWidget,
      );
      expect(find.byType(PaymentSettlementDetailPage), findsNothing);
      expect(settlementRow, findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop-transaction-detail-panel')),
        findsOneWidget,
      );

      // Closing a read-only transaction restores the *same* settlement
      // detail State, retaining its scroll position and loaded data.
      await tester.tap(
        find.byKey(const ValueKey('transaction-detail-close-panel')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PaymentSettlementDetailPage), findsOneWidget);
      expect(find.byType(TransactionRow), findsOneWidget);
      expect(settlementRow, findsOneWidget);
      expect(
        identical(
          tester.state(find.byType(PaymentSettlementDetailPage)),
          originalDetailState,
        ),
        isTrue,
      );

      // Editing a transaction must protect the unsaved draft when the user
      // clicks another settlement row in the still-visible left pane.
      await tester.tap(find.byType(TransactionRow));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('transaction-detail-edit-button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-description-field')),
        'Uncommitted change',
      );
      await tester.tap(
        find.byKey(
          const ValueKey('desktop-payment-settlement-settlement-panel-next'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('transaction-editor-content')),
        findsOneWidget,
      );
      expect(find.text('Uncommitted change'), findsOneWidget);
      expect(
        find.text(
          'Finish or cancel the transaction edit before opening another settlement.',
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-editor-cancel-panel')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('transaction-detail-summary-card')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-detail-close-panel')),
      );
      await tester.pumpAndSettle();

      // A saved transaction edit must invalidate the retained settlement
      // detail, but must not replace its State or reset the panel.
      await tester.tap(find.byType(TransactionRow));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('transaction-detail-edit-button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-description-field')),
        'Updated period purchase',
      );
      await tester.enterText(
        find.byKey(const ValueKey('transaction-amount-field')),
        '27.00',
      );
      // An attempted settlement switch displays a warning while this editor
      // is active. Save must remain physically tappable with it visible.
      await tester.tap(
        find.byKey(
          const ValueKey('desktop-payment-settlement-settlement-panel-next'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-settlement-edit-warning')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-editor-content')),
        findsOneWidget,
      );
      await _submitEmbeddedTransactionSave(tester);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-settlement-edit-warning')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('transaction-detail-summary-card')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('transaction-detail-close-panel')),
      );
      await tester.pumpAndSettle();
      expect(
        identical(
          tester.state(find.byType(PaymentSettlementDetailPage)),
          originalDetailState,
        ),
        isTrue,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TransactionRow &&
              widget.transaction.description == 'Updated period purchase' &&
              widget.transaction.amount == '27',
        ),
        findsOneWidget,
      );

      // Also cover the direct path: save a second edit, then select a
      // different settlement without first closing transaction details.
      await tester.tap(find.byType(TransactionRow));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('transaction-detail-edit-button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-description-field')),
        'Updated again',
      );
      await _submitEmbeddedTransactionSave(tester);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey('desktop-payment-settlement-settlement-panel-next'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PaymentSettlementDetailPage), findsOneWidget);
      await tester.tap(settlementRow);
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TransactionRow &&
              widget.transaction.description == 'Updated again',
        ),
        findsOneWidget,
      );

      // Delete in the embedded transaction detail, then verify that its
      // parent settlement refreshes the count/list rather than showing
      // the now-deleted period transaction.
      await tester.tap(find.byType(TransactionRow));
      await tester.pumpAndSettle();
      final deleteButton = find.byKey(
        const ValueKey('transaction-detail-delete-button'),
      );
      // Desktop detail actions are fixed outside the scrolling content.
      expect(find.byType(ButlerlyDesktopPanelFooter), findsOneWidget);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();
      final confirmDelete = find.text('Delete permanently').last;
      await tester.ensureVisible(confirmDelete);
      await tester.tap(confirmDelete);
      await tester.pumpAndSettle();
      expect(
        repository.values.containsKey('settlement-period-transaction'),
        isFalse,
      );
      expect(find.byType(PaymentSettlementDetailPage), findsOneWidget);
      expect(find.byType(TransactionRow), findsNothing);
      expect(find.text('Updated again'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('desktop-payment-settlement-close')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-transaction-detail-panel')),
        findsNothing,
      );
      expect(settlementRow, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop edit warning stays pinned when settlement results are scrolled',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1600, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final finance = services<FinanceServices>();
      final source = PaymentSource(
        id: PaymentSourceId('scrolled-settlements-source'),
        name: 'Scrolled card',
        type: PaymentSourceType.card,
      );
      await finance.savePaymentSource(source);
      await paymentSettlements.save(
        PaymentSettlement(
          id: PaymentSettlementId('scrolled-settlement-anchor'),
          paymentSourceId: source.id,
          payment: Money(
            amount: DecimalValue.parse('25.00'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-11-09',
          periodStart: '2026-11-01',
          periodEnd: '2026-11-09',
          status: PaymentSettlementStatus.open,
          createdAt: DateTime.utc(2026, 11, 9),
          updatedAt: DateTime.utc(2026, 11, 9),
        ),
      );
      // Make the left results pane scroll well beyond the overview/header.
      for (var index = 0; index < 30; index++) {
        await paymentSettlements.save(
          PaymentSettlement(
            id: PaymentSettlementId('scrolled-settlement-$index'),
            paymentSourceId: source.id,
            payment: Money(
              amount: DecimalValue.parse('10.00'),
              currency: CurrencyCode('USD'),
            ),
            paymentDate: '2026-10-10',
            periodStart: '2026-10-01',
            periodEnd: '2026-10-10',
            status: PaymentSettlementStatus.open,
            createdAt: DateTime.utc(2026, 10, 10),
            updatedAt: DateTime.utc(2026, 10, 10),
          ),
        );
      }
      final created = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'scrolled-settlement-transaction',
          provenanceId: 'scrolled-settlement-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 11, 4, 12)),
          money: Money(
            amount: DecimalValue.parse('25.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          transactionDate: '2026-11-04',
          description: 'Scrolled settlement purchase',
          paymentSourceId: source.id.value,
        ),
      );
      expect(created, isA<ApplicationSuccess<TransactionDto>>());
      paymentSettlements.periodTransactions.add(
        repository.values['scrolled-settlement-transaction']!,
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey(
            'desktop-payment-settlement-scrolled-settlement-anchor',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TransactionRow));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('transaction-detail-edit-button')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('transaction-description-field')),
        'Unsaved scrolled edit',
      );

      final resultsScroll = find.descendant(
        of: find.byKey(const ValueKey('butlerly-page-canvas')),
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomScrollView && widget.key == null,
        ),
      );
      expect(resultsScroll, findsOneWidget);
      final otherSettlement = find.byKey(
        const ValueKey('desktop-payment-settlement-scrolled-settlement-18'),
      );
      final tableRows = find.byKey(
        const ValueKey('desktop-payment-settlements-rows'),
      );
      final verticalResultsScrollable = find.descendant(
        of: tableRows,
        matching: find.byType(Scrollable),
      );
      expect(verticalResultsScrollable, findsOneWidget);
      await tester.scrollUntilVisible(
        otherSettlement,
        180,
        scrollable: verticalResultsScrollable,
      );
      await tester.pumpAndSettle();
      final scrollPosition = tester
          .state<ScrollableState>(verticalResultsScrollable)
          .position;
      expect(scrollPosition.pixels, greaterThan(200));

      await tester.tap(otherSettlement);
      await tester.pumpAndSettle();
      final warning = find.byKey(
        const ValueKey('desktop-settlement-edit-warning'),
      );
      expect(warning, findsOneWidget);
      final resultsBounds = tester.getRect(resultsScroll);
      final warningBounds = tester.getRect(warning);
      expect(warningBounds.top, greaterThanOrEqualTo(resultsBounds.top));
      expect(warningBounds.bottom, lessThan(resultsBounds.bottom));
      expect(find.text('Unsaved scrolled edit'), findsOneWidget);

      // Scrolling more does not move the pinned feedback out of the viewport.
      final previousOffset = scrollPosition.pixels;
      await tester.drag(tableRows, const Offset(0, 110));
      await tester.pumpAndSettle();
      expect(scrollPosition.pixels, lessThan(previousOffset));
      expect(scrollPosition.pixels, greaterThan(0));
      expect(tester.getTopLeft(warning).dy, closeTo(warningBounds.top, 1));

      await _submitEmbeddedTransactionSave(tester);
      expect(warning, findsNothing);
      expect(
        find.byKey(const ValueKey('transaction-detail-summary-card')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> seedSettlementViewport(int count) async {
    final source = PaymentSource(
      id: PaymentSourceId('viewport-card'),
      name: 'Viewport card',
      type: PaymentSourceType.card,
    );
    await paymentSources.save(source);
    final date = DateTime.utc(2026, 11, 1);
    for (var index = 0; index < count; index++) {
      await paymentSettlements.save(
        PaymentSettlement(
          id: PaymentSettlementId('viewport-$index'),
          paymentSourceId: source.id,
          payment: Money(
            amount: DecimalValue.parse('19.013'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-11-01',
          periodStart: '2026-10-02',
          periodEnd: '2026-11-01',
          status: PaymentSettlementStatus.open,
          createdAt: date,
          updatedAt: date,
        ),
      );
    }
  }

  testWidgets('Settlement keyboard scrolls the page when short rows fit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1500, 280);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await seedSettlementViewport(2);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
    );
    await tester.pumpAndSettle();
    final row = tester.element(find.text('Viewport card').first);
    final inner = Scrollable.of(row, axis: Axis.vertical);
    final outer = Scrollable.of(inner.context, axis: Axis.vertical).position;
    expect(inner.position.maxScrollExtent, 0);
    expect(outer.maxScrollExtent, greaterThan(0));
    final focus = Focus.of(row, createDependency: false);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(outer.pixels, greaterThan(0));
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(outer.pixels, 0);
  });

  testWidgets(
    'Pulling a wide settlement row reloads the history',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 880);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await seedSettlementViewport(100);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
      );
      await tester.pumpAndSettle();
      final row = find.byKey(
        const ValueKey('desktop-payment-settlement-viewport-0'),
      );
      expect(row, findsOneWidget);
      final listCalls = paymentSettlements.listCalls;
      await tester.drag(row, const Offset(0, 450));
      await tester.pumpAndSettle();
      expect(paymentSettlements.listCalls, listCalls + 1);
      expect(row, findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'Settlement touch scrolling reaches the final row with detail open',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1300, 420);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await seedSettlementViewport(20);
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
      );
      await tester.pumpAndSettle();
      Finder row(int index) =>
          find.byKey(ValueKey('desktop-payment-settlement-viewport-$index'));
      await tester.tap(row(0).hitTestable(at: Alignment.centerLeft));
      await tester.pumpAndSettle();

      final detail = find.byKey(
        const ValueKey('desktop-settlement-detail-viewport-0'),
      );
      final detailScroll = tester
          .state<ScrollableState>(
            find.descendant(of: detail, matching: find.byType(Scrollable)),
          )
          .position;
      expect(detailScroll.maxScrollExtent, greaterThan(0));
      detailScroll.jumpTo(detailScroll.maxScrollExtent / 2);
      final detailOffset = detailScroll.pixels;

      final rows = find.byKey(
        const ValueKey('desktop-payment-settlements-rows'),
      );
      final inner = tester.state<ScrollableState>(
        find.descendant(of: rows, matching: find.byType(Scrollable)),
      );
      final page = Scrollable.of(inner.context, axis: Axis.vertical).position;
      // Reveal the top of the table while leaving its lower portion clipped.
      page.jumpTo(page.pixels + tester.getTopLeft(rows).dy - 290);
      await tester.pumpAndSettle();
      final pageOffset = page.pixels;
      inner.position.jumpTo(inner.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final finalRow = row(19).hitTestable(at: Alignment.centerLeft);
      expect(finalRow, findsNothing);
      for (
        var attempt = 0;
        attempt < 3 && finalRow.evaluate().isEmpty;
        attempt++
      ) {
        final rowsBounds = tester.getRect(rows);
        await tester.dragFrom(
          rowsBounds.topLeft + const Offset(34, 30),
          const Offset(0, -220),
        );
        await tester.pumpAndSettle();
      }
      expect(page.pixels, greaterThan(pageOffset));
      expect(detailScroll.pixels, detailOffset);
      expect(finalRow, findsOneWidget);
      await tester.tap(finalRow);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('desktop-settlement-detail-viewport-19')),
        findsOneWidget,
      );
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets('Settlement refresh reveals a reordered keyboard focus target', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 550);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await seedSettlementViewport(40);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(
      const ValueKey('desktop-payment-settlement-viewport-0'),
    );
    final label = find.descendant(
      of: row,
      matching: find.text('Viewport card'),
    );
    final rowContext = tester.element(label);
    final position = Scrollable.of(rowContext, axis: Axis.vertical).position;
    Focus.of(rowContext, createDependency: false).requestFocus();
    await tester.pump();
    expect(row.hitTestable(), findsOneWidget);
    expect(position.pixels, 0);

    final focused = paymentSettlements.values.remove('viewport-0')!;
    final others = paymentSettlements.values.entries.toList();
    paymentSettlements.values
      ..clear()
      ..addEntries(others.take(6))
      ..[focused.id.value] = focused
      ..addEntries(others.skip(6));
    notifyPaymentSettlementChanged();
    await tester.pumpAndSettle();
    expect(row.hitTestable(), findsOneWidget);
    expect(position.pixels, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-settlement-detail-viewport-0')),
      findsOneWidget,
    );
  });

  testWidgets('Settlement refresh keeps the viewport when focus is offscreen', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 880);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await seedSettlementViewport(40);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(
      const ValueKey('desktop-payment-settlement-viewport-0'),
    );
    final label = find.descendant(
      of: row,
      matching: find.text('Viewport card'),
    );
    final context = tester.element(label);
    final position = Scrollable.of(context, axis: Axis.vertical).position;
    final focus = Focus.of(context, createDependency: false);
    focus.requestFocus();
    await tester.pump();
    position.jumpTo(120);
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);
    expect(row.hitTestable(), findsNothing);

    notifyPaymentSettlementChanged();
    await tester.pumpAndSettle();
    expect(position.pixels, 120);
    expect(row.hitTestable(), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-settlement-detail-viewport-0')),
      findsNothing,
    );
  });

  testWidgets('Desktop mounts bounded rows and opens a distant settlement', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 880);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final source = PaymentSource(
      id: PaymentSourceId('long-history-card'),
      name: 'History card',
      type: PaymentSourceType.card,
    );
    await paymentSources.save(source);
    final payment = Money(
      amount: DecimalValue.parse('19.013'),
      currency: CurrencyCode('USD'),
    );
    final date = DateTime.utc(2026, 11, 1);
    for (var index = 0; index < 5000; index++) {
      await paymentSettlements.save(
        PaymentSettlement(
          id: PaymentSettlementId('history-$index'),
          paymentSourceId: index.isEven
              ? source.id
              : PaymentSourceId('missing-historical-credit-card-source-$index'),
          payment: payment,
          paymentDate: '2026-11-01',
          periodStart: '2026-10-02',
          periodEnd: '2026-11-01',
          status: PaymentSettlementStatus.open,
          createdAt: date,
          updatedAt: date,
        ),
      );
    }

    Finder row(int index) =>
        find.byKey(ValueKey('desktop-payment-settlement-history-$index'));
    bool isSettlementRow(Widget widget) =>
        widget is InkWell &&
        widget.key is ValueKey<String> &&
        (widget.key as ValueKey<String>).value.startsWith(
          'desktop-payment-settlement-history-',
        );
    final mountedRows = find.byWidgetPredicate(isSettlementRow);
    for (final (locale, theme) in [
      (const Locale('en'), AppTheme.light),
      (const Locale('zh', 'CN'), AppTheme.navy),
      (const Locale('es'), AppTheme.dark),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          theme: theme,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.5)),
              child: const Scaffold(body: PaymentSettlementsPage()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final missingLabel = AppLocalizations(locale).text(
        'missingSettlementSource',
        {'id': 'missing-historical-credit-card-source-1'},
      );
      expect(find.text(missingLabel), findsOneWidget);
      expect(row(0), findsOneWidget);
      expect(
        tester.getSize(row(1)).height,
        greaterThan(tester.getSize(row(0)).height),
      );
      expect(row(4999), findsNothing);
      expect(mountedRows.evaluate().length, lessThan(50));
      expect(tester.takeException(), isNull);
    }
    expect(paymentSettlements.transactionListCalls, 0);

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey('desktop-payment-settlements-rows')),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    final firstSource = find.descendant(
      of: row(0),
      matching: find.text('History card'),
    );
    final firstRowFocus = Focus.of(
      tester.element(firstSource),
      createDependency: false,
    );
    for (
      var attempt = 0;
      attempt < 5 && !firstRowFocus.hasPrimaryFocus;
      attempt++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(firstRowFocus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));

    var newRows = 0;
    final previousRebuild = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previousRebuild?.call(element, builtOnce);
      if (!builtOnce && isSettlementRow(element.widget)) newRows++;
    };
    try {
      // The estimated scroll extent can refine after a single thumb jump.
      for (
        var attempt = 0;
        attempt < 5 && row(4999).evaluate().isEmpty;
        attempt++
      ) {
        newRows = 0;
        position.jumpTo(position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(newRows, inInclusiveRange(1, 50));
      }
    } finally {
      debugOnRebuildDirtyWidget = previousRebuild;
    }
    expect(row(4999), findsOneWidget);
    expect(row(4998), findsOneWidget);
    expect(mountedRows.evaluate().length, lessThan(50));
    expect(paymentSettlements.transactionListCalls, 0);

    await tester.ensureVisible(row(4999));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    await tester.pump();
    expect(
      tester
          .getSemantics(row(4999))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
    final finalSource = find.descendant(
      of: row(4999),
      matching: find.textContaining(
        'missing-historical-credit-card-source-4999',
      ),
    );
    Focus.of(
      tester.element(finalSource),
      createDependency: false,
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-settlement-detail-history-4999')),
      findsOneWidget,
    );
    expect(row(4999), findsOneWidget);
    expect(paymentSettlements.transactionListCalls, 1);

    final table = find.byKey(
      const ValueKey('desktop-payment-settlements-table'),
    );
    final horizontal = tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byKey(
              const ValueKey('desktop-payment-settlements-horizontal-scroll'),
            ),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.right,
            ),
          ),
        )
        .position;
    expect(horizontal.maxScrollExtent, greaterThan(0));
    final amountHeading = find.descendant(
      of: table,
      matching: find.text(
        const AppLocalizations(Locale('es')).text('paymentSettlementAmount'),
      ),
    );
    final amountCell = find.descendant(
      of: row(4999),
      matching: find.textContaining('USD'),
    );
    expect(
      tester.getTopLeft(amountHeading).dx,
      tester.getTopLeft(amountCell).dx,
    );
    final beforeHorizontalScroll = tester.getTopLeft(amountCell).dx;
    final beforeVerticalScroll = position.pixels;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(horizontal.pixels, greaterThan(0));
    expect(tester.getTopLeft(amountCell).dx, lessThan(beforeHorizontalScroll));
    expect(
      tester.getTopLeft(amountHeading).dx,
      tester.getTopLeft(amountCell).dx,
    );
    expect(position.pixels, beforeVerticalScroll);

    final beforeRefreshHorizontal = horizontal.pixels;
    notifyPaymentSourceChanged();
    await tester.pumpAndSettle();
    expect(horizontal.pixels, beforeRefreshHorizontal);
    expect(position.pixels, beforeVerticalScroll);

    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(beforeVerticalScroll));
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pumpAndSettle();
    expect(position.pixels, beforeVerticalScroll);

    await tester.tap(
      find.byKey(const ValueKey('desktop-payment-settlement-close')),
    );
    await tester.pumpAndSettle();
    expect(row(4999), findsOneWidget);
    expect(position.pixels, beforeVerticalScroll);

    Focus.of(
      tester.element(finalSource),
      createDependency: false,
    ).requestFocus();
    await tester.pump();
    notifyPaymentSourceChanged();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ButlerlyLoadingState), findsOneWidget);
    expect(row(4999), findsNothing);
    await tester.pumpAndSettle();
    expect(row(4999), findsOneWidget);
    expect(tester.state<ScrollableState>(scrollable).position, same(position));
    expect(position.pixels, beforeVerticalScroll);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final detail = find.byKey(
      const ValueKey('desktop-settlement-detail-history-4999'),
    );
    expect(detail, findsOneWidget);
    final restored = paymentSettlements.values['history-0']!;
    paymentSettlements.values.clear();
    await paymentSettlements.save(restored);
    notifyWorkspaceRestored();
    await tester.pump();
    await tester.pump();
    expect(find.byType(ButlerlyLoadingState), findsOneWidget);
    expect(row(4999).hitTestable(), findsNothing);
    expect(detail, findsNothing);
    await tester.pumpAndSettle();
    expect(row(0), findsOneWidget);
    expect(row(4999), findsNothing);

    paymentSettlements.values.clear();
    notifyWorkspaceRestored();
    await tester.pumpAndSettle();
    expect(detail, findsNothing);
    expect(table, findsNothing);
    expect(
      find.text(
        const AppLocalizations(Locale('es')).text('noPaymentSettlements'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Archived card retains its historical settlements without enabling Add',
    (tester) async {
      final finance = services<FinanceServices>();
      final archived = PaymentSource(
        id: PaymentSourceId('archived-card-source'),
        name: 'Archived credit card',
        type: PaymentSourceType.card,
        status: PaymentSourceStatus.archived,
      );
      await finance.savePaymentSource(archived);
      await paymentSettlements.save(
        PaymentSettlement(
          id: PaymentSettlementId('historical-settlement'),
          paymentSourceId: archived.id,
          payment: Money(
            amount: DecimalValue.parse('125.00'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-04-15',
          periodStart: '2026-03-16',
          periodEnd: '2026-04-15',
          status: PaymentSettlementStatus.reconciled,
          createdAt: DateTime.utc(2026, 4, 15),
          updatedAt: DateTime.utc(2026, 4, 15),
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Archived credit card (Archived)'), findsOneWidget);
      expect(
        find.text(
          'Add or reactivate a credit card in Payment Sources to create a settlement.',
        ),
        findsOneWidget,
      );
      expect(find.text('USD 125.00'), findsOneWidget);
      expect(find.text('Apr 15, 2026'), findsOneWidget);
      expect(
        tester
            .widget<ButlerlyHeaderAddButton>(
              find.byType(ButlerlyHeaderAddButton),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final succeeds in [true, false]) {
    testWidgets(
      'delayed settlement mutation after route disposal refreshes retained Tools only on success=$succeeds',
      (tester) async {
        final finance = services<FinanceServices>();
        final source = PaymentSource(
          id: PaymentSourceId('delayed-card'),
          name: 'Delayed card',
          type: PaymentSourceType.card,
        );
        await finance.savePaymentSource(source);
        final settlement = PaymentSettlement(
          id: PaymentSettlementId('delayed-settlement'),
          paymentSourceId: source.id,
          payment: Money(
            amount: DecimalValue.parse('75.25'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-09-15',
          periodStart: '2026-08-16',
          periodEnd: '2026-09-15',
          status: PaymentSettlementStatus.open,
          createdAt: DateTime.utc(2026, 9, 15),
          updatedAt: DateTime.utc(2026, 9, 15),
        );
        await paymentSettlements.save(settlement);
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: ToolsPage()),
          ),
        );
        await tester.pumpAndSettle();
        final retainedTools = tester.state(find.byType(ToolsPage));
        expect(find.text('1 settlement needs attention'), findsOneWidget);
        unawaited(
          navigator.currentState!.push<void>(
            MaterialPageRoute(
              builder: (_) => PaymentSettlementDetailPage(
                finance: finance,
                settlementId: settlement.id.value,
                sourceNames: {source.id.value: source.name},
                sources: [source],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final detailState = tester.state(
          find.byType(PaymentSettlementDetailPage),
        );
        final completion = Completer<void>();
        paymentSettlements.saveCompletion = completion.future;
        final revision = paymentSettlementChanges.value;
        await tester.tap(find.byIcon(Icons.more_vert));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark as reconciled'));
        await tester.pumpAndSettle();
        expect(paymentSettlements.savePending, isTrue);
        expect(
          paymentSettlements.values[settlement.id.value]!.status,
          PaymentSettlementStatus.open,
        );
        expect(paymentSettlementChanges.value, revision);

        navigator.currentState!.pop();
        await tester.pumpAndSettle();
        expect(detailState.mounted, isFalse);
        expect(tester.state(find.byType(ToolsPage)), same(retainedTools));
        expect(find.text('1 settlement needs attention'), findsOneWidget);

        if (succeeds) {
          completion.complete();
        } else {
          completion.completeError(
            const RepositoryException(
              RepositoryFailureCode.unavailable,
              'save payment settlement',
            ),
          );
        }
        await tester.pumpAndSettle();
        expect(
          paymentSettlements.values[settlement.id.value]!.status,
          succeeds
              ? PaymentSettlementStatus.reconciled
              : PaymentSettlementStatus.open,
        );
        expect(paymentSettlementChanges.value, revision + (succeeds ? 1 : 0));
        expect(tester.state(find.byType(ToolsPage)), same(retainedTools));
        expect(
          find.text('1 settlement needs attention'),
          succeeds ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Compact settlement detail refreshes the list on Back after edit and status changes',
    (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final source = PaymentSource(
        id: PaymentSourceId('compact-card'),
        name: 'Compact card',
        type: PaymentSourceType.card,
      );
      await services<FinanceServices>().savePaymentSource(source);
      await paymentSettlements.save(
        PaymentSettlement(
          id: PaymentSettlementId('compact-settlement'),
          paymentSourceId: source.id,
          payment: Money(
            amount: DecimalValue.parse('75.25'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-09-15',
          periodStart: '2026-08-16',
          periodEnd: '2026-09-15',
          status: PaymentSettlementStatus.open,
          createdAt: DateTime.utc(2026, 9, 15),
          updatedAt: DateTime.utc(2026, 9, 15),
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Compact card'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit payment settlement'));
      await tester.pumpAndSettle();
      final sheet = find.byType(ButlerlySheet);
      expect(sheet, findsOneWidget);
      final fields = find.descendant(
        of: sheet,
        matching: find.byType(TextFormField),
      );
      final amount = fields.first;
      final balance = fields.at(5);
      final save = find.widgetWithText(FilledButton, 'Save');
      await tester.enterText(amount, '1e3');
      await tester.ensureVisible(balance);
      await tester.enterText(balance, 'NaN');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Amount: Enter a valid amount.'), findsOneWidget);
      expect(
        find.text('Statement balance (optional): Enter a valid amount.'),
        findsOneWidget,
      );
      expect(sheet, findsOneWidget);
      expect(
        paymentSettlements.values['compact-settlement']!.payment.amount,
        DecimalValue.parse('75.25'),
      );
      await tester.enterText(amount, '80.25');
      await tester.ensureVisible(balance);
      await tester.enterText(balance, '100.01234567890123456789');
      final failedWrite = Completer<void>();
      paymentSettlements.saveCompletion = failedWrite.future;
      final revision = paymentSettlementChanges.value;
      final saveCalls = paymentSettlements.saveCalls;
      await tester.tap(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Saving…'), findsOneWidget);
      expect(paymentSettlements.saveCalls, saveCalls + 1);
      failedWrite.completeError(
        const RepositoryException(
          RepositoryFailureCode.unavailable,
          'save payment settlement',
        ),
      );
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      expect(find.text('80.25'), findsOneWidget);
      expect(find.text('100.01234567890123456789'), findsOneWidget);
      expect(paymentSettlementChanges.value, revision);
      paymentSettlements.saveCompletion = null;
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(paymentSettlementChanges.value, revision + 1);
      expect(
        paymentSettlements
            .values['compact-settlement']!
            .statementBalance!
            .amount,
        DecimalValue.parse('100.01234567890123456789'),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('USD 80.25'), findsOneWidget);
      expect(find.text('USD 75.25'), findsNothing);
      expect(
        paymentSettlements.values['compact-settlement']!.paymentSourceId,
        source.id,
      );

      await tester.tap(find.text('Compact card'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as reconciled'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Reconciled'), findsOneWidget);

      await tester.tap(find.text('Compact card'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Reconciled'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Settlement list can retry a failed load more than once', (
    tester,
  ) async {
    paymentSettlements.failList = true;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
    );
    await tester.pumpAndSettle();
    final retry = find.widgetWithText(FilledButton, 'Try again');
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(retry, findsOneWidget);
    expect(tester.takeException(), isNull);

    paymentSettlements.failList = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('No active credit cards'), findsOneWidget);
    expect(find.byType(PaymentSourcesPage), findsNothing);
  });

  testWidgets('payment settlement rows show source, amount, and payment date', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    final source = PaymentSource(
      id: PaymentSourceId('source-card'),
      name: 'Travel card',
      type: PaymentSourceType.card,
    );
    await finance.savePaymentSource(source);
    await paymentSettlements.save(
      PaymentSettlement(
        id: PaymentSettlementId('settlement-card'),
        paymentSourceId: source.id,
        payment: Money(
          amount: DecimalValue.parse('75.25'),
          currency: CurrencyCode('USD'),
        ),
        paymentDate: '2026-09-15',
        periodStart: '2026-08-16',
        periodEnd: '2026-09-15',
        status: PaymentSettlementStatus.open,
        createdAt: DateTime.utc(2026, 9, 15),
        updatedAt: DateTime.utc(2026, 9, 15),
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PaymentSettlementsPage())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Travel card'), findsOneWidget);
    expect(find.text('USD 75.25'), findsOneWidget);
    expect(find.text('Sep 15, 2026'), findsOneWidget);
    expect(find.text('2026-08-16 – 2026-09-15'), findsOneWidget);

    paymentSources.values.remove(source.id.value);
    notifyWorkspaceRestored();
    await tester.pumpAndSettle();

    expect(find.text('Travel card'), findsNothing);
    const missingSource = 'Payment source unavailable (source-card)';
    await tester.tap(find.text(missingSource));
    await tester.pumpAndSettle();
    expect(find.byType(PaymentSettlementDetailPage), findsOneWidget);
    expect(find.text(missingSource), findsOneWidget);
    await tester.tap(find.byTooltip('Edit payment settlement'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ButlerlySheet),
        matching: find.text(missingSource),
      ),
      findsOneWidget,
    );
    expect(
      paymentSettlements.values['settlement-card']!.paymentSourceId,
      source.id,
    );
  });

  testWidgets('Mounted settlements refresh after source status changes', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.savePaymentSource(
      PaymentSource(
        id: PaymentSourceId('source-card'),
        name: 'Travel card',
        type: PaymentSourceType.card,
      ),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: PaymentSettlementsPage()),
      ),
    );
    await tester.pumpAndSettle();
    final add = find.byKey(const ValueKey('payment-settlements-add'));
    expect(tester.widget<IconButton>(add).onPressed, isNotNull);

    Future<void> changeStatus(String tooltip) async {
      final before = paymentSourceChanges.value;
      navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const PaymentSourcesPage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(paymentSourceChanges.value, before + 1);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
    }

    await changeStatus('Archive payment source');
    expect(tester.widget<IconButton>(add).onPressed, isNull);
    await changeStatus('Reactivate payment source');
    expect(tester.widget<IconButton>(add).onPressed, isNotNull);
  });

  testWidgets(
    'Master Data uses tight header spacing and exposes add in header',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MasterDataPage()));
      await tester.pumpAndSettle();

      final page = tester.widget<ButlerlyPage>(find.byType(ButlerlyPage));
      expect(page.pinnedSpacing, same(ButlerlyPinnedPageSpacing.tightHeader));
      expect(page.actions, hasLength(1));
      final headerAction = page.actions.single;
      expect(headerAction, isA<ButlerlyHeaderAddButton>());
      final headerPadding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byType(ButlerlyHeaderAddButton),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(headerPadding.padding, EdgeInsetsDirectional.zero);

      final addButton = find.byKey(const ValueKey('master-data-add'));
      final addIcon = find.descendant(
        of: addButton,
        matching: find.byIcon(Icons.add),
      );
      expect(addIcon, findsOneWidget);
      final iconButton = tester.widget<IconButton>(addButton);
      expect(
        iconButton.style?.backgroundColor?.resolve({}),
        Theme.of(tester.element(addButton)).colorScheme.primary,
      );
      expect(
        iconButton.style?.foregroundColor?.resolve({}),
        Theme.of(tester.element(addButton)).colorScheme.onPrimary,
      );
    },
  );

  testWidgets('Master Data manages merchants through bottom sheets', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.saveMerchant(
      Merchant(id: MerchantId('merchant-existing'), name: 'Corner Store'),
    );

    await tester.pumpWidget(const MaterialApp(home: MasterDataPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compact-section-3')));
    await tester.pumpAndSettle();

    expect(find.text('Corner Store'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('master-data-edit-sheet')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).first, 'Corner Market');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Corner Market'), findsOneWidget);
    expect(find.text('Corner Store'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('master-data-add')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('master-data-edit-sheet')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, 'New Merchant');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('New Merchant'), findsOneWidget);

    await tester.tap(find.byTooltip('Deactivate').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Archived'), findsOneWidget);

    await tester.tap(find.byTooltip('Reactivate').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Archived'), findsNothing);
  });

  testWidgets('merchant editor manages aliases and normalization patterns', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    final merchant = Merchant(
      id: MerchantId('merchant-aliases'),
      name: 'Corner Store',
      rawName: 'CORNER STORE #12',
    );
    await finance.saveMerchant(merchant);

    await tester.pumpWidget(const MaterialApp(home: MasterDataPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compact-section-3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('Merchant aliases'), findsOneWidget);
    expect(find.text('Normalization patterns'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), 'Corner Store #12');
    await tester.enterText(find.byType(TextField).at(2), 'CORNER STORE');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      (await merchantAliases.listForMerchant(merchant.id)).single.alias,
      'Corner Store #12',
    );
    expect(
      (await merchantPatterns.listForMerchant(merchant.id)).single.pattern,
      'CORNER STORE',
    );
    final stored = await finance.listMerchants();
    expect(
      (stored as ApplicationSuccess<List<Merchant>>).value.single.rawName,
      'CORNER STORE #12',
    );
  });

  testWidgets('Master Data chooses subcategory parent in a bottom sheet', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.saveCategory(
      Category(
        id: CategoryId('category-food'),
        name: 'Food',
        origin: CategoryOrigin.user,
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: MasterDataPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('compact-section-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('master-data-add')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('master-data-edit-sheet')),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, 'Dining');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('master-data-parent-sheet')),
      findsOneWidget,
    );
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(find.text('Dining'), findsOneWidget);
    expect(find.textContaining('Food'), findsOneWidget);
  });

  testWidgets('detail presents only the canonical transaction calendar date', (
    tester,
  ) async {
    final transaction = TransactionDto(
      id: 'timezone-boundary',
      amount: '100',
      currency: 'USD',
      direction: TransactionDirection.expense.name,
      status: TransactionStatus.active.name,
      reviewState: TransactionReviewState.clear.name,
      occurredAt: DateTime.utc(2026, 8, 11, 4),
      transactionDate: '2026-08-10',
      createdAt: DateTime.utc(2026, 8, 11, 4),
      updatedAt: DateTime.utc(2026, 8, 11, 4),
      provenance: [
        ProvenanceDto(
          sourceType: ProvenanceSourceType.userEntry.name,
          capturedAt: DateTime.utc(2026, 8, 11, 4),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TransactionDetailPage(
          finance: services<FinanceServices>(),
          transaction: transaction,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aug 10, 2026'), findsNWidgets(2));
    expect(find.text('Aug 11, 2026'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transaction-detail-record-card')),
      200,
      scrollable: _transactionDetailScrollable(tester),
    );
    await tester.pumpAndSettle();
    expect(find.text('Entered locally'), findsOneWidget);
  });

  testWidgets('detail resolves master-data IDs to user-visible names', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.saveMerchant(
      Merchant(id: MerchantId('merchant-123456'), name: 'Corner Market'),
    );
    await finance.saveCategory(
      Category(
        id: CategoryId('category-123456'),
        name: 'Groceries',
        origin: CategoryOrigin.user,
      ),
    );
    await finance.saveTag(Tag(id: TagId('tag-123456'), name: 'Weekly'));

    final transaction = TransactionDto(
      id: 'organized',
      amount: '24.50',
      currency: 'USD',
      direction: TransactionDirection.expense.name,
      status: TransactionStatus.active.name,
      reviewState: TransactionReviewState.clear.name,
      merchantId: 'merchant-123456',
      categoryId: 'category-123456',
      tagIds: const ['tag-123456'],
      transactionDate: '2026-08-10',
      createdAt: DateTime.utc(2026, 8, 10),
      updatedAt: DateTime.utc(2026, 8, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TransactionDetailPage(finance: finance, transaction: transaction),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Corner Market').evaluate().isNotEmpty, isTrue);
    expect(find.text('Groceries').evaluate().isNotEmpty, isTrue);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transaction-detail-notes-card')),
      200,
      scrollable: _transactionDetailScrollable(tester),
    );
    await tester.pumpAndSettle();
    expect(find.text('Weekly').evaluate().isNotEmpty, isTrue);
    expect(find.text('merchant-123456'), findsNothing);
    expect(find.text('category-123456'), findsNothing);
    expect(find.text('tag-123456'), findsNothing);
  });

  testWidgets('editor presents the canonical transaction calendar date', (
    tester,
  ) async {
    final transaction = TransactionDto(
      id: 'timezone-boundary-editor',
      amount: '100',
      currency: 'USD',
      direction: TransactionDirection.expense.name,
      status: TransactionStatus.active.name,
      reviewState: TransactionReviewState.clear.name,
      occurredAt: DateTime.utc(2026, 8, 11, 4),
      transactionDate: '2026-08-10',
      createdAt: DateTime.utc(2026, 8, 11, 4),
      updatedAt: DateTime.utc(2026, 8, 11, 4),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: TransactionEditorPage(
          finance: services<FinanceServices>(),
          existing: transaction,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editorScroll = _transactionEditorScrollable(tester);
    await tester.drag(editorScroll, const Offset(0, -640));
    await tester.pumpAndSettle();
    final dateCard = find.byKey(const ValueKey('transaction-editor-date-card'));
    expect(dateCard, findsOneWidget);
    expect(
      find.descendant(
        of: dateCard,
        matching: find.text('Monday, August 10, 2026'),
      ),
      findsOneWidget,
    );
    expect(find.text('2026-08-11'), findsNothing);
  });

  testWidgets(
    'transaction detail uses Simplified Chinese and hides extra actions',
    (tester) async {
      final finance = services<FinanceServices>();
      await finance.createTransaction(
        CreateTransactionCommand(
          id: 'localized-detail',
          provenanceId: 'localized-detail-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 8, 10)),
          money: Money(
            amount: DecimalValue.parse('8.50'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'Source name',
        ),
      );
      final result = await finance.getTransaction('localized-detail');
      final transaction = (result as ApplicationSuccess<TransactionDto>).value;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: TransactionDetailPage(
            finance: finance,
            transaction: transaction,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('交易详情'), findsWidgets);
      expect(find.text('方向'), findsOneWidget);
      expect(find.text('支出'), findsOneWidget);
      expect(find.text('Transaction detail'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('整理交易'), findsNothing);
      expect(find.text('指定付款来源'), findsNothing);
    },
  );

  testWidgets('add editor saves and returns a typed saved result', (
    tester,
  ) async {
    TransactionEditorResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: _EditorHarness(
          finance: services<FinanceServices>(),
          onResult: (value) => result = value,
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '12.50');
    await tester.scrollUntilVisible(
      find.text('Save locally'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();
    expect(result, isA<TransactionEditorSaved>());
    expect(repository.values, hasLength(1));
  });

  testWidgets('add and edit editors use card-based form sections', (
    tester,
  ) async {
    await _openEditorForTest(tester);

    final financialCard = find.byKey(
      const ValueKey('transaction-editor-financial-card'),
    );
    final descriptionCard = find.byKey(
      const ValueKey('transaction-editor-description-card'),
    );
    final organizationCard = find.byKey(
      const ValueKey('transaction-editor-organization-card'),
    );
    final dateCard = find.byKey(const ValueKey('transaction-editor-date-card'));
    expect(financialCard, findsOneWidget);
    expect(
      find.descendant(
        of: financialCard,
        matching: find.byKey(const ValueKey('transaction-amount-field')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: financialCard,
        matching: find.byType(ButlerlyDirectionSelector),
      ),
      findsOneWidget,
    );

    await _scrollEditorToMasterData(tester);
    expect(organizationCard, findsOneWidget);
    expect(
      find.descendant(
        of: organizationCard,
        matching: find.byType(ButlerlyMerchantSelector),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: organizationCard,
        matching: find.byType(ButlerlyPaymentSourceSelector),
      ),
      findsOneWidget,
    );
    expect(dateCard, findsOneWidget);

    await tester.scrollUntilVisible(
      descriptionCard,
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(descriptionCard, findsOneWidget);
    expect(
      find.descendant(
        of: descriptionCard,
        matching: find.byKey(const ValueKey('transaction-description-field')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: descriptionCard,
        matching: find.byType(ButlerlyTagPicker),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await repository.save(_editorTransaction('card-edit'));
    await _openEditorForTest(
      tester,
      existing: TransactionDto.fromDomain(repository.values['card-edit']!),
    );

    expect(find.text('Edit transaction'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transaction-editor-financial-card')),
      findsOneWidget,
    );
    await _scrollEditorToMasterData(tester);
    expect(
      find.byKey(const ValueKey('transaction-editor-organization-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('transaction-editor-date-card')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('transaction-editor-description-card')),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.byKey(const ValueKey('transaction-editor-description-card')),
      findsOneWidget,
    );
  });

  testWidgets(
    'add editor keeps its save action fixed while the form scrolls on a narrow phone',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      TransactionEditorResult? result;
      await _openEditorForTest(tester, onResult: (value) => result = value);

      final editorList = find.byKey(const ValueKey('transaction-editor-list'));
      final saveButton = find.byKey(const ValueKey('transaction-save-locally'));
      expect(editorList, findsOneWidget);
      expect(saveButton, findsOneWidget);
      expect(
        find.descendant(of: editorList, matching: saveButton),
        findsNothing,
      );
      expect(
        find.ancestor(of: saveButton, matching: find.byType(SafeArea)),
        findsOneWidget,
      );

      final initialSaveButtonRect = tester.getRect(saveButton);
      final amountField = find.byKey(
        const ValueKey('transaction-amount-field'),
      );
      await tester.enterText(amountField, '12.50');
      await tester.showKeyboard(amountField);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(saveButton, findsOneWidget);
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.drag(editorList, const Offset(0, -1000));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(saveButton, findsOneWidget);
      expect(tester.getRect(saveButton), initialSaveButtonRect);

      final tagPicker = find.byType(ButlerlyTagPicker);
      for (
        var attempt = 0;
        attempt < 8 && tagPicker.evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(editorList, const Offset(0, -240));
        await tester.pumpAndSettle();
      }
      expect(tagPicker, findsOneWidget);
      expect(saveButton, findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(result, isA<TransactionEditorSaved>());
    },
  );

  testWidgets(
    'add editor Use Existing returns the selected candidate without saving',
    (tester) async {
      TransactionEditorResult? result;
      await repository.save(_editorTransaction('existing-editor'));
      await tester.pumpWidget(
        MaterialApp(
          home: _EditorHarness(
            finance: services<FinanceServices>(),
            onResult: (value) => result = value,
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '25');
      await tester.scrollUntilVisible(
        find.text('Save locally'),
        160,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Save locally'));
      await tester.pumpAndSettle();
      expect(find.text('Possible duplicate'), findsOneWidget);
      await tester.tap(find.text('Use existing'));
      await tester.pumpAndSettle();
      expect(result, isA<TransactionEditorUseExisting>());
      expect(
        (result! as TransactionEditorUseExisting).transactionId,
        'existing-editor',
      );
      expect(repository.values.keys, ['existing-editor']);
    },
  );

  testWidgets('edit editor excludes itself and preserves it on Use Existing', (
    tester,
  ) async {
    final current = _editorTransaction('current-editor');
    await repository.save(current);
    await tester.pumpWidget(
      MaterialApp(
        home: _EditorHarness(
          finance: services<FinanceServices>(),
          existing: TransactionDto.fromDomain(current),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save locally'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();
    expect(find.text('Possible duplicate'), findsNothing);
    expect(repository.values['current-editor']?.money, current.money);
    expect(repository.values['current-editor']?.direction, current.direction);
  });

  testWidgets('add editor Continue Anyway creates a second transaction', (
    tester,
  ) async {
    TransactionEditorResult? result;
    final original = _editorTransaction('add-original');
    await repository.save(original);
    await _openEditorForTest(tester, onResult: (value) => result = value);
    await tester.enterText(find.byType(TextFormField).at(0), '25');
    await _tapEditorSave(tester);
    expect(find.text('Possible duplicate'), findsOneWidget);
    await tester.tap(find.text('Continue anyway'));
    await tester.pumpAndSettle();
    expect(result, isA<TransactionEditorSaved>());
    expect(repository.values, hasLength(2));
    expect(repository.values['add-original'], same(original));
    final created = repository.values.values.singleWhere(
      (transaction) => transaction.id != original.id,
    );
    expect(created.money.amount.toString(), '25');
    expect(created.money.currency, original.money.currency);
    expect(created.direction, original.direction);
    expect(created.transactionDate, original.transactionDate);
  });

  testWidgets('add editor Cancel leaves the candidate and creates nothing', (
    tester,
  ) async {
    final original = _editorTransaction('add-cancel');
    await repository.save(original);
    await _openEditorForTest(tester);
    await tester.enterText(find.byType(TextFormField).at(0), '25');
    await _tapEditorSave(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(TransactionEditorPage), findsOneWidget);
    expect(repository.values, hasLength(1));
    expect(repository.values['add-cancel'], same(original));
  });

  testWidgets(
    'add editor selects the intended duplicate among multiple candidates',
    (tester) async {
      TransactionEditorResult? result;
      await repository.save(_editorTransaction('add-first'));
      await repository.save(_editorTransaction('add-second'));
      await _openEditorForTest(tester, onResult: (value) => result = value);
      await tester.enterText(find.byType(TextFormField).at(0), '25');
      await _tapEditorSave(tester);
      expect(find.byType(RadioListTile<String>), findsNWidgets(2));
      await tester.tap(find.byType(RadioListTile<String>).at(1));
      await tester.pump();
      await tester.tap(find.text('Use existing'));
      await tester.pumpAndSettle();
      expect(
        (result! as TransactionEditorUseExisting).transactionId,
        'add-second',
      );
      expect(repository.values, hasLength(2));
    },
  );

  testWidgets(
    'edit matching another transaction offers Continue Anyway and updates only A',
    (tester) async {
      TransactionEditorResult? result;
      final a = _editorTransaction('edit-a');
      final b = _editorTransaction('edit-b');
      await repository.save(a);
      await repository.save(b);
      await _openEditorForTest(
        tester,
        existing: TransactionDto.fromDomain(a),
        onResult: (value) => result = value,
      );
      await _tapEditorSave(tester);
      expect(find.text('Possible duplicate'), findsOneWidget);
      await tester.tap(find.text('Continue anyway'));
      await tester.pumpAndSettle();
      expect(result, isA<TransactionEditorSaved>());
      expect(repository.values['edit-a'], isNot(same(a)));
      expect(repository.values['edit-b'], same(b));
      expect(repository.values['edit-a']?.money.amount.toString(), '25');
      expect(repository.values['edit-a']?.transactionDate, b.transactionDate);
      expect(repository.values['edit-a']?.money.currency, b.money.currency);
      expect(repository.values['edit-a']?.direction, b.direction);
    },
  );

  testWidgets(
    'edit matching another transaction Use Existing preserves both records',
    (tester) async {
      TransactionEditorResult? result;
      final a = _editorTransaction('edit-use-a');
      final b = _editorTransaction('edit-use-b');
      await repository.save(a);
      await repository.save(b);
      await _openEditorForTest(
        tester,
        existing: TransactionDto.fromDomain(a),
        onResult: (value) => result = value,
      );
      await _tapEditorSave(tester);
      await tester.tap(find.text('Use existing'));
      await tester.pumpAndSettle();
      expect(
        (result! as TransactionEditorUseExisting).transactionId,
        'edit-use-b',
      );
      expect(repository.values['edit-use-a'], same(a));
      expect(repository.values['edit-use-b'], same(b));
    },
  );

  testWidgets(
    'edit matching another transaction Cancel preserves both records',
    (tester) async {
      final a = _editorTransaction('edit-cancel-a');
      final b = _editorTransaction('edit-cancel-b');
      await repository.save(a);
      await repository.save(b);
      await _openEditorForTest(tester, existing: TransactionDto.fromDomain(a));
      await _tapEditorSave(tester);
      expect(find.text('Possible duplicate'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionEditorPage), findsOneWidget);
      expect(repository.values['edit-cancel-a'], same(a));
      expect(repository.values['edit-cancel-b'], same(b));
    },
  );

  testWidgets(
    'edit matching multiple transactions returns explicitly selected candidate',
    (tester) async {
      TransactionEditorResult? result;
      final a = _editorTransaction('edit-multi-a');
      final b = _editorTransaction('edit-multi-b');
      final c = _editorTransaction('edit-multi-c');
      await repository.save(a);
      await repository.save(b);
      await repository.save(c);
      await _openEditorForTest(
        tester,
        existing: TransactionDto.fromDomain(a),
        onResult: (value) => result = value,
      );
      await _tapEditorSave(tester);
      expect(find.byType(RadioListTile<String>), findsNWidgets(2));
      await tester.tap(find.byType(RadioListTile<String>).at(1));
      await tester.pump();
      await tester.tap(find.text('Use existing'));
      await tester.pumpAndSettle();
      expect(
        (result! as TransactionEditorUseExisting).transactionId,
        'edit-multi-c',
      );
      expect(repository.values['edit-multi-a'], same(a));
      expect(repository.values['edit-multi-b'], same(b));
      expect(repository.values['edit-multi-c'], same(c));
    },
  );

  testWidgets('statement duplicate evidence failures remain actionable', (
    tester,
  ) async {
    final existing = _editorTransaction('statement-evidence-existing');
    await repository.save(existing);
    final now = DateTime.utc(2026, 9, 1);
    await duplicateGroups.save(
      DuplicateCandidateGroup(
        id: 'duplicate:2026-09-01|25|USD|expense',
        transactionIds: [existing.id],
        duplicateKey: DuplicateTransactionKey(
          transactionDate: '2026-09-01',
          amount: DecimalValue.parse('25'),
          currency: 'USD',
          direction: TransactionDirection.expense.name,
        ),
        status: DuplicateCandidateGroupStatus.unresolved,
        integrityIssue: const DuplicateCandidateGroupIntegrityIssue(
          code: 'malformedStatementDuplicateEvidence',
          detail: 'statement evidence is unavailable',
        ),
        statementRows: const [
          DuplicateCandidateStatementRow(
            statementId: 'missing-statement',
            rowId: 'missing-row',
          ),
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReviewPage(showPossibleDuplicates: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repair duplicate review'), findsOneWidget);
    expect(
      find.textContaining('Your existing local data was not changed.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Repair duplicate review'));
    await tester.pumpAndSettle();
    expect(find.text('No possible duplicates found'), findsOneWidget);
    expect(await duplicateGroups.list(), isEmpty);
  });

  testWidgets('malformed statement duplicate evidence can be repaired', (
    tester,
  ) async {
    final existing = _editorTransaction('statement-repair-existing');
    await repository.save(existing);
    final now = existing.createdAt;
    await duplicateGroups.save(
      DuplicateCandidateGroup(
        id: 'duplicate:malformed-statement-review',
        transactionIds: [existing.id],
        duplicateKey: DuplicateTransactionKey(
          transactionDate: existing.transactionDate!,
          amount: existing.money.amount,
          currency: existing.money.currency.value,
          direction: existing.direction.name,
        ),
        status: DuplicateCandidateGroupStatus.unresolved,
        integrityIssue: const DuplicateCandidateGroupIntegrityIssue(
          code: 'malformedStatementDuplicateEvidence',
          detail: 'invalid persisted statement evidence',
        ),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReviewPage(showPossibleDuplicates: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repair duplicate review'), findsOneWidget);
    await tester.tap(find.text('Repair duplicate review'));
    await tester.pumpAndSettle();
    expect(find.text('No possible duplicates found'), findsOneWidget);
    expect(await duplicateGroups.list(), isEmpty);
  });

  testWidgets('incomplete transaction duplicate groups remain repairable', (
    tester,
  ) async {
    final existing = _editorTransaction('incomplete-duplicate-review');
    await repository.save(existing);
    final now = existing.createdAt;
    await duplicateGroups.save(
      DuplicateCandidateGroup(
        id: 'duplicate:incomplete-transaction-review',
        transactionIds: [existing.id],
        duplicateKey: DuplicateTransactionKey(
          transactionDate: existing.transactionDate!,
          amount: existing.money.amount,
          currency: existing.money.currency.value,
          direction: existing.direction.name,
        ),
        status: DuplicateCandidateGroupStatus.unresolved,
        integrityIssue: const DuplicateCandidateGroupIntegrityIssue(
          code: 'incompleteDuplicateGroup',
          detail: 'one duplicate member was permanently removed',
        ),
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ReviewPage(showPossibleDuplicates: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Repair duplicate group'), findsOneWidget);
    expect(find.textContaining('saved duplicate group'), findsOneWidget);
    await tester.tap(find.text('Repair duplicate group'));
    await tester.pumpAndSettle();
    expect(find.text('No possible duplicates found'), findsOneWidget);
    expect(await duplicateGroups.list(), isEmpty);
  });
}

Future<void> _openEditorForTest(
  WidgetTester tester, {
  TransactionDto? existing,
  ValueChanged<TransactionEditorResult?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: _EditorHarness(
        finance: services<FinanceServices>(),
        existing: existing,
        onResult: onResult,
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

Future<void> _tapEditorSave(WidgetTester tester) async {
  expect(
    find.byKey(const ValueKey('transaction-save-locally')),
    findsOneWidget,
  );
  await tester.tap(find.text('Save locally'));
  await tester.pumpAndSettle();
}

Transaction _editorTransaction(String id) {
  final now = DateTime.now().toUtc();
  final date = now.toLocal().toIso8601String().substring(0, 10);
  return Transaction(
    id: TransactionId(id),
    timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
    money: Money(
      amount: DecimalValue.parse('25.00'),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.manual,
    transactionDate: date,
    provenance: [
      Provenance(
        id: ProvenanceId('$id-p'),
        sourceType: ProvenanceSourceType.userEntry,
        capturedAt: now,
        originalRepresentation: 'manual',
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}

class _EditorHarness extends StatefulWidget {
  const _EditorHarness({required this.finance, this.existing, this.onResult});
  final FinanceServices finance;
  final TransactionDto? existing;
  final ValueChanged<TransactionEditorResult?>? onResult;
  @override
  State<_EditorHarness> createState() => _EditorHarnessState();
}

class _EditorHarnessState extends State<_EditorHarness> {
  TransactionEditorResult? lastResult;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async {
          final result = await Navigator.push<TransactionEditorResult>(
            context,
            MaterialPageRoute(
              builder: (_) => TransactionEditorPage(
                finance: widget.finance,
                existing: widget.existing,
              ),
            ),
          );
          if (mounted) {
            setState(() => lastResult = result);
            widget.onResult?.call(result);
          }
        },
        child: const Text('Open editor'),
      ),
    ),
  );
}

final class MemoryUserPreferences implements UserPreferenceRepository {
  UserPreference? value;

  @override
  Future<UserPreference?> load() async => value;

  @override
  Future<void> save(UserPreference preference) async {
    value = preference;
  }
}

Future<void> _scrollTransactionDetailToTop(WidgetTester tester) async {
  final scrollable = _transactionDetailScrollable(tester);
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
}

Finder _transactionDetailScrollable(WidgetTester tester) {
  final detailList = find.byKey(const ValueKey('transaction-detail-list'));
  expect(detailList, findsOneWidget);
  final scrollable = find.descendant(
    of: detailList,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );
  expect(scrollable, findsOneWidget);
  return scrollable;
}

Future<void> _tapTransactionDetailEdit(WidgetTester tester) async {
  final editButton = find.byKey(
    const ValueKey('transaction-detail-edit-button'),
  );
  await tester.scrollUntilVisible(
    editButton,
    200,
    scrollable: _transactionDetailScrollable(tester),
  );
  tester.widget<OutlinedButton>(editButton).onPressed!();
  await tester.pumpAndSettle();
}

Finder _transactionEditorScrollable(WidgetTester tester) {
  final editorList = find.byKey(const ValueKey('transaction-editor-list'));
  expect(editorList, findsOneWidget);
  final scrollable = find.descendant(
    of: editorList,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );
  expect(scrollable, findsOneWidget);
  return scrollable;
}

Future<void> _scrollEditorToMasterData(WidgetTester tester) async {
  final editorList = find.byKey(const ValueKey('transaction-editor-list'));
  expect(editorList, findsOneWidget);
  await tester.drag(editorList, const Offset(0, -520));
  await tester.pumpAndSettle();
}

/// Verify that a real pointer tap reaches the desktop embedded Save action.
/// Calling onPressed directly would hide a clipped or intercepted footer.
Future<void> _submitEmbeddedTransactionSave(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('transaction-save-locally'));
  expect(save, findsOneWidget);
  // A fixed desktop footer must be tappable without scrolling it into view.
  expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Future<void> _scrollEditorToSave(WidgetTester tester) async {
  final save = find.byKey(const ValueKey('transaction-save-locally'));
  expect(save, findsOneWidget);
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
}

void _expectEditorSelection(WidgetTester tester, String label) {
  expect(
    find.byWidgetPredicate(
      (widget) => widget is EditableText && widget.controller.text == label,
    ),
    findsOneWidget,
  );
}

final class MemoryTransactionRepository implements TransactionRepository {
  final values = <String, Transaction>{};
  TransactionRepositoryQuery? lastQuery;
  bool filterPeriodQueries = false;
  bool filterOccurredAtQueries = false;
  Future<void>? saveGate;

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async {
    lastQuery = query;
    return values.values.where((transaction) {
      if (filterOccurredAtQueries &&
          (query.occurredAtFrom != null ||
              query.occurredAtToExclusive != null)) {
        final occurredAt = transaction.timing is KnownTransactionTime
            ? (transaction.timing as KnownTransactionTime).occurredAt
            : null;
        if (occurredAt == null) return false;
        if (query.occurredAtFrom != null &&
            occurredAt.isBefore(query.occurredAtFrom!)) {
          return false;
        }
        if (query.occurredAtToExclusive != null &&
            !occurredAt.isBefore(query.occurredAtToExclusive!)) {
          return false;
        }
      }
      if (filterPeriodQueries && (query.from != null || query.to != null)) {
        final businessDate = transaction.transactionDate?.trim();
        final parsed = businessDate == null
            ? null
            : DateTime.tryParse(businessDate);
        if (parsed == null) return false;
        final date = DateTime.utc(parsed.year, parsed.month, parsed.day);
        final from = query.from == null
            ? null
            : DateTime.utc(
                query.from!.year,
                query.from!.month,
                query.from!.day,
              );
        final to = query.to == null
            ? null
            : DateTime.utc(query.to!.year, query.to!.month, query.to!.day);
        if ((from != null && date.isBefore(from)) ||
            (to != null && date.isAfter(to))) {
          return false;
        }
      }
      if (query.categoryId != null &&
          transaction.categoryId != query.categoryId) {
        return false;
      }
      if (query.needsReview != null &&
          (transaction.reviewState == TransactionReviewState.needsReview) !=
              query.needsReview) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
    if (saveGate case final pending?) await pending;
    values[transaction.id.value] = transaction;
  }
}

final class MemoryDuplicateGroups implements DuplicateCandidateGroupRepository {
  MemoryDuplicateGroups(this.transactions);

  final MemoryTransactionRepository transactions;
  final groups = <DuplicateCandidateGroup>[];
  int fullScanCalls = 0;

  @override
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  }) async => groups
      .where((group) => status == null || group.status == status)
      .toList();

  @override
  Future<List<DuplicateTransactionGroupMatch>>
  findActiveDuplicateGroups() async {
    fullScanCalls++;
    final byKey = <String, DuplicateTransactionGroupMatch>{};
    for (final transaction in transactions.values.values) {
      if (transaction.status != TransactionStatus.active ||
          transaction.transactionDate == null) {
        continue;
      }
      final key = DuplicateTransactionKey(
        transactionDate: transaction.transactionDate!,
        amount: transaction.money.amount,
        currency: transaction.money.currency.value,
        direction: transaction.direction.name,
      );
      final previous = byKey[key.canonical];
      byKey[key.canonical] = DuplicateTransactionGroupMatch(
        duplicateKey: key,
        transactionIds: [...?previous?.transactionIds, transaction.id],
      );
    }
    return byKey.values
        .where((match) => match.transactionIds.length > 1)
        .map(
          (match) => DuplicateTransactionGroupMatch(
            duplicateKey: match.duplicateKey,
            transactionIds: List.unmodifiable(
              match.transactionIds.toList()
                ..sort((a, b) => a.value.compareTo(b.value)),
            ),
          ),
        )
        .toList();
  }

  @override
  Future<List<TransactionId>> findActiveTransactionIdsForKey(
    DuplicateTransactionKey key,
  ) async =>
      transactions.values.values
          .where(
            (transaction) =>
                DuplicateTransactionKey.fromTransaction(
                  transaction,
                )?.canonical ==
                key.canonical,
          )
          .map((transaction) => transaction.id)
          .toList()
        ..sort((left, right) => left.value.compareTo(right.value));

  @override
  Future<void> save(DuplicateCandidateGroup group) async {
    groups.removeWhere((value) => value.id == group.id);
    groups.add(group);
  }

  @override
  Future<void> remove(String id) async {
    groups.removeWhere((group) => group.id == id);
  }
}

final class MemoryStatements
    implements StatementRepository, StatementWorkflowRepository {
  MemoryStatements(this.transactions);

  final MemoryTransactionRepository transactions;
  final statements = <String, FinancialStatement>{};
  final rows = <String, StatementRow>{};

  @override
  Future<void> saveStatement(FinancialStatement statement) async {
    statements[statement.id] = statement;
  }

  @override
  Future<void> saveRows(List<StatementRow> values) async {
    for (final row in values) {
      rows[row.id] = row;
    }
  }

  @override
  Future<void> saveStatementWithRows(
    FinancialStatement statement,
    List<StatementRow> values,
  ) async {
    await saveStatement(statement);
    await saveRows(values);
  }

  @override
  Future<FinancialStatement?> findStatement(String id) async => statements[id];

  @override
  Future<List<FinancialStatement>> listStatements({
    bool includeArchived = false,
  }) async => statements.values
      .where(
        (statement) =>
            includeArchived || statement.status != StatementStatus.archived,
      )
      .toList();

  @override
  Future<List<StatementRow>> listRows(String statementId) async =>
      rows.values.where((row) => row.statementId == statementId).toList()
        ..sort((left, right) => left.position.compareTo(right.position));

  @override
  Future<void> assignPaymentSource(
    String statementId,
    String paymentSourceId,
    DateTime updatedAt,
  ) async {
    final statement = statements[statementId];
    if (statement == null) return;
    statements[statementId] = FinancialStatement(
      id: statement.id,
      evidenceId: statement.evidenceId,
      paymentSourceId: paymentSourceId,
      originalFilename: statement.originalFilename,
      rawTextReference: statement.rawTextReference,
      status: StatementStatus.ready,
      createdAt: statement.createdAt,
      updatedAt: updatedAt,
    );
  }

  @override
  Future<void> updateRow(StatementRow row) async {
    rows[row.id] = row;
  }

  @override
  Future<bool> canDeleteStatement(String id) async => true;

  @override
  Future<void> removeStatement(String id) async {
    statements.remove(id);
    rows.removeWhere((_, row) => row.statementId == id);
  }

  @override
  Future<void> saveRowTransactions(List<StatementRowTransaction> values) async {
    for (final value in values) {
      await saveRowTransaction(value.row, value.transaction);
    }
  }

  @override
  Future<void> saveRowTransaction(
    StatementRow row,
    Transaction transaction,
  ) async {
    await transactions.save(transaction);
    await updateRow(row);
  }

  @override
  Future<void> linkRow(StatementRow row) => updateRow(row);
}

final class MemoryMerchants implements MerchantRepository {
  final values = <String, Merchant>{};

  @override
  Future<Merchant?> findById(MerchantId id) async => values[id.value];
  @override
  Future<List<Merchant>> listAll() async => values.values.toList();
  @override
  Future<void> save(Merchant merchant) async {
    values[merchant.id.value] = merchant;
  }
}

final class MemoryMerchantAliases implements MerchantAliasRepository {
  final values = <String, MerchantAlias>{};

  @override
  Future<MerchantAlias?> findById(MerchantAliasId id) async => values[id.value];

  @override
  Future<List<MerchantAlias>> listForMerchant(MerchantId merchantId) async =>
      values.values.where((value) => value.merchantId == merchantId).toList();

  @override
  Future<void> remove(MerchantAliasId id) async => values.remove(id.value);

  @override
  Future<void> save(MerchantAlias alias) async {
    values[alias.id.value] = alias;
  }
}

final class MemoryMerchantPatterns
    implements MerchantNormalizationPatternRepository {
  final values = <String, MerchantNormalizationPattern>{};

  @override
  Future<MerchantNormalizationPattern?> findById(
    MerchantNormalizationPatternId id,
  ) async => values[id.value];

  @override
  Future<List<MerchantNormalizationPattern>> listForMerchant(
    MerchantId merchantId,
  ) async =>
      values.values.where((value) => value.merchantId == merchantId).toList();

  @override
  Future<void> remove(MerchantNormalizationPatternId id) async =>
      values.remove(id.value);

  @override
  Future<void> save(MerchantNormalizationPattern pattern) async {
    values[pattern.id.value] = pattern;
  }
}

final class MemoryMerchantMatchingConfiguration
    implements MerchantMatchingConfigurationRepository {
  const MemoryMerchantMatchingConfiguration(
    this.merchants,
    this.aliases,
    this.patterns,
  );

  final MemoryMerchants merchants;
  final MemoryMerchantAliases aliases;
  final MemoryMerchantPatterns patterns;

  @override
  Future<void> saveConfiguration({
    required Merchant merchant,
    required List<MerchantAlias> aliases,
    required List<MerchantNormalizationPattern> patterns,
  }) async {
    final merchantAliases = await this.aliases.listForMerchant(merchant.id);
    for (final alias in merchantAliases) {
      await this.aliases.remove(alias.id);
    }
    final merchantPatterns = await this.patterns.listForMerchant(merchant.id);
    for (final pattern in merchantPatterns) {
      await this.patterns.remove(pattern.id);
    }
    await merchants.save(merchant);
    for (final alias in aliases) {
      await this.aliases.save(alias);
    }
    for (final pattern in patterns) {
      await this.patterns.save(pattern);
    }
  }
}

final class MemoryPaymentSources implements PaymentSourceRepository {
  final values = <String, PaymentSource>{};
  int listCalls = 0;
  int saveCalls = 0;
  Future<void>? listCompletion;
  Future<void>? saveCompletion;
  bool failList = false;
  bool failSave = false;

  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async => values[id.value];

  @override
  Future<List<PaymentSource>> listAll() async {
    listCalls++;
    final completion = listCompletion;
    if (completion != null) await completion;
    if (failList) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'list payment sources',
      );
    }
    return values.values.toList();
  }

  @override
  Future<void> save(PaymentSource paymentSource) async {
    saveCalls++;
    final completion = saveCompletion;
    if (completion != null) await completion;
    if (failSave) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'save payment source',
      );
    }
    values[paymentSource.id.value] = paymentSource;
  }
}

final class MemoryPaymentSettlements implements PaymentSettlementRepository {
  final values = <String, PaymentSettlement>{};
  final periodTransactions = <Transaction>[];
  MemoryTransactionRepository? transactionRepository;
  Future<void>? saveCompletion;
  bool savePending = false;
  int saveCalls = 0;
  int listCalls = 0;
  int transactionListCalls = 0;
  bool failList = false;

  @override
  Future<PaymentSettlement?> findById(PaymentSettlementId id) async =>
      values[id.value];

  @override
  Future<List<PaymentSettlement>> listAll() async {
    listCalls++;
    if (failList) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'list payment settlements',
      );
    }
    return values.values.toList();
  }

  @override
  Future<List<Transaction>> listTransactions(
    PaymentSettlement settlement, {
    DateTime? occurredAtFrom,
    DateTime? occurredAtToExclusive,
  }) async {
    transactionListCalls++;
    final transactions = transactionRepository;
    if (transactions == null) return periodTransactions;
    return periodTransactions
        .map((original) => transactions.values[original.id.value])
        .whereType<Transaction>()
        .toList(growable: false);
  }

  @override
  Future<void> remove(PaymentSettlementId id) async => values.remove(id.value);

  @override
  Future<void> save(PaymentSettlement settlement) async {
    saveCalls++;
    final completion = saveCompletion;
    if (completion != null) {
      savePending = true;
      await completion;
    }
    values[settlement.id.value] = settlement;
  }
}

final class MemoryCategories implements CategoryRepository {
  final values = <String, Category>{};

  @override
  Future<Category?> findById(CategoryId id) async => values[id.value];
  @override
  Future<List<Category>> listAll() async => values.values.toList();
  @override
  Future<void> save(Category category) async {
    values[category.id.value] = category;
  }
}

final class MemoryTags implements TagRepository {
  final values = <String, Tag>{};

  @override
  Future<Tag?> findById(TagId id) async => values[id.value];
  @override
  Future<List<Tag>> listAll() async => values.values.toList();
  @override
  Future<void> save(Tag tag) async {
    values[tag.id.value] = tag;
  }
}

final class MemoryEvidence implements EvidenceRepository {
  int listCalls = 0;
  List<EvidenceItem> items = const [];
  @override
  Future<EvidenceItem?> findById(EvidenceId id) async => null;
  @override
  Future<void> link(AttachmentLink link) async {}
  @override
  Future<void> unlinkFromTransaction(
    TransactionId transactionId,
    EvidenceId evidenceId,
  ) async {}
  @override
  Future<List<EvidenceItem>> listForTransaction(TransactionId id) async {
    listCalls++;
    return items;
  }

  @override
  Future<void> remove(EvidenceId id) async {}
  @override
  Future<void> save(EvidenceItem evidence) async {}
  @override
  Future<void> saveExtraction(Extraction extraction) async {}
}
