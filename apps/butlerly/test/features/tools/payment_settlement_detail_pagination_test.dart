import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_transaction_table.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
import 'package:butlerly/features/foundation/presentation/transaction_row.dart';
import 'package:butlerly/features/tools/presentation/payment_settlements_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in [390.0, 1400.0]) {
    testWidgets(
      'Settlement detail builds only 20 transaction rows per page at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repository = _Settlements(45);
        final finance = FinanceServices(
          _Transactions(),
          _PaymentSources(),
          _Merchants(),
          _Categories(),
          _Tags(),
          _Evidence(),
          _Preferences(),
          paymentSettlements: repository,
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
            home: PaymentSettlementDetailPage(
              finance: finance,
              settlementId: 'settlement',
              sourceNames: const {'card': 'Card'},
              sources: const [],
            ),
          ),
        );
        await tester.pumpAndSettle();

        final pager = find.byKey(
          const ValueKey('settlement-transaction-pagination'),
        );
        await tester.scrollUntilVisible(
          pager,
          150,
          scrollable: find.byType(Scrollable).first,
        );

        expect(
          find.byKey(const ValueKey('settlement-transaction-page-range')),
          findsOneWidget,
        );
        expect(find.text('1–20 / 45'), findsOneWidget);

        List<TransactionDto> visibleTransactions() {
          // Inspect the actual detail page's content contract, including when
          // the transaction card is below the viewport's lazy sliver.
          final page = tester.widget<ButlerlyPage>(
            find.byType(ButlerlyPage),
          );
          if (width >= 900) {
            return page.children
                .whereType<ButlerlyDesktopTransactionTableCard>()
                .single
                .transactions;
          }
          final inner = page.children
              .whereType<ButlerlyTransactionInnerCard>()
              .single;
          return (inner.child as ButlerlyTransactionList)
              .children
              .whereType<TransactionRow>()
              .map((row) => row.transaction)
              .toList();
        }

        expect(visibleTransactions(), hasLength(20));
        expect(visibleTransactions().first.id, 'tx-0');
        expect(visibleTransactions().last.id, 'tx-19');

        final next = find.byKey(
          const ValueKey('settlement-transaction-next'),
        );
        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text('21–40 / 45'), findsOneWidget);
        expect(visibleTransactions(), hasLength(20));
        expect(visibleTransactions().first.id, 'tx-20');
        expect(visibleTransactions().last.id, 'tx-39');

        await tester.tap(next);
        await tester.pumpAndSettle();
        expect(find.text('41–45 / 45'), findsOneWidget);
        expect(visibleTransactions(), hasLength(5));
        expect(visibleTransactions().first.id, 'tx-40');
        expect(visibleTransactions().last.id, 'tx-44');
        expect(tester.widget<IconButton>(next).onPressed, isNull);

        // A presentation-only page change must never requery the database.
        expect(repository.detailCalls, 1);
        expect(repository.transactionCalls, 1);

        await tester.tap(
          find.byKey(const ValueKey('settlement-transaction-previous')),
        );
        await tester.pumpAndSettle();
        expect(find.text('21–40 / 45'), findsOneWidget);

        final page = tester.widget<ButlerlyPage>(
          find.byType(ButlerlyPage),
        );
        await page.onRefresh!();
        await tester.pumpAndSettle();
        expect(find.text('1–20 / 45'), findsOneWidget);
        expect(repository.detailCalls, 2);
        expect(repository.transactionCalls, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Settlements extends Fake implements PaymentSettlementRepository {
  _Settlements(this.count);

  final int count;
  int detailCalls = 0;
  int transactionCalls = 0;

  @override
  Future<PaymentSettlement?> findById(PaymentSettlementId id) async {
    detailCalls++;
    final now = DateTime.utc(2026, 9, 20);
    return PaymentSettlement(
      id: PaymentSettlementId('settlement'),
      paymentSourceId: PaymentSourceId('card'),
      payment: Money(
        amount: DecimalValue.parse('45'),
        currency: CurrencyCode('USD'),
      ),
      paymentDate: '2026-09-20',
      periodStart: '2026-09-01',
      periodEnd: '2026-09-30',
      status: PaymentSettlementStatus.open,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<List<Transaction>> listTransactions(
    PaymentSettlement settlement, {
    DateTime? occurredAtFrom,
    DateTime? occurredAtToExclusive,
  }) async {
    transactionCalls++;
    final now = DateTime.utc(2026, 9, 12);
    return [
      for (var i = 0; i < count; i++)
        Transaction(
          id: TransactionId('tx-$i'),
          timing: KnownTransactionTime(now),
          money: Money(
            amount: DecimalValue.parse('1.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          sourceType: TransactionSourceType.manual,
          paymentSourceId: PaymentSourceId('card'),
          transactionDate: '2026-09-12',
          provenance: [
            Provenance(
              id: ProvenanceId('provenance-$i'),
              sourceType: ProvenanceSourceType.userEntry,
              capturedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
    ];
  }
}

class _Transactions extends Fake implements TransactionRepository {}

class _PaymentSources extends Fake implements PaymentSourceRepository {
  @override
  Future<List<PaymentSource>> listAll() async => [];
}

class _Merchants extends Fake implements MerchantRepository {
  @override
  Future<List<Merchant>> listAll() async => [];
}

class _Categories extends Fake implements CategoryRepository {
  @override
  Future<List<Category>> listAll() async => [];
}

class _Tags extends Fake implements TagRepository {
  @override
  Future<List<Tag>> listAll() async => [];
}

class _Evidence extends Fake implements EvidenceRepository {}

class _Preferences extends Fake implements UserPreferenceRepository {
  @override
  Future<UserPreference?> load() async => null;
}
