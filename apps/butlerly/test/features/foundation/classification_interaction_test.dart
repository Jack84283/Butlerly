import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../transactions/transaction_lifecycle_test.dart'
    show
        MemoryCategories,
        MemoryDuplicateGroups,
        MemoryEvidence,
        MemoryMerchants,
        MemoryPaymentSources,
        MemoryTags,
        MemoryTransactionRepository,
        MemoryUserPreferences;

void main() {
  late MemoryTransactionRepository transactions;
  late MemoryMerchants merchants;
  late MemoryCategories categories;
  late FinanceServices finance;

  setUp(() {
    transactions = MemoryTransactionRepository();
    merchants = MemoryMerchants();
    categories = MemoryCategories();
    final duplicateGroups = MemoryDuplicateGroups(transactions);
    finance = FinanceServices(
      transactions,
      MemoryPaymentSources(),
      merchants,
      categories,
      MemoryTags(),
      MemoryEvidence(),
      MemoryUserPreferences(),
      duplicateGroups: duplicateGroups,
    );
    categories.values
      ..['food'] = Category(
        id: CategoryId('food'),
        name: 'Food & Dining',
        origin: CategoryOrigin.system,
      )
      ..['groceries'] = Category(
        id: CategoryId('groceries'),
        name: 'Groceries',
        origin: CategoryOrigin.system,
        parentId: CategoryId('food'),
      )
      ..['travel'] = Category(
        id: CategoryId('travel'),
        name: 'Travel',
        origin: CategoryOrigin.system,
      )
      ..['transport'] = Category(
        id: CategoryId('transport'),
        name: 'Transport',
        origin: CategoryOrigin.system,
        parentId: CategoryId('travel'),
      );
  });

  Future<void> seedMerchant({required bool withHistory}) async {
    merchants.values['safeway'] = Merchant(
      id: MerchantId('safeway'),
      name: 'Safeway',
      defaultCategoryId: CategoryId('travel'),
      defaultSubcategoryId: CategoryId('transport'),
    );
    if (withHistory) {
      transactions.values['historical'] = Transaction(
        id: TransactionId('historical'),
        timing: KnownTransactionTime(DateTime.utc(2026, 8, 1)),
        money: Money(
          amount: DecimalValue.parse('20'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.manual,
        description: 'SAFEWAY #1234',
        merchantId: MerchantId('safeway'),
        categoryId: CategoryId('food'),
        subcategoryId: CategoryId('groceries'),
        provenance: [
          Provenance(
            id: ProvenanceId('historical-provenance'),
            sourceType: ProvenanceSourceType.userEntry,
            capturedAt: DateTime.utc(2026, 8, 1),
          ),
        ],
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
      );
    }
  }

  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('manual description visibly applies historical classification', (
    tester,
  ) async {
    await seedMerchant(withHistory: true);
    await pumpApp(tester, TransactionEditorPage(finance: finance));
    await tester.enterText(find.byType(TextFormField).at(2), 'SAFEWAY #5678');
    await tester.pumpAndSettle();
    await _scrollToSelectors(tester);

    _expectSelectorValue(tester, 'Food & Dining');
    _expectSelectorValue(tester, 'Groceries');
  });

  testWidgets('manual merchant selection visibly applies defaults', (
    tester,
  ) async {
    await seedMerchant(withHistory: false);
    await pumpApp(tester, TransactionEditorPage(finance: finance));

    await _scrollToSelectors(tester);
    await _chooseDropdown(tester, 0, 'Safeway');

    _expectSelectorValue(tester, 'Travel');
    _expectSelectorValue(tester, 'Transport');
  });

  testWidgets('manual classification override survives later changes', (
    tester,
  ) async {
    await seedMerchant(withHistory: true);
    await pumpApp(tester, TransactionEditorPage(finance: finance));
    await tester.enterText(find.byType(TextFormField).at(2), 'SAFEWAY #5678');
    await tester.pumpAndSettle();
    await _scrollToSelectors(tester);
    _expectSelectorValue(tester, 'Food & Dining');
    _expectSelectorValue(tester, 'Groceries');

    await _chooseDropdown(tester, 1, 'Travel');
    await _chooseDropdown(tester, 2, 'Transport');
    await _scrollToTop(tester);
    await tester.enterText(
      find.byType(TextFormField).at(2),
      'A different shop',
    );
    await tester.pumpAndSettle();
    await _scrollToSelectors(tester);
    await _chooseDropdown(tester, 0, 'Safeway');

    _expectSelectorValue(tester, 'Travel');
    _expectSelectorValue(tester, 'Transport');
  });
}

Future<void> _chooseDropdown(
  WidgetTester tester,
  int index,
  String value,
) async {
  await tester.tap(find.byType(DropdownMenu<String>).at(index));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, value);
  await tester.pumpAndSettle();
  await tester.tap(find.byType(MenuItemButton).last);
  await tester.pumpAndSettle();
}

Future<void> _scrollToSelectors(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.drag(scrollable, const Offset(0, -600));
  await tester.pumpAndSettle();
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
  await tester.pumpAndSettle();
}

void _expectSelectorValue(WidgetTester tester, String value) {
  expect(
    find.byWidgetPredicate(
      (widget) => widget is TextField && widget.controller?.text == value,
    ),
    findsOneWidget,
  );
}
