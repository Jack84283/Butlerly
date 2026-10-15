import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly/features/desktop/presentation/desktop_transaction_table.dart';
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
      expect(find.byType(DesktopTransactionTable), findsOneWidget);
      expect(find.byType(TransactionRow), findsNothing);
      expect(find.text('Merchant'), findsOneWidget);
      expect(find.text('Subcategory'), findsOneWidget);
      expect(find.text('Payment source'), findsOneWidget);
      expect(find.text('Corner Store'), findsOneWidget);
      expect(find.text('Dining'), findsOneWidget);
      expect(find.text('Travel Visa •••• 8421'), findsOneWidget);
      expect(find.byType(ButlerlyPaymentMarkIcon), findsOneWidget);
      expect(find.text('September cafe'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('desktop-transaction-row-oct-1')));
      expect(tapped, 'oct-1');

      await tester.tap(find.text('September 2026'));
      await tester.pumpAndSettle();
      expect(find.byType(DesktopTransactionTable), findsNWidgets(2));
      expect(find.text('September cafe'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('transaction-month-inner-card-2026-09')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(find.byType(DesktopTransactionTable), findsNothing);
    expect(find.byType(TransactionRow), findsNWidgets(2));
    expect(find.text('2 transactions'), findsOneWidget);
    expect(find.text('Corner Store'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
