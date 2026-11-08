import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
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

  void registerFinance(List<PaymentSource> sources) {
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        _UnusedTransactions(),
        _SavedSources(sources),
        _UnusedMerchants(),
        _UnusedCategories(),
        _UnusedTags(),
        _UnusedEvidence(),
        _UnusedPreferences(),
        paymentSettlements: _SavedSettlements(),
      ),
    );
  }

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

  testWidgets('device + restores the original settlement bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    registerFinance([
      PaymentSource(
        id: PaymentSourceId('visa'),
        name: 'Visa',
        type: PaymentSourceType.card,
      ),
    ]);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final add = find.byKey(const ValueKey('payment-settlements-add'));
    expect(add, findsOneWidget);
    expect(tester.widget<IconButton>(add).onPressed, isNotNull);

    await tester.tap(add);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Add payment settlement'), findsAtLeastNWidgets(1));
    await tester.tap(find.widgetWithText(ButlerlyCancelButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(PaymentSettlementsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('device without a card retains its original disabled Add', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    registerFinance([]);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final add = find.byKey(const ValueKey('payment-settlements-add'));
    expect(add, findsOneWidget);
    expect(tester.widget<IconButton>(add).onPressed, isNull);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(PaymentSettlementsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _SavedSources extends Fake implements PaymentSourceRepository {
  _SavedSources(this.sources);

  final List<PaymentSource> sources;

  @override
  Future<List<PaymentSource>> listAll() async => sources;
}

class _SavedSettlements extends Fake implements PaymentSettlementRepository {
  @override
  Future<List<PaymentSettlement>> listAll() async => const [];
}

class _UnusedTransactions extends Fake implements TransactionRepository {}

class _UnusedMerchants extends Fake implements MerchantRepository {}

class _UnusedCategories extends Fake implements CategoryRepository {}

class _UnusedTags extends Fake implements TagRepository {}

class _UnusedEvidence extends Fake implements EvidenceRepository {}

class _UnusedPreferences extends Fake implements UserPreferenceRepository {}
