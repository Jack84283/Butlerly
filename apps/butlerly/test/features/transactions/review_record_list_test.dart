import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_transaction_item.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/features/foundation/presentation/transaction_record_list.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final needsReview in [true, false]) {
    testWidgets(
      'grouped review metadata wraps and preserves taps: $needsReview',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();

        const reason =
            'Category conflicts with imported receipt information that needs careful review before confirming the transaction';
        String? tapped;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: TransactionRecordList(
                  transactions: [
                    for (var i = 0; i < 3; i++)
                      TransactionDto(
                        id: '$i',
                        amount: '42.18',
                        currency: 'USD',
                        direction: 'expense',
                        status: 'active',
                        reviewState: needsReview ? 'needsReview' : 'clear',
                        createdAt: DateTime.utc(2026),
                        updatedAt: DateTime.utc(2026),
                        transactionDate: i == 2 ? '2026-09-03' : '2026-09-04',
                        description: 'Merchant $i',
                        paymentSourceId: 'visa',
                        tagIds: const ['family'],
                      ),
                  ],
                  masterData: const TransactionMasterData(
                    tagNames: {'family': '#family'},
                  ),
                  paymentSourceNames: const {'visa': 'Visa •••• 1234'},
                  missingCategoryLabel: 'Not categorized',
                  groupByFinancialDate: true,
                  showDateInRows: true,
                  supportingContentBuilder: (_, transaction) => Text(
                    needsReview
                        ? reason
                        : 'Category and subcategory are missing',
                    key: ValueKey('reason-${transaction.id}'),
                  ),
                  onTap: (transaction) => tapped = transaction.id,
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ButlerlyCard), findsNothing);
        expect(find.byType(Card), findsNothing);
        expect(find.byType(ButlerlyTransactionList), findsNWidgets(2));
        expect(find.byType(ButlerlyRecordRow), findsNWidgets(3));
        expect(
          find.byKey(const ValueKey('transaction-group-divider-1')),
          findsNothing,
        );
        expect(find.textContaining('Visa •••• 1234'), findsNWidgets(3));
        expect(find.textContaining('Not categorized'), findsNWidgets(3));
        expect(find.text('−42.18 USD'), findsNWidgets(3));
        expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

        final transactionTitle = tester.widget<Text>(find.text('Merchant 0'));
        final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
        expect(
          transactionTitle.style?.fontFamily,
          AppTheme.light.textTheme.bodyMedium?.fontFamily,
        );
        expect(
          transactionTitle.style?.fontFamily,
          isNot(ButlerlyTypography.editorialFontFamily),
        );
        expect(
          transactionTitle.style?.fontSize,
          ButlerlyTransactionItemTokens.titleFontSize,
        );
        expect(transactionTitle.style?.fontWeight, FontWeight.w600);
        expect(transactionTitle.style?.color, colors.primaryText);

        expect(
          tester.getTopLeft(find.byKey(const ValueKey('reason-0'))).dy,
          greaterThan(tester.getBottomLeft(find.text('#family').first).dy),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('reason-0'))).height,
          greaterThan(40),
        );
        await tester.tap(find.byKey(const ValueKey('reason-0')));
        expect(tapped, '0');
        expect(
          find.bySemanticsLabel(
            RegExp(
              needsReview ? 'Category conflicts' : 'Category and subcategory',
            ),
          ),
          findsWidgets,
        );
        semantics.dispose();
      },
    );
  }

  testWidgets('grouped transaction ledger avoids card surfaces in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: TransactionRecordList(
            transactions: [
              TransactionDto(
                id: 'dark-card',
                amount: '10.00',
                currency: 'USD',
                direction: 'expense',
                status: 'active',
                reviewState: 'needsReview',
                createdAt: DateTime.utc(2026),
                updatedAt: DateTime.utc(2026),
                transactionDate: '2026-09-04',
                description: 'Dark mode merchant',
              ),
            ],
            groupByFinancialDate: true,
            onTap: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(ButlerlyCard), findsNothing);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ButlerlyTransactionList), findsOneWidget);
    expect(find.byType(ButlerlyRecordRow), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transaction-group-divider-1')),
      findsNothing,
    );
  });

  testWidgets(
    'transaction and search ledger mode groups by month and shows row dates',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TransactionRecordList(
                transactions: [
                  TransactionDto(
                    id: 'sep-15',
                    amount: '12.00',
                    currency: 'USD',
                    direction: 'expense',
                    status: 'active',
                    reviewState: 'clear',
                    createdAt: DateTime.utc(2026),
                    updatedAt: DateTime.utc(2026),
                    transactionDate: '2026-09-15',
                    description: 'September merchant',
                  ),
                  TransactionDto(
                    id: 'sep-04',
                    amount: '8.00',
                    currency: 'USD',
                    direction: 'expense',
                    status: 'active',
                    reviewState: 'clear',
                    createdAt: DateTime.utc(2026),
                    updatedAt: DateTime.utc(2026),
                    transactionDate: '2026-09-04',
                    description: 'Another September merchant',
                  ),
                  TransactionDto(
                    id: 'aug-31',
                    amount: '5.00',
                    currency: 'USD',
                    direction: 'expense',
                    status: 'active',
                    reviewState: 'clear',
                    createdAt: DateTime.utc(2026),
                    updatedAt: DateTime.utc(2026),
                    transactionDate: '2026-08-31',
                    description: 'August merchant',
                  ),
                ],
                groupByFinancialDate: true,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('September 2026'), findsOneWidget);
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.byType(ButlerlyTransactionList), findsNWidgets(2));
      expect(find.textContaining('Sep 15, 2026'), findsOneWidget);
      expect(find.textContaining('Sep 4, 2026'), findsOneWidget);
      expect(find.textContaining('Aug 31, 2026'), findsOneWidget);
    },
  );
}
