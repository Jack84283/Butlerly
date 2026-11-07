import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/features/tools/presentation/payment_settlements_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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
        expect(find.byType(ButlerlySheet), findsOneWidget);
        expect(find.text('Choose a payment source to continue'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('settlement-create-payment-source')),
          findsOneWidget,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(ButlerlySheet), findsNothing);
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
        expect(find.text('Choose a payment source to continue'), findsNothing);
        expect(find.text('Add payment settlement'), findsAtLeastNWidgets(1));
        expect(tester.takeException(), isNull);
      },
    );
  }
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
