import 'dart:async';

import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _Transactions transactions;
  late FinanceServices finance;

  setUp(() async {
    await services.reset();
    HomePage.debugCurrentDate = DateTime(2026, 9, 16, 15);
    transactions = _Transactions();
    finance = FinanceServices(
      transactions,
      _PaymentSources(),
      _Merchants(),
      _Categories(),
      _Tags(),
      _Evidence(),
      _Preferences(),
      analysisRules: _Rules([_expenseRule()]),
    );
    services.registerSingleton<FinanceServices>(finance);
    final seeded = await finance.createTransaction(
      CreateTransactionCommand(
        id: 'home-refresh-initial',
        provenanceId: 'home-refresh-initial-provenance',
        timing: KnownTransactionTime(DateTime.utc(2026, 9, 15, 12)),
        transactionDate: '2026-09-15',
        money: Money(
          amount: DecimalValue.parse('10.00'),
          currency: CurrencyCode('USD'),
        ),
        direction: TransactionDirection.expense,
        description: 'Initial Home spending',
      ),
    );
    expect(seeded, isA<ApplicationSuccess<TransactionDto>>());
  });

  tearDown(() async {
    HomePage.debugCurrentDate = null;
    await services.reset();
  });

  testWidgets(
    'Home keeps the pinned header and refreshes visible spending on a real iOS pull',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const _TestApp());
      await tester.pumpAndSettle();
      expect(find.text('10.00 USD'), findsOneWidget);

      final scrollFinder = find.byType(CustomScrollView);
      final scrollView = tester.widget<CustomScrollView>(scrollFinder);
      final headerIndex = scrollView.slivers.indexWhere(
        (sliver) => sliver is SliverPersistentHeader,
      );
      final refreshIndex = scrollView.slivers.indexWhere(
        (sliver) => sliver is CupertinoSliverRefreshControl,
      );
      expect(headerIndex, isNonNegative);
      expect(refreshIndex, isNonNegative);
      expect(headerIndex, lessThan(refreshIndex));
      expect(
        (scrollView.slivers[headerIndex] as SliverPersistentHeader).pinned,
        isTrue,
      );

      final refreshControl =
          scrollView.slivers[refreshIndex] as CupertinoSliverRefreshControl;
      expect(
        refreshControl.key,
        const ValueKey('home-cupertino-refresh-control'),
      );
      expect(refreshControl.onRefresh, isNotNull);
      expect(find.byKey(const ValueKey('home-refresh-indicator')), findsNothing);

      final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
      final canvas = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('home-page-canvas')),
      );
      final bodySurface = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('home-page-content-surface')),
      );
      expect(canvas.color, colors.subtleSurface);
      expect(bodySurface.color, colors.background);
      expect(canvas.color, isNot(bodySurface.color));

      final bodyPadding = tester.widget<Padding>(
        find.byKey(const ValueKey('home-page-content-padding')),
      );
      expect(
        bodyPadding.padding,
        const EdgeInsets.fromLTRB(
          ButlerlySize.phoneGutter,
          ButlerlySpacing.small,
          ButlerlySize.phoneGutter,
          ButlerlySpacing.large,
        ),
      );

      final added = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'home-refresh-added',
          provenanceId: 'home-refresh-added-provenance',
          timing: KnownTransactionTime(DateTime.utc(2026, 9, 16, 12)),
          transactionDate: '2026-09-16',
          money: Money(
            amount: DecimalValue.parse('5.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'Added Home spending',
        ),
      );
      expect(added, isA<ApplicationSuccess<TransactionDto>>());
      expect(find.text('10.00 USD'), findsOneWidget);
      expect(find.text('15.00 USD'), findsNothing);

      final readGate = Completer<void>();
      transactions.readGate = readGate.future;
      final bodyFinder = find.byKey(const ValueKey('home-body-data'));
      final headerFinder = find.byKey(const ValueKey('home-header-surface'));
      final beforeRefresh = (tester.widget(bodyFinder) as FutureBuilder).future;
      final headerTopBefore = tester.getTopLeft(headerFinder).dy;

      await tester.drag(scrollFinder, const Offset(0, 320));
      await tester.pump();

      // While the refresh read is deliberately held open, keep the existing
      // spending snapshot visible and keep the pinned header stationary.
      expect(find.text('10.00 USD'), findsOneWidget);
      expect(find.text('15.00 USD'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getTopLeft(headerFinder).dy, closeTo(headerTopBefore, 0.01));

      readGate.complete();
      transactions.readGate = null;
      await tester.pumpAndSettle();

      final afterRefresh = (tester.widget(bodyFinder) as FutureBuilder).future;
      expect(identical(beforeRefresh, afterRefresh), isFalse);
      expect(find.text('10.00 USD'), findsNothing);
      expect(find.text('15.00 USD'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getTopLeft(headerFinder).dy, closeTo(headerTopBefore, 0.01));

      expect(scrollView.physics, isA<BouncingScrollPhysics>());
      expect(
        (scrollView.physics! as BouncingScrollPhysics).parent,
        isA<AlwaysScrollableScrollPhysics>(),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.light,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const Scaffold(body: HomePage()),
  );
}

AnalysisRuleDefinition _expenseRule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R001'),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: 'ANL-R001',
  descriptionKey: 'ANL-R001',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(
    operation: RuleOperation.sum,
    field: 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
  ),
  grouping: RuleGrouping.none,
  baseline: RuleBaseline.none,
  condition: const RuleCondition(operator: 'none'),
  severity: RuleSeverity.info,
  surface: AnalysisSurface.overview,
  role: 'expenseTotal',
  filters: const [
    AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['expense']),
  ],
  definitionHash: RuleDefinitionHash('b' * 64),
);

