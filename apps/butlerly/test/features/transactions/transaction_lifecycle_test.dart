import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/features/foundation/presentation/review_page.dart';
import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Lunch'), findsOneWidget);
    await tester.tap(find.text('Lunch'));
    await tester.pumpAndSettle();
    expect(find.text('Transaction detail'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(2), 'Corrected lunch');
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();
    expect(find.text('Transactions'), findsOneWidget);

    await tester.tap(find.text('Corrected lunch'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Archive transaction'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Archive transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Corrected lunch'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Permanently delete'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Permanently delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.text('No transactions yet'), findsOneWidget);
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

    await tester.tap(find.text('Any category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dining').last);
    await tester.enterText(find.byType(EditableText), 'Lunch');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Lunch'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Bus'), findsNothing);
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
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolve review issue'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing needs review right now.'), findsOneWidget);
  });

  testWidgets('creates and archives a local payment source', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PaymentSourcesPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add source'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Travel card');
    await tester.tap(find.text('Save locally'));
    await tester.pumpAndSettle();

    expect(find.text('Travel card'), findsOneWidget);
    await tester.tap(find.byTooltip('Archive payment source'));
    await tester.pumpAndSettle();
    expect(find.textContaining('archived'), findsOneWidget);
  });
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
  @override
  Future<Merchant?> findById(MerchantId id) async => null;
  @override
  Future<List<Merchant>> listAll() async => const [];
  @override
  Future<void> save(Merchant merchant) async {}
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
  @override
  Future<Tag?> findById(TagId id) async => null;
  @override
  Future<List<Tag>> listAll() async => const [];
  @override
  Future<void> save(Tag tag) async {}
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
  Future<void> save(EvidenceItem evidence) async {}
  @override
  Future<void> saveExtraction(Extraction extraction) async {}
}
