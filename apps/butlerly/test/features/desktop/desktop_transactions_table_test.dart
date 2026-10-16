import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_transaction_table.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_record_list.dart';
import 'package:butlerly/features/foundation/presentation/transaction_row.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  final now = DateTime.utc(2026, 10, 15);
  final data = [
    TransactionDto(
      id: 'oct-1',
      amount: '25.00',
      currency: 'USD',
      direction: 'expense',
      status: 'active',
      reviewState: 'clear',
      transactionDate: '2026-10-15',
      createdAt: now,
      updatedAt: now,
      merchantId: 'store',
      categoryId: 'food',
      subcategoryId: 'dining',
      paymentSourceId: 'visa',
    ),
    TransactionDto(
      id: 'oct-2',
      amount: '12.00',
      currency: 'USD',
      direction: 'expense',
      status: 'active',
      reviewState: 'clear',
      transactionDate: '2026-10-10',
      createdAt: now,
      updatedAt: now,
      description: 'Cafe',
      categoryId: 'food',
    ),
    TransactionDto(
      id: 'sep-1',
      amount: '8.50',
      currency: 'USD',
      direction: 'expense',
      status: 'active',
      reviewState: 'clear',
      transactionDate: '2026-09-22',
      createdAt: now,
      updatedAt: now,
      description: 'September cafe',
      categoryId: 'food',
    ),
  ];
  const masterData = TransactionMasterData(
    merchantNames: {'store': 'Corner Store'},
    categoryNames: {'food': 'Food', 'dining': 'Dining'},
    paymentSourceNames: {'visa': 'Travel Visa •••• 8421'},
    paymentSourceMarks: {'visa': 'visa'},
  );

  testWidgets(
    'Wide Transactions keeps month cards, totals, and inner card tables',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? tapped;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: SingleChildScrollView(
              child: TransactionRecordList(
                transactions: data,
                masterData: masterData,
                groupByFinancialDate: true,
                collapsibleMonthSections: true,
                monthSectionsAsCards: true,
                dashboardRowStyle: true,
                desktopTableMode: true,
                onTap: (transaction) => tapped = transaction.id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('2 transactions'), findsOneWidget);
      expect(find.text('1 transaction'), findsOneWidget);
      expect(find.textContaining('37.00'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transaction-month-card-2026-10')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('transaction-month-inner-card-2026-10')),
        findsOneWidget,
      );
      expect(find.byType(ButlerlyTransactionInnerCard), findsOneWidget);
      expect(find.byType(ButlerlyDesktopTransactionTable), findsOneWidget);
      expect(find.byType(TransactionRow), findsNothing);
      expect(find.text('Merchant'), findsOneWidget);
      expect(find.text('Subcategory'), findsOneWidget);
      expect(find.text('Payment source'), findsOneWidget);
      expect(find.text('Corner Store'), findsOneWidget);
      expect(find.text('Dining'), findsOneWidget);
      expect(find.text('Travel Visa •••• 8421'), findsOneWidget);
      expect(find.byType(ButlerlyPaymentMarkIcon), findsOneWidget);
      expect(find.text('September cafe'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('desktop-transaction-row-oct-1')),
      );
      expect(tapped, 'oct-1');

      await tester.tap(find.text('September 2026'));
      await tester.pumpAndSettle();
      expect(find.byType(ButlerlyDesktopTransactionTable), findsNWidgets(2));
      expect(find.text('September cafe'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transaction-month-inner-card-2026-09')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Reusable desktop tables accept independent page data and taps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? firstSelection;
    String? secondSelection;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                width: 1000,
                child: ButlerlyDesktopTransactionTable(
                  transactions: [data[0]],
                  masterData: masterData,
                  onTap: (value) => firstSelection = value.id,
                ),
              ),
              SizedBox(
                width: 1000,
                child: ButlerlyDesktopTransactionTable(
                  transactions: [data[1]],
                  masterData: masterData,
                  onTap: (value) => secondSelection = value.id,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ButlerlyDesktopTransactionTable), findsNWidgets(2));
    expect(find.text('Merchant'), findsNWidgets(2));
    await tester.tap(
      find.byKey(const ValueKey('desktop-transaction-row-oct-1')),
    );
    expect(firstSelection, 'oct-1');
    expect(secondSelection, isNull);
    await tester.tap(
      find.byKey(const ValueKey('desktop-transaction-row-oct-2')),
    );
    expect(secondSelection, 'oct-2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reusable desktop table scrolls within a narrow side panel', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 430,
              child: ButlerlyDesktopTransactionTable(
                transactions: [data[0]],
                masterData: masterData,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-transaction-table-horizontal-scroll')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('desktop-transactions-table')))
          .width,
      ButlerlyDesktopTransactionTable.minimumTableWidth,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Desktop Search uses the Home inner-card geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: SingleChildScrollView(
            child: TransactionRecordList(
              transactions: data.take(2).toList(),
              masterData: masterData,
              groupByFinancialDate: true,
              collapsibleMonthSections: true,
              monthSectionsAsCards: true,
              dashboardRowStyle: true,
              desktopHomeInnerCardStyle: true,
              desktopTableMode: true,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final inner = find.byType(ButlerlyDesktopInnerCard);
    expect(inner, findsOneWidget);
    expect(
      find.byKey(const ValueKey('transaction-month-inner-card-2026-10')),
      findsOneWidget,
    );
    expect(find.byType(ButlerlyTransactionInnerCard), findsNothing);
    expect(find.byType(ButlerlyDesktopTransactionTable), findsOneWidget);
    expect(find.byType(TransactionRow), findsNothing);
    expect(find.text('Merchant'), findsOneWidget);
    expect(find.text('Payment source'), findsOneWidget);

    // Assert one canonical 12 px content inset on every side, not stacked
    // 12 px card padding plus another 12 px inside the table.
    final table = find.byKey(const ValueKey('desktop-transactions-table'));
    final cardRect = tester.getRect(inner);
    final tableRect = tester.getRect(table);
    expect(
      tableRect.left - cardRect.left,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      cardRect.right - tableRect.right,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      tableRect.top - cardRect.top,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );
    expect(
      cardRect.bottom - tableRect.bottom,
      closeTo(ButlerlyDesktopInnerCard.contentPadding, 0.1),
    );

    final clipped = tester.widget<ClipRRect>(
      find.descendant(of: inner, matching: find.byType(ClipRRect)).first,
    );
    expect(
      clipped.borderRadius,
      BorderRadius.circular(ButlerlyDesktopInnerCard.cornerRadius),
    );
    final padding = tester.widget<Padding>(
      find.descendant(of: inner, matching: find.byType(Padding)).first,
    );
    expect(
      padding.padding,
      const EdgeInsets.all(ButlerlyDesktopInnerCard.contentPadding),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home and Search inner cards render identical table contents', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(
                  width: 1000,
                  child: ButlerlyDesktopTransactionSection(
                    key: const ValueKey('home-reference-outer'),
                    innerCardKey: const ValueKey('home-reference-inner'),
                    title: 'Recent transactions',
                    transactions: data.take(2).toList(),
                    masterData: masterData,
                    onTap: (_) {},
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 1020,
                  child: TransactionRecordList(
                    transactions: data.take(2).toList(),
                    masterData: masterData,
                    groupByFinancialDate: true,
                    collapsibleMonthSections: true,
                    monthSectionsAsCards: true,
                    desktopHomeInnerCardStyle: true,
                    desktopTableMode: true,
                    onTap: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ButlerlyDesktopTransactionTableCard), findsNWidgets(2));
    expect(find.byType(ButlerlyDesktopTransactionSection), findsNWidgets(2));
    final homeInner = find.byKey(const ValueKey('home-reference-inner'));
    final searchInner = find.byKey(
      const ValueKey('transaction-month-inner-card-2026-10'),
    );
    final homeTable = find.descendant(
      of: homeInner,
      matching: find.byKey(const ValueKey('desktop-transactions-table')),
    );
    final searchTable = find.descendant(
      of: searchInner,
      matching: find.byKey(const ValueKey('desktop-transactions-table')),
    );
    expect(homeTable, findsOneWidget);
    expect(searchTable, findsOneWidget);
    expect(
      find.descendant(
        of: homeInner,
        matching: find.byType(ButlerlyDesktopInnerCard),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: searchInner,
        matching: find.byType(ButlerlyDesktopInnerCard),
      ),
      findsOneWidget,
    );

    final homeOuter = find.byKey(const ValueKey('home-reference-outer'));
    final searchOuter = find.byKey(
      const ValueKey('transaction-month-card-2026-10'),
    );
    final homeOuterRect = tester.getRect(homeOuter);
    final searchOuterRect = tester.getRect(searchOuter);
    final homeCardRect = tester.getRect(homeInner);
    final searchCardRect = tester.getRect(searchInner);
    for (final offset in [
      homeCardRect.left - homeOuterRect.left,
      homeOuterRect.right - homeCardRect.right,
      searchCardRect.left - searchOuterRect.left,
      searchOuterRect.right - searchCardRect.right,
    ]) {
      expect(
        offset,
        closeTo(ButlerlyDesktopTransactionSection.outerPadding, 0.1),
      );
    }

    final homeHeader = find.descendant(
      of: homeOuter,
      matching: find.text('Recent transactions'),
    );
    final searchHeader = find.descendant(
      of: searchOuter,
      matching: find.text('October 2026'),
    );
    expect(
      tester.getTopLeft(homeHeader).dx - homeOuterRect.left,
      closeTo(ButlerlyDesktopTransactionSection.outerPadding, 0.1),
    );
    expect(
      tester.getTopLeft(searchHeader).dx - searchOuterRect.left,
      closeTo(ButlerlyDesktopTransactionSection.outerPadding, 0.1),
    );
    final homeInnerRect = tester.getRect(homeInner);
    final searchInnerRect = tester.getRect(searchInner);
    final homeTableRect = tester.getRect(homeTable);
    final searchTableRect = tester.getRect(searchTable);
    expect(
      tester.getSize(homeTable).height,
      tester.getSize(searchTable).height,
    );
    expect(
      homeTableRect.left - homeInnerRect.left,
      searchTableRect.left - searchInnerRect.left,
    );
    expect(
      homeInnerRect.right - homeTableRect.right,
      searchInnerRect.right - searchTableRect.right,
    );
    expect(
      homeTableRect.top - homeInnerRect.top,
      searchTableRect.top - searchInnerRect.top,
    );
    expect(
      homeInnerRect.bottom - homeTableRect.bottom,
      searchInnerRect.bottom - searchTableRect.bottom,
    );

    for (final label in ['Date', 'Merchant', 'Category', 'Amount']) {
      final homeCell = find.descendant(
        of: homeInner,
        matching: find.text(label),
      );
      final searchCell = find.descendant(
        of: searchInner,
        matching: find.text(label),
      );
      expect(homeCell, findsOneWidget);
      expect(searchCell, findsOneWidget);
      expect(
        tester.widget<Text>(homeCell).style,
        tester.widget<Text>(searchCell).style,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('Compact and Medium retain canonical transaction rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: SingleChildScrollView(
            child: TransactionRecordList(
              transactions: data.take(2).toList(),
              masterData: masterData,
              groupByFinancialDate: true,
              collapsibleMonthSections: true,
              monthSectionsAsCards: true,
              dashboardRowStyle: true,
              onTap: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ButlerlyDesktopTransactionTable), findsNothing);
    expect(find.byType(TransactionRow), findsNWidgets(2));
    expect(find.text('2 transactions'), findsOneWidget);
    expect(find.text('Corner Store'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