final class _Transactions implements TransactionRepository {
  final values = <String, Transaction>{};
  Future<void>? readGate;

  Future<void> _waitForRead() async {
    if (readGate case final pending?) await pending;
  }

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async {
    await _waitForRead();
    return values.values.toList(growable: false);
  }

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async {
    await _waitForRead();
    return values.values.toList(growable: false);
  }

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
    values[transaction.id.value] = transaction;
  }
}

final class _Preferences implements UserPreferenceRepository {
  UserPreference value = UserPreference(
    locale: 'en',
    baseCurrency: CurrencyCode('USD'),
    timeZoneId: 'UTC',
  );

  @override
  Future<UserPreference?> load() async => value;

  @override
  Future<void> save(UserPreference preference) async {
    value = preference;
  }
}

final class _Rules implements AnalysisRuleRepository {
  _Rules(this.values);

  final List<AnalysisRuleDefinition> values;

  @override
  Future<List<AnalysisRuleDefinition>> listActive() async => values;

  @override
  Future<List<AnalysisRuleDefinition>> listDefinitions() async => values;

  @override
  Future<AnalysisRuleActivation?> existingActivation(RuleIdentity id) async =>
      null;

  @override
  Future<void> activate(
    RuleIdentity id,
    RuleVersion version,
    bool enabled,
    DateTime at,
  ) async {}

  @override
  Future<void> install(
    AnalysisRuleDefinition definition, {
    required String sourceType,
    required String canonicalDefinition,
  }) async {}
}

final class _PaymentSources implements PaymentSourceRepository {
  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async => null;

  @override
  Future<List<PaymentSource>> listAll() async => const [];

  @override
  Future<void> save(PaymentSource paymentSource) async {}
}

final class _Merchants implements MerchantRepository {
  @override
  Future<Merchant?> findById(MerchantId id) async => null;

  @override
  Future<List<Merchant>> listAll() async => const [];

  @override
  Future<void> save(Merchant merchant) async {}
}

final class _Categories implements CategoryRepository {
  @override
  Future<Category?> findById(CategoryId id) async => null;

  @override
  Future<List<Category>> listAll() async => const [];

  @override
  Future<void> save(Category category) async {}
}

final class _Tags implements TagRepository {
  @override
  Future<Tag?> findById(TagId id) async => null;

  @override
  Future<List<Tag>> listAll() async => const [];

  @override
  Future<void> save(Tag tag) async {}
}

final class _Evidence implements EvidenceRepository {
  @override
  Future<EvidenceItem?> findById(EvidenceId id) async => null;

  @override
  Future<void> link(AttachmentLink link) async {}

  @override
  Future<List<EvidenceItem>> listForTransaction(TransactionId id) async =>
      const [];

  @override
  Future<void> remove(EvidenceId id) async {}

  @override
  Future<void> save(EvidenceItem evidence) async {}

  @override
  Future<void> saveExtraction(Extraction extraction) async {}
}
