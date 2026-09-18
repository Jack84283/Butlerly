import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_record_list.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shared transaction rows use merchant title and matching amount size',
    (tester) async {
      final now = DateTime.utc(2026, 9, 15, 12);
      final transaction = TransactionDto(
        id: 'transaction-1',
        amount: '12.34',
        currency: 'USD',
        direction: 'expense',
        status: 'active',
        reviewState: 'clear',
        transactionDate: '2026-09-15',
        createdAt: now,
        updatedAt: now,
        description: 'Groceries for dinner',
        rawCounterparty: 'WHOLE FOODS #123',
        merchantId: 'merchant-1',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: TransactionRecordList(
              transactions: [transaction],
              masterData: const TransactionMasterData(
                merchantNames: {'merchant-1': 'Whole Foods'},
              ),
              onTap: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Whole Foods'), findsOneWidget);
      expect(find.text('Groceries for dinner'), findsNothing);

      final title = tester.widget<Text>(find.text('Whole Foods'));
      final amount = tester.widget<Text>(find.text('−12.34 USD'));
      expect(amount.style?.fontSize, title.style?.fontSize);
    },
  );

  testWidgets(
    'shared transaction rows fall back when merchant is unavailable',
    (tester) async {
      final now = DateTime.utc(2026, 9, 15, 12);
      final transaction = TransactionDto(
        id: 'transaction-2',
        amount: '8.50',
        currency: 'USD',
        direction: 'expense',
        status: 'active',
        reviewState: 'clear',
        transactionDate: '2026-09-15',
        createdAt: now,
        updatedAt: now,
        description: 'Coffee with client',
        rawCounterparty: 'CAFE RAW',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: const [Locale('en')],
          home: Scaffold(
            body: TransactionRecordList(
              transactions: [transaction],
              onTap: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Coffee with client'), findsOneWidget);
      expect(find.text('CAFE RAW'), findsNothing);
    },
  );
  testWidgets('canonical payment source label wins over a raw page override', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 15, 12);
    final transaction = TransactionDto(
      id: 'transaction-card',
      amount: '42.00',
      currency: 'USD',
      direction: 'expense',
      status: 'active',
      reviewState: 'needsReview',
      transactionDate: '2026-09-15',
      createdAt: now,
      updatedAt: now,
      description: 'Dinner',
      paymentSourceId: 'card-1',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: const [Locale('en')],
        home: Scaffold(
          body: TransactionRecordList(
            transactions: [transaction],
            masterData: const TransactionMasterData(
              paymentSourceNames: {'card-1': 'Travel card •••• 8421'},
            ),
            paymentSourceNames: const {'card-1': 'Travel card'},
            onTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Travel card •••• 8421'), findsOneWidget);
    expect(find.text('Travel card'), findsNothing);
  });

}
