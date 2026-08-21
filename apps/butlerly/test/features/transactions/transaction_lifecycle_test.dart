import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/features/foundation/presentation/review_page.dart';
import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
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

  setUp(() async {
    await services.reset();
    repository = MemoryTransactionRepository();
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        repository,
        MemoryPaymentSources(),
        MemoryMerchants(),
        MemoryCategories(),
        MemoryTags(),
        MemoryEvidence(),
        MemoryUserPreferences(),
      ),
    );
  });

  tearDown(() => services.reset());

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
    await tester.tap(find.text('Organize transaction'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNWidgets(3));
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
    expect(find.text('Transactions'), findsOneWidget);

    await tester.ensureVisible(find.text('Corrected lunch'));
    await tester.tap(find.text('Corrected lunch'));
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

    expect(find.text('Corner Market'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
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

    await tester.tap(find.text('Merchant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Corner Market').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Groceries').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add tag').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weekly').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save organization'));
    await tester.pumpAndSettle();

    expect(find.text('Transaction detail'), findsOneWidget);
    expect(find.text('Corner Market'), findsOneWidget);
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Weekly'), findsOneWidget);
    final stored = repository.values['select-master-data']!;
    expect(stored.merchantId, MerchantId('merchant-market'));
    expect(stored.categoryId, CategoryId('category-groceries'));
    expect(stored.tagIds, contains(TagId('tag-weekly')));
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
    expect(find.text('Remove me'), findsOneWidget);
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
    expect(find.text('商户'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    expect(find.text('添加标签'), findsNWidgets(2));
    expect(find.text('保存整理结果'), findsOneWidget);
    expect(find.text('Organize transaction'), findsNothing);
  });
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
  @override
  Future<EvidenceItem?> findById(EvidenceId id) async => null;
  @override
  Future<void> link(AttachmentLink link) async {}
  @override
  Future<List<EvidenceItem>> listForTransaction(TransactionId id) async =>
      const [];
  @override
  Future<void> remove(EvidenceId id) async {}
  @override
  Future<void> save(EvidenceItem evidence) async {}
  @override
  Future<void> saveExtraction(Extraction extraction) async {}
}
