import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
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
                  missingCategoryLabel: 'Not Categorized',
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
        expect(find.byType(ButlerlyCard), findsNWidgets(2));
        expect(find.byType(ButlerlyRecordRow), findsNWidgets(3));
        expect(find.text('Visa •••• 1234'), findsNWidgets(3));
        expect(find.text('Not Categorized'), findsNWidgets(3));
        expect(find.text('−42.18 USD'), findsNWidgets(3));
        expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
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
}
