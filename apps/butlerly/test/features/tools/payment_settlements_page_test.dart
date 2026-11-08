import 'dart:async';

import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/features/tools/presentation/payment_settlements_page.dart';
import 'package:butlerly/features/tools/presentation/tools_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

  _TestSettlements registerServices(List<PaymentSource> sources) {
    final settlements = _TestSettlements();
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        _UnusedTransactions(),
        _TestSources(sources),
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
    expect(
      selector.entries.map((entry) => entry.value).toList(),
      ['visa', 'mastercard'],
    );
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
      await tester.tap(
        find.byKey(const ValueKey('payment-settlements-add')),
      );
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
      expect(
        tester.widget<TextFormField>(amount).controller!.text,
        '42.50',
      );

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

    Navigator.of(
      tester.element(find.byType(PaymentSourcesPage)),
    ).pop();
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
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-payment-settlements-table')),
      findsOneWidget,
    );
    expect(find.textContaining('Archived Visa'), findsAtLeastNWidgets(1));
    expect(
      find.byKey(const ValueKey('desktop-settlement-add-source')),
      findsOneWidget,
    );
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
    final settlements = registerServices(sources);
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
          builder: (_, state, child) => AdaptiveShell(
            location: state.uri.toString(),
            child: child,
          ),
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
    expect(find.text('Payment settlements'), findsOneWidget);
    await tester.tap(find.text('Payment settlements'));
    await tester.pumpAndSettle();

    expect(find.byType(PaymentSettlementsPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-settlement-payment-sources')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-payment-settlements-table')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settlement-eligible-source-card-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settlement-more-active-sources')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settlement-eligible-source-card-29')),
      findsNothing,
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
    await tester.ensureVisible(next);
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
          builder: (_, _) =>
              const Scaffold(body: PaymentSettlementsPage()),
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

  @override
  Future<List<PaymentSource>> listAll() async => sources;

  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async =>
      sources.where((source) => source.id == id).firstOrNull;

  @override
  Future<void> save(PaymentSource source) async => sources.add(source);
}

class _TestSettlements extends Fake implements PaymentSettlementRepository {
  final values = <PaymentSettlement>[];
  Future<List<PaymentSettlement>>? blockedList;

  @override
  Future<List<PaymentSettlement>> listAll() =>
      blockedList ?? Future.value(List.of(values));

  @override
  Future<PaymentSettlement?> findById(PaymentSettlementId id) async =>
      values.where((value) => value.id == id).firstOrNull;

  @override
  Future<void> save(PaymentSettlement settlement) async {
    values.removeWhere((value) => value.id == settlement.id);
    values.add(settlement);
  }
}

class _UnusedTransactions extends Fake implements TransactionRepository {}

class _UnusedMerchants extends Fake implements MerchantRepository {}

class _UnusedCategories extends Fake implements CategoryRepository {}

class _UnusedTags extends Fake implements TagRepository {}

class _UnusedEvidence extends Fake implements EvidenceRepository {}

class _UnusedPreferences extends Fake implements UserPreferenceRepository {}
