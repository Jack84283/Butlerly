import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/features/foundation/presentation/payment_sources_page.dart';
import 'package:butlerly/features/tools/presentation/payment_settlements_page.dart';
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

  void registerServices(List<PaymentSource> sources) {
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        _UnusedTransactions(),
        _TestSources(sources),
        _UnusedMerchants(),
        _UnusedCategories(),
        _UnusedTags(),
        _UnusedEvidence(),
        _UnusedPreferences(),
        paymentSettlements: _TestSettlements(),
      ),
    );
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

        // A missing card must navigate directly to the real create form,
        // rather than leaving the user in an inert prerequisite sheet.
        expect(find.byType(PaymentSourcesPage), findsOneWidget);
        expect(find.text('Add payment source'), findsAtLeastNWidgets(1));
        expect(
          find.byKey(const ValueKey('settlement-create-payment-source')),
          findsNothing,
        );
        if (width < 900) {
          expect(find.byType(ButlerlySheet), findsOneWidget);
          final types = find.byType(ButlerlySelectField<PaymentSourceType>);
          expect(types, findsOneWidget);
          expect(
            tester.widget<ButlerlySelectField<PaymentSourceType>>(types).value,
            PaymentSourceType.card,
          );
        } else {
          expect(find.byType(ButlerlySheet), findsNothing);
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
        expect(find.byType(ButlerlySheet), findsOneWidget);
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

  testWidgets(
    'creating a prerequisite credit card resumes the settlement editor',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sources = <PaymentSource>[];
      registerServices(sources);

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('payment-settlements-add')));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentSourcesPage), findsOneWidget);

      final name = find.widgetWithText(TextField, 'Name');
      final lastFour = find.widgetWithText(TextField, 'Last 4 digits');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Visa test card');
      await tester.ensureVisible(lastFour);
      await tester.enterText(lastFour, '1234');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(sources, hasLength(1));
      expect(sources.single.type, PaymentSourceType.card);
      expect(find.byType(PaymentSourcesPage), findsNothing);
      expect(find.byType(ButlerlySheet), findsOneWidget);
      expect(find.text('Add payment settlement'), findsAtLeastNWidgets(1));
      final selectedSource = find.byType(ButlerlySelectField<String>);
      expect(
        tester.widget<ButlerlySelectField<String>>(selectedSource).value,
        sources.single.id.value,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('settlement Add uses the app route for credit-card creation', (
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
          builder: (_, state) => Scaffold(
            body: PaymentSourcesPage(
              openCreateOnStart: state.uri.queryParameters['create'] == 'true',
              fromPaymentSettlement:
                  state.uri.queryParameters['from'] == 'settlements',
            ),
          ),
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
    await tester.tap(
      find.byKey(const ValueKey('payment-settlements-add')),
    );
    await tester.pumpAndSettle();

    final uri = router.routeInformationProvider.value.uri;
    expect(uri.path, '/payment-sources');
    expect(uri.queryParameters['create'], 'true');
    expect(uri.queryParameters['from'], 'settlements');
    expect(find.byType(PaymentSourcesPage), findsOneWidget);
    expect(find.byType(ButlerlySheet), findsOneWidget);
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
  @override
  Future<List<PaymentSettlement>> listAll() async => [];
}

class _UnusedTransactions extends Fake implements TransactionRepository {}

class _UnusedMerchants extends Fake implements MerchantRepository {}

class _UnusedCategories extends Fake implements CategoryRepository {}

class _UnusedTags extends Fake implements TagRepository {}

class _UnusedEvidence extends Fake implements EvidenceRepository {}

class _UnusedPreferences extends Fake implements UserPreferenceRepository {}
