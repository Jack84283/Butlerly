import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/features/foundation/presentation/review_page.dart';
import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('en'));
  late MemoryTransactionRepository repository;
  late MemoryEvidence evidenceRepository;
  late MemoryDuplicateGroups duplicateGroups;
  late MemoryPaymentSources paymentSources;

  setUp(() async {
    await services.reset();
    repository = MemoryTransactionRepository();
    evidenceRepository = MemoryEvidence();
    duplicateGroups = MemoryDuplicateGroups(repository);
    paymentSources = MemoryPaymentSources();
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        repository,
        paymentSources,
        MemoryMerchants(),
        MemoryCategories(),
        MemoryTags(),
        evidenceRepository,
        MemoryUserPreferences(),
        duplicateGroups: duplicateGroups,
      ),
    );
  });

  tearDown(() => services.reset());

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
    expect(find.text('No evidence is attached locally.'), findsOneWidget);

    notifyTransactionChanged();
    await tester.pumpAndSettle();
    expect(find.text('No evidence is attached locally.'), findsOneWidget);
    expect(evidenceRepository.listCalls, 2);
  });

  testWidgets('creates, edits, archives, and permanently deletes locally', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: TransactionsPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add transaction').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '12.50');
    await tester.enterText(find.byType(TextFormField).at(2), 'Lunch');
    await tester.enterText(find.byType(TextFormField).at(3), 'Team meal');
    await tester.scrollUntilVisible(
      find.text('Save locally'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();

    expect(find.text('Lunch'), findsOneWidget);
    expect(repository.values.values.single.notes, 'Team meal');
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction detail'), findsOneWidget);
    expect(find.text('Team meal'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Organize transaction'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('Organize transaction'));
    await tester.tap(find.text('Organize transaction'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(DropdownMenu<String>), findsNWidgets(3));
    expect(find.textContaining('add a new'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), 'Corrected lunch');
    await tester.scrollUntilVisible(
      find.text('Save locally'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction detail'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Archive transaction'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Archive transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    final archivedAfterResult = await services<FinanceServices>()
        .getTransaction(repository.values.values.single.id.value);
    final archivedAfter =
        (archivedAfterResult as ApplicationSuccess<TransactionDto>).value;
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('archived-transaction-detail'),
        home: TransactionDetailPage(
          finance: services<FinanceServices>(),
          transaction: archivedAfter,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Transaction detail'), findsOneWidget);
    for (var index = 0; index < 3; index++) {
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently').last);
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

    await tester.tap(find.text('Filters'));
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
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Lunch'), findsAtLeastNWidgets(1));
    expect(find.text('Bus'), findsNothing);
  });

  testWidgets('Home refreshes when a transaction changes outside its route', (
    tester,
  ) async {
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

  testWidgets('transaction rows show merchant category and tags', (
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

    await tester.pumpWidget(const MaterialApp(home: TransactionsPage()));
    await tester.pumpAndSettle();

    expect(find.text('Organized row'), findsOneWidget);
    expect(find.text('Corner Market • Groceries • Weekly'), findsOneWidget);
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

    expect(find.text('Lunch'), findsOneWidget);
    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();

    expect(find.text('You’re all caught up'), findsOneWidget);
  });

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
    await tester.pumpWidget(const MaterialApp(home: ReviewPage()));
    await tester.pumpAndSettle();
    expect(find.byType(ButlerlyCard), findsOneWidget);
    expect(find.byType(ButlerlyRecordRow), findsOneWidget);
    expect(find.text('Needs a category'), findsOneWidget);
    expect(find.text('Resolve'), findsOneWidget);

    await tester.tap(find.text('Uncategorized'));
    await tester.pumpAndSettle();
    expect(find.byType(ButlerlyTransactionList), findsOneWidget);
    expect(find.byType(ButlerlyRecordRow), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
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
    await tester.tap(find.text('Uncategorized'));
    await tester.pumpAndSettle();
    expect(find.text('Refresh me'), findsOneWidget);
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
    await tester.tap(find.text('Uncategorized'));
    await tester.pumpAndSettle();
    expect(find.text('Added after refresh'), findsOneWidget);
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
      final candidate = find.byType(ButlerlyTransactionListItem).last;
      await tester.ensureVisible(candidate);
      await tester.tap(candidate);
      await tester.pump();
      final consolidate = find.text('Consolidate / use one');
      await tester.ensureVisible(consolidate);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Consolidate / use one'),
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

    await tester.tap(find.text('Rescan possible duplicates'));
    await tester.pumpAndSettle();
    expect(duplicateGroups.fullScanCalls, 1);
    expect(transactionChanges.value, notificationBeforeRescan + 1);
  });

  testWidgets('creates and archives a local payment source', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PaymentSourcesPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add payment source'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Travel card');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Travel card'), findsOneWidget);
    await tester.tap(find.byTooltip('Archive payment source'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Archived'), findsOneWidget);
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

    expect(find.text('Aug 10, 2026'), findsOneWidget);
    expect(find.text('Aug 11, 2026'), findsNothing);
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
    expect(find.text('Weekly').evaluate().isNotEmpty, isTrue);
    expect(find.text('merchant-123456'), findsNothing);
    expect(find.text('category-123456'), findsNothing);
    expect(find.text('tag-123456'), findsNothing);
  });

  testWidgets('organizer assigns predefined merchant category and tag', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.saveMerchant(
      Merchant(id: MerchantId('merchant-market'), name: 'Corner Market'),
    );
    await finance.saveCategory(
      Category(
        id: CategoryId('category-groceries'),
        name: 'Groceries',
        origin: CategoryOrigin.system,
      ),
    );
    await finance.saveTag(Tag(id: TagId('tag-weekly'), name: 'Weekly'));
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'select-master-data',
        provenanceId: 'manual-select-master-data',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 10)),
        money: Money(
          amount: DecimalValue.parse('24.50'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Market purchase',
      ),
    );
    final transactionResult = await finance.getTransaction(
      'select-master-data',
    );
    final transaction =
        (transactionResult as ApplicationSuccess<TransactionDto>).value;

    await tester.pumpWidget(
      MaterialApp(
        home: TransactionDetailPage(finance: finance, transaction: transaction),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Organize transaction'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Organize transaction'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownMenu<String>).at(0));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Corner Market');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MenuItemButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownMenu<String>).at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Groceries');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MenuItemButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownMenu<String>).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MenuItemButton).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save organization'));
    await tester.pumpAndSettle();

    expect(find.text('Transaction detail'), findsOneWidget);
  });

  testWidgets('organizer removes an assigned tag and returns to detail', (
    tester,
  ) async {
    final finance = services<FinanceServices>();
    await finance.saveTag(Tag(id: TagId('tag-remove'), name: 'Remove me'));
    await finance.createTransaction(
      CreateTransactionCommand(
        id: 'remove-tag',
        provenanceId: 'manual-remove-tag',
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 10)),
        money: Money(
          amount: DecimalValue.parse('9.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Tagged purchase',
      ),
    );
    await finance.addTag('remove-tag', 'tag-remove');
    final result = await finance.getTransaction('remove-tag');
    final transaction = (result as ApplicationSuccess<TransactionDto>).value;

    await tester.pumpWidget(
      MaterialApp(
        home: TransactionDetailPage(finance: finance, transaction: transaction),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Organize transaction'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Organize transaction'));
    await tester.pumpAndSettle();

    expect(find.text('Remove me'), findsNWidgets(2));
    final chipBounds = tester.getRect(find.byType(InputChip));
    await tester.tapAt(Offset(chipBounds.right - 16, chipBounds.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('Remove me').last, findsOneWidget);
    await tester.tap(find.text('Save organization'));
    await tester.pumpAndSettle();

    expect(find.text('Transaction detail'), findsOneWidget);
    expect(find.text('Remove me'), findsNothing);
    expect(repository.values['remove-tag']!.tagIds, isEmpty);
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

    expect(find.text('2026-08-10'), findsOneWidget);
    expect(find.text('2026-08-11'), findsNothing);
  });

  testWidgets('detail and organization dialog use Simplified Chinese', (
    tester,
  ) async {
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
        home: TransactionDetailPage(finance: finance, transaction: transaction),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('交易详情'), findsOneWidget);
    expect(find.text('方向'), findsOneWidget);
    expect(find.text('支出'), findsOneWidget);
    expect(find.text('Transaction detail'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('整理交易'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('整理交易'));
    await tester.pumpAndSettle();

    expect(find.text('整理交易'), findsNWidgets(2));
    expect(find.text('商户').last, findsOneWidget);
    expect(find.text('分类').last, findsOneWidget);
    expect(find.text('添加标签'), findsOneWidget);
    expect(find.text('保存整理结果'), findsOneWidget);
    expect(find.text('Organize transaction'), findsNothing);
  });

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
  await tester.scrollUntilVisible(
    find.text('Save locally'),
    160,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(find.text('Save locally'));
  await tester.pumpAndSettle();
}

Transaction _editorTransaction(String id) {
  final now = DateTime.now().toUtc();
  final date = now.toIso8601String().substring(0, 10);
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

final class MemoryTransactionRepository implements TransactionRepository {
  final values = <String, Transaction>{};

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values.values.where((transaction) {
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

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
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

final class MemoryPaymentSources implements PaymentSourceRepository {
  final values = <String, PaymentSource>{};

  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async => values[id.value];

  @override
  Future<List<PaymentSource>> listAll() async => values.values.toList();

  @override
  Future<void> save(PaymentSource paymentSource) async {
    values[paymentSource.id.value] = paymentSource;
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
  @override
  Future<EvidenceItem?> findById(EvidenceId id) async => null;
  @override
  Future<void> link(AttachmentLink link) async {}
  @override
  Future<List<EvidenceItem>> listForTransaction(TransactionId id) async {
    listCalls++;
    return const [];
  }

  @override
  Future<void> remove(EvidenceId id) async {}
  @override
  Future<void> save(EvidenceItem evidence) async {}
  @override
  Future<void> saveExtraction(Extraction extraction) async {}
}
