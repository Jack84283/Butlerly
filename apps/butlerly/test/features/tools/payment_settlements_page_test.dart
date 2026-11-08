import 'dart:async';
import 'dart:io';

import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/features/desktop/presentation/desktop_transaction_detail_split_view.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/features/tools/presentation/payment_settlements_page.dart';
import 'package:butlerly/features/tools/presentation/tools_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async => services.reset());
  tearDown(() => services.reset());

  Widget app() => const MaterialApp(
    localizationsDelegates: [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: PaymentSettlementsPage()),
  );

  _TestSettlements registerServices(
    List<PaymentSource> sources, {
    _TestSources? sourceRepository,
  }) {
    final settlements = _TestSettlements();
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        _UnusedTransactions(),
        sourceRepository ?? _TestSources(sources),
        _UnusedMerchants(),
        _UnusedCategories(),
        _UnusedTags(),
        _UnusedEvidence(),
        _UnusedPreferences(),
        paymentSettlements: settlements,
      ),
    );
    return settlements;
  }

  for (final width in [390.0, 1400.0]) {
    testWidgets(
      'Payment Settlements Add stays enabled and guides setup at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        registerServices([]);
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();

        final add = find.byKey(const ValueKey('payment-settlements-add'));
        expect(add, findsOneWidget);
        expect(tester.widget<IconButton>(add).onPressed, isNotNull);
        expect(
          tester
              .widget<ButlerlyHeaderAddButton>(
                find.byType(ButlerlyHeaderAddButton),
              )
              .closeToHelp,
          isTrue,
        );

        await tester.tap(add);
        await tester.pumpAndSettle();

        if (width < 900) {
          // Device mode must always show the actual settlement bottom sheet.
          // Having zero eligible cards is an inline prerequisite, not a route
          // change to Add Payment Source.
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(find.byType(PaymentSourcesPage), findsNothing);
          expect(
            find.byKey(const ValueKey('payment-settlement-editor-page')),
            findsNothing,
          );
          expect(find.text('Add payment settlement'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('settlement-no-eligible-source')),
            findsOneWidget,
          );
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('payment-settlement-submit-error')),
            findsOneWidget,
          );
          await tester.tap(find.widgetWithText(ButlerlyCancelButton, 'Cancel'));
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
        } else {
          // Desktop prerequisite navigation is intentionally unchanged.
          expect(find.byType(PaymentSourcesPage), findsOneWidget);
          expect(
            find.byKey(const ValueKey('desktop-payment-source-workspace')),
            findsOneWidget,
          );
          expect(find.byType(BottomSheet), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Payment Settlements Add opens its editor with a card at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        registerServices([
          PaymentSource(
            id: PaymentSourceId('visa'),
            name: 'Visa',
            type: PaymentSourceType.card,
          ),
        ]);
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();

        final add = find.byKey(const ValueKey('payment-settlements-add'));
        expect(tester.widget<IconButton>(add).onPressed, isNotNull);
        await tester.tap(add);
        await tester.pumpAndSettle();
        if (width < 900) {
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(
            find.byKey(const ValueKey('payment-settlement-editor-page')),
            findsNothing,
          );
        } else {
          expect(
            find.byKey(const ValueKey('payment-settlement-editor-page')),
            findsOneWidget,
          );
          expect(find.byType(BottomSheet), findsNothing);
        }
        expect(find.byType(PaymentSourcesPage), findsNothing);
        expect(find.text('Add payment settlement'), findsAtLeastNWidgets(1));
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await tester.pumpAndSettle();
        // A validation failure must be visible in the sheet's fixed action
        // area, even when the relevant form field has been scrolled away.
        expect(
          find.byKey(const ValueKey('payment-settlement-submit-error')),
          findsOneWidget,
        );
        expect(find.text('Enter a valid amount.'), findsAtLeastNWidgets(1));
        final source = find.byType(ButlerlySelectField<String>);
        expect(source, findsOneWidget);
        expect(
          tester.widget<ButlerlySelectField<String>>(source).value,
          'visa',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('device sheet offers only eligible credit-card sources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    registerServices([
      PaymentSource(
        id: PaymentSourceId('visa'),
        name: 'Visa',
        type: PaymentSourceType.card,
      ),
      PaymentSource(
        id: PaymentSourceId('mastercard'),
        name: 'Mastercard',
        type: PaymentSourceType.card,
      ),
      PaymentSource(
        id: PaymentSourceId('cash'),
        name: 'Cash',
        type: PaymentSourceType.cash,
      ),
      PaymentSource(
        id: PaymentSourceId('archived'),
        name: 'Archived',
        type: PaymentSourceType.card,
        status: PaymentSourceStatus.archived,
      ),
    ]);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-settlements-add')));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(PaymentSourcesPage), findsNothing);
    final selector = tester.widget<ButlerlySelectField<String>>(
      find.byType(ButlerlySelectField<String>),
    );
    expect(selector.entries.map((entry) => entry.value).toList(), [
      'visa',
      'mastercard',
    ]);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1400.0]) {
    testWidgets('settlement form accepts typing and Save at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settlements = registerServices([
        PaymentSource(
          id: PaymentSourceId('visa'),
          name: 'Visa',
          type: PaymentSourceType.card,
          currency: 'USD',
        ),
      ]);

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-settlements-add')));
      await tester.pumpAndSettle();

      // Device uses the original bottom sheet; desktop keeps the page editor.
      if (width < 900) {
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(
          find.byKey(const ValueKey('payment-settlement-editor-page')),
          findsNothing,
        );
      } else {
        expect(
          find.byKey(const ValueKey('payment-settlement-editor-page')),
          findsOneWidget,
        );
        expect(find.byType(BottomSheet), findsNothing);
      }
      final amount = find.widgetWithText(TextFormField, 'Amount');
      expect(amount, findsOneWidget);
      await tester.enterText(amount, '42.50');
      await tester.pump();
      expect(tester.widget<TextFormField>(amount).controller!.text, '42.50');

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(settlements.values, hasLength(1));
      expect(
        settlements.values.single.payment.amount,
        DecimalValue.parse('42.50'),
      );
      expect(settlements.values.single.paymentSourceId.value, 'visa');
      expect(
        find.byKey(const ValueKey('payment-settlement-editor-page')),
        findsNothing,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop shows eligible cards alongside settlement history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    registerServices([
      PaymentSource(
        id: PaymentSourceId('visa'),
        name: 'Visa',
        type: PaymentSourceType.card,
        lastFour: '1234',
      ),
      PaymentSource(
        id: PaymentSourceId('cash'),
        name: 'Cash',
        type: PaymentSourceType.cash,
      ),
    ]);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // Entry is independent of the unrelated Payment Sources repository.
    expect(
      find.byKey(const ValueKey('desktop-settlement-payment-sources')),
      findsNothing,
    );
    // Legacy Add resolves source metadata only after the user requests it.
    await tester.tap(find.byKey(const ValueKey('payment-settlements-add')));
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('payment-settlement-editor-page'));
    expect(editor, findsOneWidget);
    Navigator.of(tester.element(editor)).pop();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-settlement-payment-sources')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settlement-eligible-source-visa')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settlement-eligible-source-cash')),
      findsNothing,
    );
    final manage = find.byKey(
      const ValueKey('desktop-settlement-manage-sources'),
    );
    expect(manage, findsOneWidget);
    await tester.tap(manage);
    await tester.pumpAndSettle();
    expect(find.byType(PaymentSourcesPage), findsOneWidget);

    Navigator.of(tester.element(find.byType(PaymentSourcesPage))).pop();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-settlement-payment-sources')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop never hides saved settlements for an archived card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final saved = registerServices([
      PaymentSource(
        id: PaymentSourceId('archived-visa'),
        name: 'Archived Visa',
        type: PaymentSourceType.card,
        status: PaymentSourceStatus.archived,
        lastFour: '4321',
      ),
    ]);
    final now = DateTime.utc(2026, 11, 7);
    saved.values.add(
      PaymentSettlement(
        id: PaymentSettlementId('past-settlement'),
        paymentSourceId: PaymentSourceId('archived-visa'),
        payment: Money(
          amount: DecimalValue.parse('80.00'),
          currency: CurrencyCode('USD'),
        ),
        paymentDate: '2026-10-05',
        periodStart: '2026-09-01',
        periodEnd: '2026-09-30',
        status: PaymentSettlementStatus.open,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-settlement-payment-sources')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktop-payment-settlements-table')),
      findsOneWidget,
    );
    expect(find.textContaining('archived-visa'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop source setup Cancel returns to settlements', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    registerServices([]);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-settlements-add')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-payment-source-workspace')),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.widgetWithText(ButlerlyCancelButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(PaymentSourcesPage), findsNothing);
    expect(
      find.byKey(const ValueKey('desktop-settlement-payment-sources')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop card setup returns to tappable settlement editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sources = <PaymentSource>[];
    registerServices(sources);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-settlements-add')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-payment-source-workspace')),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Desktop Visa',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Last 4 digits'),
      '1234',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(sources, hasLength(1));
    expect(sources.single.type, PaymentSourceType.card);
    expect(sources.single.status, PaymentSourceStatus.active);
    expect(
      find.byKey(const ValueKey('payment-settlement-editor-page')),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsNothing);

    final amount = find.widgetWithText(TextFormField, 'Amount');
    await tester.enterText(amount, '50.00');
    await tester.pump();
    expect(tester.widget<TextFormField>(amount).controller!.text, '50.00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Tools opens real settlements with bounded rendering', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sources = List.generate(
      30,
      (index) => PaymentSource(
        id: PaymentSourceId('card-$index'),
        name: 'Card $index',
        type: PaymentSourceType.card,
        lastFour: index.toString().padLeft(4, '0'),
      ),
    );
    final sourceRepository = _TestSources(sources);
    final settlements = registerServices(
      sources,
      sourceRepository: sourceRepository,
    );
    final now = DateTime.utc(2026, 11, 7);
    settlements.values.addAll(
      List.generate(
        105,
        (index) => PaymentSettlement(
          id: PaymentSettlementId('settlement-$index'),
          paymentSourceId: PaymentSourceId('card-${index % 30}'),
          payment: Money(
            amount: DecimalValue.parse('50.00'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-10-05',
          periodStart: '2026-09-01',
          periodEnd: '2026-09-30',
          status: PaymentSettlementStatus.open,
          createdAt: now,
          updatedAt: now,
        ),
      ),
    );

    final router = GoRouter(
      initialLocation: '/tools',
      routes: [
        ShellRoute(
          // Match the real desktop navigation shell, not a bare test route.
          builder: (_, state, child) =>
              AdaptiveShell(location: state.uri.toString(), child: child),
          routes: [
            GoRoute(path: '/tools', builder: (_, _) => const ToolsPage()),
            GoRoute(
              path: '/payment-settlements',
              builder: (_, _) => const Scaffold(body: PaymentSettlementsPage()),
            ),
          ],
        ),
        GoRoute(
          path: '/help',
          builder: (_, _) => const Scaffold(body: Text('Help')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Payment settlements'), findsOneWidget);
    await tester.tap(find.text('Payment settlements'));
    await tester.pumpAndSettle();

    expect(find.byType(PaymentSettlementsPage), findsOneWidget);
    expect(sourceRepository.listCalls, 0);
    expect(
      find.byKey(const ValueKey('desktop-settlement-payment-sources')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktop-payment-settlements-table')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-payment-settlement-settlement-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-payment-settlement-settlement-20')),
      findsNothing,
    );
    final next = find.byKey(const ValueKey('settlement-page-next'));
    expect(next, findsOneWidget);
    expect(tester.widget<IconButton>(next).onPressed, isNotNull);
    // Page navigation now sits above the long table, within the viewport.
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('desktop-payment-settlement-settlement-0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktop-payment-settlement-settlement-20')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop settlement detail stays in a closeable right panel',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sources = _TestSources([]);
      final pending = Completer<List<PaymentSource>>();
      sources.blockedList = pending.future;
      final settlements = registerServices([], sourceRepository: sources);
      settlements.values.add(
        PaymentSettlement(
          id: PaymentSettlementId('panel-record'),
          paymentSourceId: PaymentSourceId('legacy-source'),
          payment: Money(
            amount: DecimalValue.parse('42.50'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-10-05',
          periodStart: '2026-09-01',
          periodEnd: '2026-09-30',
          status: PaymentSettlementStatus.open,
          createdAt: DateTime.utc(2026, 11, 7),
          updatedAt: DateTime.utc(2026, 11, 7),
        ),
      );

      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump();
      final row = find.byKey(
        const ValueKey('desktop-payment-settlement-panel-record'),
      );
      expect(row, findsOneWidget);
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-transaction-detail-panel')),
        findsOneWidget,
      );
      expect(find.byType(PaymentSettlementsPage), findsOneWidget);
      expect(find.byType(PaymentSettlementDetailPage), findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktop-payment-settlements-table')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('desktop-settlement-detail-close')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('desktop-transaction-detail-panel')),
        findsNothing,
      );
      expect(find.byType(PaymentSettlementsPage), findsOneWidget);
      pending.complete([]);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [900.0, 1200.0, 1400.0]) {
    testWidgets(
      'desktop right detail uses compact transaction rows at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final sources = _TestSources([]);
        final settlements = registerServices([], sourceRepository: sources);
        final now = DateTime.utc(2026, 11, 7);
        settlements.values.add(
          PaymentSettlement(
            id: PaymentSettlementId('compact-panel'),
            paymentSourceId: PaymentSourceId('legacy-import'),
            payment: Money(
              amount: DecimalValue.parse('42.50'),
              currency: CurrencyCode('USD'),
            ),
            paymentDate: '2026-10-05',
            periodStart: '2026-09-01',
            periodEnd: '2026-09-30',
            status: PaymentSettlementStatus.open,
            createdAt: now,
            updatedAt: now,
          ),
        );
        settlements.transactionResults.add(
          Transaction(
            id: TransactionId('import-transaction'),
            timing: KnownTransactionTime(DateTime.utc(2026, 9, 15)),
            money: Money(
              amount: DecimalValue.parse('42.50'),
              currency: CurrencyCode('USD'),
            ),
            direction: TransactionDirection.expense,
            sourceType: TransactionSourceType.import,
            description: 'Imported statement purchase',
            provenance: [
              Provenance(
                id: ProvenanceId('compact-panel-provenance'),
                sourceType: ProvenanceSourceType.import,
                sourceId: 'statement-row-one',
                originalRepresentation: '2026-09-15 Purchase USD 42.50',
                capturedAt: now,
              ),
            ],
            createdAt: now,
            updatedAt: now,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: DesktopTransactionDetailSplitView(
                results: const SizedBox.expand(),
                detail: PaymentSettlementDetailPage(
                  finance: services<FinanceServices>(),
                  settlementId: 'compact-panel',
                  sourceNames: const {},
                  sources: const [],
                  embedded: true,
                  onClose: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('desktop-transaction-detail-panel')),
          findsOneWidget,
        );
        // Transactions can start below the fold in a 350px-wide detail
        // pane. Scroll the pane rather than assuming a lazy sliver mounted it.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('settlement-detail-compact-transactions')),
          120,
          scrollable: find
              .descendant(
                of: find.byType(PaymentSettlementDetailPage),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('settlement-detail-compact-transactions')),
          findsOneWidget,
        );
        expect(find.text('Imported statement purchase'), findsOneWidget);
        expect(sources.listCalls, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'device detail opens and closes with source metadata unavailable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sources = _TestSources([]);
      final pending = Completer<List<PaymentSource>>();
      sources.blockedList = pending.future;
      final settlements = registerServices([], sourceRepository: sources);
      settlements.values.add(
        PaymentSettlement(
          id: PaymentSettlementId('delayed-label'),
          paymentSourceId: PaymentSourceId('legacy-source'),
          payment: Money(
            amount: DecimalValue.parse('12.00'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-10-05',
          periodStart: '2026-09-01',
          periodEnd: '2026-09-30',
          status: PaymentSettlementStatus.open,
          createdAt: DateTime.utc(2026, 11, 7),
          updatedAt: DateTime.utc(2026, 11, 7),
        ),
      );

      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('legacy-source').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(PaymentSettlementDetailPage), findsOneWidget);

      Navigator.of(
        tester.element(find.byType(PaymentSettlementDetailPage)),
      ).pop();
      await tester.pumpAndSettle();
      expect(find.byType(PaymentSettlementsPage), findsOneWidget);
      pending.complete([]);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('device entry displays only one history page at a time', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sourceRepository = _TestSources([]);
    final settlements = registerServices(
      [],
      sourceRepository: sourceRepository,
    );
    settlements.values.addAll(
      List.generate(
        75,
        (index) => PaymentSettlement(
          id: PaymentSettlementId('page-$index'),
          paymentSourceId: PaymentSourceId('legacy-$index'),
          payment: Money(
            amount: DecimalValue.parse('42.00'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-10-05',
          periodStart: '2026-09-01',
          periodEnd: '2026-09-30',
          status: PaymentSettlementStatus.open,
          createdAt: DateTime.utc(2026, 11, 7),
          updatedAt: DateTime.utc(2026, 11, 7),
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(sourceRepository.listCalls, 0);
    // Off-screen sliver children are not required to be mounted.
    // Verify the visible first record and the authoritative pager range.
    expect(find.text('legacy-0'), findsOneWidget);
    expect(find.text('1–20 / 75'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('device-settlement-page-range')),
      findsOneWidget,
    );
    final next = find.byKey(const ValueKey('device-settlement-page-next'));
    expect(tester.widget<IconButton>(next).onPressed, isNotNull);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('21–40 / 75'), findsOneWidget);
    expect(find.text('legacy-0'), findsNothing);
    // Check the selected range instead of assuming an off-screen card is
    // mounted by the lazily rendered SliverList.
    expect(sourceRepository.listCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'device opens and leaves real SQLite settlement history without source reads',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      sqfliteFfiInit();
      final database = ButlerlyDatabase(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
        schemaSql: await File(
          '../../packages/butlerly_database/database/schema/v1.sql',
        ).readAsString(),
      );
      await database.open(seedSystemDataOnOpen: false);
      addTearDown(() => database.close());
      await database.connection.insert('payment_sources', {
        'id': 'legacy-import',
        'name': 'Legacy import',
        'type': PaymentSourceType.card.name,
        'status': PaymentSourceStatus.active.name,
      });
      final repository = SqlitePaymentSettlementRepository(database);
      final now = DateTime.utc(2026, 11, 7);
      for (var index = 0; index < 75; index++) {
        await repository.save(
          PaymentSettlement(
            id: PaymentSettlementId('sqlite-settlement-$index'),
            paymentSourceId: PaymentSourceId('legacy-import'),
            payment: Money(
              amount: DecimalValue.parse('42.00'),
              currency: CurrencyCode('USD'),
            ),
            paymentDate: '2026-10-05',
            periodStart: '2026-09-01',
            periodEnd: '2026-09-30',
            status: PaymentSettlementStatus.open,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      // Exercise the detail path with actual imported transactions.
      // Previously this test only opened the settlement list and could
      // never detect a slow N+1 detail hydration query.
      final importedTransactions = SqliteTransactionRepository(database);
      for (var index = 0; index < 50; index++) {
        final at = DateTime.utc(2026, 9, 15, 12, index % 60);
        await importedTransactions.save(
          Transaction(
            id: TransactionId('sqlite-import-$index'),
            timing: KnownTransactionTime(at),
            money: Money(
              amount: DecimalValue.parse('5.00'),
              currency: CurrencyCode('USD'),
            ),
            direction: TransactionDirection.expense,
            sourceType: TransactionSourceType.import,
            paymentSourceId: PaymentSourceId('legacy-import'),
            transactionDate: '2026-09-15',
            description: 'Statement purchase $index',
            provenance: [
              Provenance(
                id: ProvenanceId('sqlite-import-provenance-$index'),
                sourceType: ProvenanceSourceType.import,
                sourceId: 'statement-row-$index',
                originalRepresentation: '2026-09-15 purchase 5.00',
                capturedAt: at,
              ),
            ],
            createdAt: at,
            updatedAt: at,
          ),
        );
      }
      final sources = _TestSources([]);
      services.registerSingleton<FinanceServices>(
        FinanceServices(
          _UnusedTransactions(),
          sources,
          _UnusedMerchants(),
          _UnusedCategories(),
          _UnusedTags(),
          _UnusedEvidence(),
          _UnusedPreferences(),
          paymentSettlements: repository,
        ),
      );
      final router = GoRouter(
        initialLocation: '/tools',
        routes: [
          ShellRoute(
            builder: (_, state, child) =>
                AdaptiveShell(location: state.uri.toString(), child: child),
            routes: [
              GoRoute(path: '/tools', builder: (_, _) => const ToolsPage()),
              GoRoute(
                path: '/payment-settlements',
                builder: (_, _) =>
                    const Scaffold(body: PaymentSettlementsPage()),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Payment settlements'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentSettlementsPage), findsOneWidget);
      expect(find.text('1–20 / 75'), findsOneWidget);
      expect(sources.listCalls, 0);
      await tester.tap(
        find.byKey(const ValueKey('device-settlement-page-next')),
      );
      await tester.pumpAndSettle();
      expect(find.text('21–40 / 75'), findsOneWidget);
      expect(sources.listCalls, 0);

      // Open a saved settlement, fetch 50 matching imported transactions
      // from real SQLite, paginate, close, and then navigate back to Tools.
      final settlementCard = find.text('legacy-import').first;
      await tester.ensureVisible(settlementCard);
      await tester.tap(settlementCard);
      await tester.pumpAndSettle();
      expect(find.byType(PaymentSettlementDetailPage), findsOneWidget);
      expect(sources.listCalls, 0);

      final detailScroll = find
          .descendant(
            of: find.byType(PaymentSettlementDetailPage),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settlement-detail-transaction-next')),
        180,
        scrollable: detailScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('1–20 / 50'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('settlement-detail-transaction-next')),
      );
      await tester.pumpAndSettle();
      expect(find.text('21–40 / 50'), findsOneWidget);
      expect(sources.listCalls, 0);

      Navigator.of(
        tester.element(find.byType(PaymentSettlementDetailPage)),
      ).pop();
      await tester.pumpAndSettle();
      expect(find.byType(PaymentSettlementsPage), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ToolsPage), findsOneWidget);
      expect(find.byType(PaymentSettlementsPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop paints before reads and never overlaps SQLite reads', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sources = _TestSources([]);
    final settlements = registerServices([], sourceRepository: sources);
    final deferred = Completer<List<PaymentSettlement>>();
    settlements.blockedList = deferred.future;

    await tester.pumpWidget(app());
    // The route can paint its title even while SQLite has not answered.
    expect(find.text('Payment settlements'), findsOneWidget);
    expect(find.text('Loading…'), findsOneWidget);
    // The source query must not race a still-in-flight settlement query.
    expect(sources.listCalls, 0);

    deferred.complete([]);
    await tester.pumpAndSettle();
    expect(sources.listCalls, 0);
    expect(
      find.byKey(const ValueKey('desktop-settlement-payment-sources')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop history stays visible if Payment Sources cannot finish loading',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sources = _TestSources([]);
      // Deliberately never complete this source query. Settlement history
      // must remain accessible, without waiting for the source timeout.
      sources.blockedList = Completer<List<PaymentSource>>().future;
      final settlements = registerServices([], sourceRepository: sources);
      settlements.values.add(
        PaymentSettlement(
          id: PaymentSettlementId('history-only'),
          paymentSourceId: PaymentSourceId('archived-card'),
          payment: Money(
            amount: DecimalValue.parse('60.00'),
            currency: CurrencyCode('USD'),
          ),
          paymentDate: '2026-10-05',
          periodStart: '2026-09-01',
          periodEnd: '2026-09-30',
          status: PaymentSettlementStatus.open,
          createdAt: DateTime.utc(2026, 11, 7),
          updatedAt: DateTime.utc(2026, 11, 7),
        ),
      );

      await tester.pumpWidget(app());
      await tester.pump();
      await tester.pump();

      expect(sources.listCalls, 0);
      expect(find.text('Payment settlements'), findsAtLeastNWidgets(1));
      expect(
        find.byKey(const ValueKey('desktop-payment-settlements-table')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-payment-settlement-history-only')),
        findsOneWidget,
      );
      // A source lookup must not be issued unless Add was explicitly tapped.
      final add = find.byKey(const ValueKey('payment-settlements-add'));
      expect(tester.widget<IconButton>(add).onPressed, isNotNull);

      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      expect(sources.listCalls, 0);
      expect(find.text('Try again'), findsNothing);
      expect(
        find.byKey(const ValueKey('desktop-payment-settlements-table')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-payment-settlement-history-only')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 1400.0]) {
    testWidgets(
      'Tools navigation remains responsive with a stalled settlement read '
      'at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final settlements = registerServices([]);
        final deferred = Completer<List<PaymentSettlement>>();
        settlements.blockedList = deferred.future;

        final router = GoRouter(
          initialLocation: '/tools',
          routes: [
            ShellRoute(
              builder: (_, state, child) =>
                  AdaptiveShell(location: state.uri.toString(), child: child),
              routes: [
                GoRoute(path: '/tools', builder: (_, _) => const ToolsPage()),
                GoRoute(
                  path: '/payment-settlements',
                  builder: (_, _) =>
                      const Scaffold(body: PaymentSettlementsPage()),
                ),
              ],
            ),
            GoRoute(
              path: '/help',
              builder: (_, _) => const Scaffold(body: Text('Help')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Payment settlements'));
        // A GoRouter push transition needs an elapsed frame; pumpAndSettle
        // cannot be used while the deliberately stalled spinner is active.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(PaymentSettlementsPage), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // Navigation must work even though the database never responds.
        router.pop();
        await tester.pumpAndSettle();
        expect(find.byType(ToolsPage), findsOneWidget);
        expect(find.byType(PaymentSettlementsPage), findsNothing);
        // Release the fake database read after leaving the page. This
        // cancels the Future.timeout timer without reopening the route.
        deferred.complete([]);
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'no premature Add Payment Source before card lookup at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sources = _TestSources([
          PaymentSource(
            id: PaymentSourceId('existing-visa'),
            name: 'Existing Visa',
            type: PaymentSourceType.card,
          ),
        ]);
        final pendingSources = Completer<List<PaymentSource>>();
        sources.blockedList = pendingSources.future;
        registerServices([], sourceRepository: sources);

        await tester.pumpWidget(app());
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('payment-settlements-add')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('payment-settlements-add')),
              )
              .onPressed,
          isNotNull,
        );
        expect(sources.listCalls, 0);
        expect(find.text('Add payment source'), findsNothing);
        expect(find.byType(PaymentSourcesPage), findsNothing);

        await tester.tap(find.byKey(const ValueKey('payment-settlements-add')));
        await tester.pump();
        expect(sources.listCalls, 1);
        pendingSources.complete(sources.sources);
        await tester.pumpAndSettle();
        expect(find.byType(PaymentSourcesPage), findsNothing);
        if (width < 900) {
          expect(find.byType(BottomSheet), findsOneWidget);
        } else {
          expect(
            find.byKey(const ValueKey('payment-settlement-editor-page')),
            findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('retry payment sources without reloading settlement history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final sources = _TestSources([]);
    sources.blockedList = Completer<List<PaymentSource>>().future;
    final settlements = registerServices([], sourceRepository: sources);
    settlements.values.add(
      PaymentSettlement(
        id: PaymentSettlementId('saved-history'),
        paymentSourceId: PaymentSourceId('archived-card'),
        payment: Money(
          amount: DecimalValue.parse('15.00'),
          currency: CurrencyCode('USD'),
        ),
        paymentDate: '2026-10-05',
        periodStart: '2026-09-01',
        periodEnd: '2026-09-30',
        status: PaymentSettlementStatus.open,
        createdAt: DateTime.utc(2026, 11, 7),
        updatedAt: DateTime.utc(2026, 11, 7),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pump();
    await tester.pump();
    expect(settlements.listCalls, 1);
    expect(sources.listCalls, 0);
    await tester.tap(find.byKey(const ValueKey('payment-settlements-add')));
    await tester.pump();
    expect(sources.listCalls, 1);
    await tester.pump(const Duration(seconds: 9));
    await tester.pump();
    expect(find.text('Try again'), findsAtLeastNWidgets(1));

    sources.blockedList = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pumpAndSettle();

    expect(settlements.listCalls, 1);
    expect(sources.listCalls, 2);
    expect(
      find.byKey(const ValueKey('desktop-payment-settlement-saved-history')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-settlement-payment-sources')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stalled initial read resolves to retry instead of spinning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settlements = registerServices([]);
    settlements.blockedList = Completer<List<PaymentSettlement>>().future;

    await tester.pumpWidget(app());
    // Even with a stalled read, the page header stays visible instead of
    // replacing the whole route with an unlabelled spinner.
    expect(find.byType(ButlerlyPage), findsOneWidget);
    expect(find.text('Payment settlements'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Loading…'), findsOneWidget);
    // Advance the widget-test clock beyond the bounded load deadline.
    await tester.pump(const Duration(seconds: 21));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(ButlerlyPage), findsOneWidget);
    expect(find.text('Payment settlements'), findsAtLeastNWidgets(1));
    expect(find.text('Try again'), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('device + never redirects to Payment Sources under GoRouter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    registerServices([]);

    final router = GoRouter(
      initialLocation: '/payment-settlements',
      routes: [
        GoRoute(
          path: '/payment-settlements',
          builder: (_, _) => const Scaffold(body: PaymentSettlementsPage()),
        ),
        GoRoute(
          path: '/payment-sources',
          builder: (_, _) =>
              const Scaffold(body: Text('unexpected-payment-sources-route')),
        ),
        GoRoute(
          path: '/help',
          builder: (_, _) => const Scaffold(body: Text('Help')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('payment-settlements-add')));
    await tester.pumpAndSettle();

    expect(
      router.routeInformationProvider.value.uri.path,
      '/payment-settlements',
    );
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Add payment settlement'), findsOneWidget);
    expect(find.text('unexpected-payment-sources-route'), findsNothing);
    expect(
      find.byKey(const ValueKey('settlement-no-eligible-source')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _TestSources extends Fake implements PaymentSourceRepository {
  _TestSources(this.sources);

  final List<PaymentSource> sources;
  Future<List<PaymentSource>>? blockedList;
  int listCalls = 0;

  @override
  Future<List<PaymentSource>> listAll() {
    listCalls++;
    return blockedList ?? Future.value(sources);
  }

  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async =>
      sources.where((source) => source.id == id).firstOrNull;

  @override
  Future<void> save(PaymentSource source) async => sources.add(source);
}

class _TestSettlements extends Fake implements PaymentSettlementRepository {
  final values = <PaymentSettlement>[];
  final transactionResults = <Transaction>[];
  Future<List<PaymentSettlement>>? blockedList;
  int listCalls = 0;

  @override
  Future<List<PaymentSettlement>> listAll() {
    listCalls++;
    return blockedList ?? Future.value(List.of(values));
  }

  @override
  Future<PaymentSettlement?> findById(PaymentSettlementId id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<void> save(PaymentSettlement settlement) async {
    values.removeWhere((value) => value.id == settlement.id);
    values.add(settlement);
  }

  @override
  Future<List<Transaction>> listTransactions(
    PaymentSettlement settlement, {
    DateTime? occurredAtFrom,
    DateTime? occurredAtToExclusive,
  }) async => transactionResults;
}

class _UnusedTransactions extends Fake implements TransactionRepository {}

class _UnusedMerchants extends Fake implements MerchantRepository {}

class _UnusedCategories extends Fake implements CategoryRepository {}

class _UnusedTags extends Fake implements TagRepository {}

class _UnusedEvidence extends Fake implements EvidenceRepository {}

class _UnusedPreferences extends Fake implements UserPreferenceRepository {}
