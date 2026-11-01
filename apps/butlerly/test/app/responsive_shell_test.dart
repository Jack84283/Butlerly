import 'dart:async';
import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/shell/compact/compact_primary_shell.dart';
import 'package:butlerly/app/shell/medium/medium_primary_shell.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly/design_system/components/butlerly_brand_icon.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_page.dart';
import 'package:butlerly/features/desktop/presentation/desktop_primary_shell.dart';
import 'package:butlerly/features/foundation/presentation/contextual_pages.dart';
import 'package:butlerly/features/foundation/presentation/legal_licenses_page.dart';
import 'package:butlerly/features/foundation/presentation/receipt_capture_page.dart';
import 'package:butlerly/features/foundation/presentation/review_page.dart';
import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/features/foundation/presentation/settings_page.dart';
import 'package:butlerly/features/insights/presentation/insights_page.dart';
import 'package:butlerly/features/tools/presentation/tools_page.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart'
    as finance_domain;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../features/transactions/transaction_lifecycle_test.dart'
    show
        MemoryCategories,
        MemoryEvidence,
        MemoryMerchants,
        MemoryPaymentSources,
        MemoryTags,
        MemoryTransactionRepository,
        MemoryUserPreferences;

void main() {
  setUp(() {
    appRouter.go('/');
    debugDefaultTargetPlatformOverride = null;
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('classifies presentation from width at the documented breakpoints', () {
    expect(ButlerlyLayout.modeForWidth(800), ButlerlyLayoutMode.compact);
    expect(ButlerlyLayout.modeForWidth(801), ButlerlyLayoutMode.medium);
    expect(ButlerlyLayout.modeForWidth(1023), ButlerlyLayoutMode.medium);
    expect(ButlerlyLayout.modeForWidth(1024), ButlerlyLayoutMode.wide);
    for (final width in [390.0, 500.0, 744.0, 800.0]) {
      expect(ButlerlyLayout.modeForWidth(width), ButlerlyLayoutMode.compact);
    }
    for (final width in [801.0, 900.0, 1023.0]) {
      expect(ButlerlyLayout.modeForWidth(width), ButlerlyLayoutMode.medium);
    }
    for (final width in [1024.0, 1133.0, 1200.0]) {
      expect(ButlerlyLayout.modeForWidth(width), ButlerlyLayoutMode.wide);
    }
  });

  test(
    'width classification is independent of platform and viewport height',
    () {
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          ButlerlyLayout.mode(const Size(390, 1200)),
          ButlerlyLayoutMode.compact,
        );
        expect(
          ButlerlyLayout.mode(const Size(900, 390)),
          ButlerlyLayoutMode.medium,
        );
        expect(
          ButlerlyLayout.mode(const Size(1200, 390)),
          ButlerlyLayoutMode.wide,
        );
      }
    },
  );

  test('content width policy uses compact and readable width tokens', () {
    expect(
      ButlerlyLayout.contentMaxWidth(const Size(390, 844)),
      ButlerlySize.compactContentMaxWidth,
    );
    expect(
      ButlerlyLayout.contentMaxWidth(const Size(900, 1100)),
      ButlerlySize.pageContentMaxWidth,
    );
    expect(
      ButlerlyLayout.contentMaxWidth(const Size(1200, 800)),
      ButlerlySize.pageContentMaxWidth,
    );
  });

  testWidgets('Compact preserves the compact shell and bottom navigation', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(390, 844));

    expect(find.byType(CompactPrimaryShell), findsOneWidget);
    expect(find.byType(MediumPrimaryShell), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('primary-compact-navigation'))),
      const Size(
        390,
        ButlerlySize.navigationBarHeight +
            ButlerlySpacing.compact +
            ButlerlySpacing.primaryNavigationBottomLift,
      ),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,
      390 - ButlerlySize.contentGutter * 2,
    );
  });

  testWidgets(
    'Medium overlays floating switch buttons on full-height content',
    (tester) async {
      const size = Size(900, 1100);
      await _pumpAt(tester, size);

      expect(find.byType(MediumPrimaryShell), findsOneWidget);
      expect(find.byType(CompactPrimaryShell), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      final bodySurface = find.byKey(
        const ValueKey('primary-medium-body-surface'),
      );
      final navigation = find.byKey(
        const ValueKey('primary-medium-navigation'),
      );
      final pill = tester.widget<Container>(
        find.byKey(const ValueKey('primary-navigation-pill')),
      );
      final decoration = pill.decoration! as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;
      expect(gradient.colors, const [Color(0xFFC0974C), Color(0xFFF3C670)]);
      expect(
        pill.padding,
        const EdgeInsets.all(ButlerlySize.primaryNavigationBorderWidth),
      );
      expect(tester.getSize(bodySurface), size);
      expect(
        tester.widget<ColoredBox>(bodySurface).color,
        Theme.of(
          tester.element(bodySurface),
        ).extension<ButlerlySemanticColors>()!.background,
      );
      expect(
        tester.getRect(bodySurface).bottom,
        closeTo(tester.getRect(navigation).bottom, 0.01),
      );
      expect(
        tester.getRect(navigation).top,
        lessThan(tester.getRect(bodySurface).bottom),
      );
      final content = find.byKey(const ValueKey('home-page-content'));
      expect(tester.getSize(content).width, ButlerlySize.pageContentMaxWidth);
      expect(
        tester.getRect(content).left,
        (size.width - ButlerlySize.pageContentMaxWidth) / 2,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('primary-medium-navigation')))
            .width,
        size.width,
      );
      expect(
        find.descendant(of: navigation, matching: find.byType(InkWell)),
        findsNWidgets(5),
      );
      for (final label in const ['Home', 'Txns', 'Tools', 'More']) {
        expect(
          find.descendant(of: navigation, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(
          of: navigation,
          matching: find.bySemanticsLabel('Add transaction'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('Tablet landscape wide uses a compact desktop rail', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(900, 600));

    expect(find.byType(DesktopPrimaryShell), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('primary-wide-navigation')))
          .width,
      ButlerlySize.wideNavigationCollapsedWidth,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('primary-wide-body-surface')))
          .width,
      900 - ButlerlySize.wideNavigationCollapsedWidth,
    );
    expect(find.byKey(const ValueKey('wide-collapsed-home')), findsOneWidget);
    _expectCollapsedBrandCentered(tester);

    tester.view.physicalSize = const Size(1200, 800);
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('primary-wide-navigation')))
          .width,
      ButlerlySize.wideNavigationExpandedWidth,
    );
  });

  testWidgets(
    'Android landscape cutout keeps the compact rail and expand button usable',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await _pumpAt(tester, const Size(600, 900));
      expect(find.byType(CompactPrimaryShell), findsOneWidget);

      // Landscape system UI can reserve space on the left of Android displays.
      // That inset must not consume the rail's fixed 72px touch targets.
      tester.view.padding = const FakeViewPadding(left: 56);
      addTearDown(tester.view.resetPadding);
      tester.view.physicalSize = const Size(900, 600);
      await tester.pumpAndSettle();

      expect(find.byType(DesktopPrimaryShell), findsOneWidget);
      final rail = find.byKey(const ValueKey('primary-wide-navigation'));
      expect(tester.getRect(rail).left, 56);
      expect(
        tester.getSize(rail).width,
        ButlerlySize.wideNavigationCollapsedWidth,
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('wide-collapsed-home'))).left,
        greaterThanOrEqualTo(56),
      );

      await tester.tap(
        find.byKey(const ValueKey('wide-collapsed-transactions')),
      );
      await tester.pumpAndSettle();
      expect(
        appRouter.routeInformationProvider.value.uri.path,
        '/transactions',
      );

      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_right_rounded));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(rail).width,
        ButlerlySize.wideNavigationExpandedWidth,
      );
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Android phone rotation preserves Medium bottom navigation and taps',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await _pumpAt(tester, const Size(390, 900));
      expect(find.byType(CompactPrimaryShell), findsOneWidget);

      tester.view.physicalSize = const Size(900, 390);
      await tester.pumpAndSettle();

      expect(find.byType(MediumPrimaryShell), findsOneWidget);
      expect(find.byType(DesktopPrimaryShell), findsNothing);
      expect(
        find.byKey(const ValueKey('primary-medium-navigation')),
        findsOneWidget,
      );
      await tester.tap(find.bySemanticsLabel('Transactions'));
      await tester.pumpAndSettle();
      expect(
        appRouter.routeInformationProvider.value.uri.path,
        '/transactions',
      );
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Wide uses the left navigation shell', (tester) async {
    const size = Size(1200, 800);
    await _pumpAt(tester, size);

    expect(ButlerlySize.wideNavigationExpandedWidth, 188.0);
    expect(ButlerlySize.wideNavigationCollapsedWidth, 72.0);
    expect(ButlerlyLayout.mode(size), ButlerlyLayoutMode.wide);
    expect(find.byType(DesktopPrimaryShell), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('primary-wide-navigation')),
        matching: find.byType(ButlerlyBrandIcon),
      ),
      findsOneWidget,
    );
    expect(find.byType(MediumPrimaryShell), findsNothing);
    expect(find.byType(CompactPrimaryShell), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('primary-wide-navigation'))),
      const Size(ButlerlySize.wideNavigationExpandedWidth, 800),
    );
    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    final home = find.descendant(of: navigation, matching: find.text('Home'));
    final transactions = find.descendant(
      of: navigation,
      matching: find.text('Transactions'),
    );
    expect(home, findsOneWidget);
    expect(transactions, findsOneWidget);
    expect(
      tester.getRect(home).top,
      lessThan(tester.getRect(transactions).top),
    );
    expect(find.byKey(const ValueKey('wide-add-navigation')), findsOneWidget);
    for (final label in const [
      'Add transaction manually',
      'Scan receipt',
      'Import statement',
      'Import file',
      'Payment sources',
    ]) {
      expect(
        find.descendant(of: navigation, matching: find.text(label)),
        findsNothing,
        reason: 'Add entry points are on the right-side Add page.',
      );
    }
    expect(
      find.descendant(of: navigation, matching: find.text('Tools')),
      findsOneWidget,
    );
    for (final label in const [
      'Review',
      'Analysis',
      'Insights',
      'Payment settlements',
      'Master data',
      'Rules',
    ]) {
      expect(
        find.descendant(of: navigation, matching: find.text(label)),
        findsNothing,
        reason: 'The desktop Tools destinations belong on the Tools page.',
      );
    }
    expect(find.byKey(const ValueKey('desktop-home-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('primary-wide-body-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('primary-wide-home-floating-surface')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('desktop-home-page')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-home-unavailable-card')),
      findsOneWidget,
    );
    for (final key in const [
      'desktop-home-summary-card',
      'desktop-home-trend-card',
      'desktop-home-category-card',
      'desktop-home-budgets-card',
      'desktop-home-action-center-card',
      'desktop-home-recent-card',
      'desktop-home-insights-card',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.text('Data is unavailable for now'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    final unavailableTrendRange = find.descendant(
      of: find.byKey(const ValueKey('desktop-home-trend-card')),
      matching: find.byType(DropdownButton<int>),
    );
    expect(
      tester.widget<DropdownButton<int>>(unavailableTrendRange).onChanged,
      isNull,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('desktop-home-unavailable-content')),
          )
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(find.text('Import statement'), findsOneWidget);
    expect(find.text('Payment settlements'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('primary-wide-body-surface'))),
      const Size(1200 - ButlerlySize.wideNavigationExpandedWidth, 800),
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('wide-home-navigation')))
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('Desktop Home shows greeting before month selector', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    final header = find.byKey(const ValueKey('desktop-home-header'));
    final greeting = find.byKey(const ValueKey('desktop-home-greeting'));
    final month = find.byKey(const ValueKey('desktop-home-month-selector'));
    final previous = find.descendant(
      of: header,
      matching: find.byIcon(Icons.chevron_left),
    );
    final next = find.descendant(
      of: header,
      matching: find.byIcon(Icons.chevron_right),
    );
    final search = find.descendant(
      of: header,
      matching: find.byIcon(Icons.search),
    );

    expect(header, findsOneWidget);
    expect(greeting, findsOneWidget);
    expect(month, findsOneWidget);
    expect(tester.widget<Text>(greeting).textAlign, TextAlign.start);
    final headerWidget = tester.widget<Container>(header);
    expect(tester.getSize(header).height, ButlerlySize.pageToolbarHeight);
    expect(
      headerWidget.padding,
      const EdgeInsets.symmetric(horizontal: ButlerlySize.contentGutter),
    );
    final appBarTitleStyle = Theme.of(
      tester.element(greeting),
    ).appBarTheme.titleTextStyle;
    expect(tester.widget<Text>(greeting).style, appBarTitleStyle);
    expect(
      tester.getRect(greeting).left - tester.getRect(header).left,
      closeTo(ButlerlySize.contentGutter, 0.01),
    );
    expect(
      tester.getRect(greeting).right,
      lessThanOrEqualTo(tester.getRect(previous).left),
    );
    expect(
      tester.getRect(previous).right,
      lessThanOrEqualTo(tester.getRect(month).left),
    );
    expect(
      tester.getRect(month).right,
      lessThanOrEqualTo(tester.getRect(next).left),
    );
    expect(tester.getRect(next).right, lessThan(tester.getRect(search).left));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Desktop Home keeps cards visible when analysis data is unavailable',
    (tester) async {
      final finance = await _desktopHomeFinance();
      services.registerSingleton<FinanceServices>(finance);
      addTearDown(() => services.unregister<FinanceServices>());

      await _pumpAt(tester, const Size(1200, 800));

      final header = find.byKey(const ValueKey('desktop-home-header'));
      final nextMonth = find.ancestor(
        of: find.descendant(
          of: header,
          matching: find.byIcon(Icons.chevron_right),
        ),
        matching: find.byType(IconButton),
      );
      expect(nextMonth, findsOneWidget);
      expect(tester.widget<IconButton>(nextMonth).onPressed, isNull);

      for (final key in const [
        'desktop-home-summary-card',
        'desktop-home-trend-card',
        'desktop-home-category-card',
        'desktop-home-budgets-card',
        'desktop-home-action-center-card',
        'desktop-home-recent-card',
        'desktop-home-insights-card',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(
        find.text(
          'Local calculations could not be completed. No records were changed.',
        ),
        findsNWidgets(3),
      );
      expect(find.text('Local storage is unavailable'), findsOneWidget);
      expect(find.text('Add budget'), findsNothing);
      expect(find.text('Insights are unavailable'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Data is unavailable for now'), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Local calculations could not be completed. No records were changed.',
        ),
        findsNWidgets(3),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop Home keeps explicit loading states until its overview resolves',
    (tester) async {
      final gate = Completer<void>();
      final finance = await _desktopHomeFinance(
        transactions: _GatedTransactionRepository(
          MemoryTransactionRepository(),
          gate.future,
        ),
      );
      services.registerSingleton<FinanceServices>(finance);
      addTearDown(() => services.unregister<FinanceServices>());

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pump();

      for (final key in const [
        'desktop-home-summary-card',
        'desktop-home-trend-card',
        'desktop-home-category-card',
        'desktop-home-budgets-card',
        'desktop-home-action-center-card',
        'desktop-home-recent-card',
        'desktop-home-insights-card',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      for (final key in const [
        'desktop-home-summary-card',
        'desktop-home-trend-card',
        'desktop-home-category-card',
        'desktop-home-budgets-card',
        'desktop-home-action-center-card',
        'desktop-home-recent-card',
        'desktop-home-insights-card',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.text('Loading data…'),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('No category data for this period'), findsNothing);
      expect(find.text('No spending trend data'), findsNothing);
      expect(find.text('No transactions'), findsNothing);
      expect(tester.takeException(), isNull);

      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop Home keeps one retry for an unavailable transaction overview',
    (tester) async {
      final finance = await _desktopHomeFinance(
        transactions: _ThrowingHomeTransactions(),
      );
      services.registerSingleton<FinanceServices>(finance);
      addTearDown(() => services.unregister<FinanceServices>());

      await _pumpAt(tester, const Size(1200, 800));

      expect(
        find.byKey(const ValueKey('desktop-home-unavailable-card')),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('desktop-home-trend-card')),
          matching: find.text('Retry'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop Home disables period controls when its timezone is invalid',
    (tester) async {
      final finance = await _desktopHomeFinance();
      await finance.saveUserPreference(
        UserPreference(
          locale: 'en',
          formattingLocale: 'en-US',
          regionCode: 'US',
          baseCurrency: CurrencyCode('USD'),
          timeZoneId: 'Invalid/Timezone',
          firstUseCompleted: true,
        ),
      );
      services.registerSingleton<FinanceServices>(finance);
      addTearDown(() => services.unregister<FinanceServices>());

      await _pumpAt(tester, const Size(1200, 800));

      final header = find.byKey(const ValueKey('desktop-home-header'));
      final previous = find.ancestor(
        of: find.descendant(
          of: header,
          matching: find.byIcon(Icons.chevron_left),
        ),
        matching: find.byType(IconButton),
      );
      final next = find.ancestor(
        of: find.descendant(
          of: header,
          matching: find.byIcon(Icons.chevron_right),
        ),
        matching: find.byType(IconButton),
      );
      final month = find.byKey(const ValueKey('desktop-home-month-selector'));

      expect(tester.widget<IconButton>(previous).onPressed, isNull);
      expect(tester.widget<IconButton>(next).onPressed, isNull);
      expect(tester.widget<TextButton>(month).onPressed, isNull);
      final unavailableTrendRange = find.descendant(
        of: find.byKey(const ValueKey('desktop-home-trend-card')),
        matching: find.byType(DropdownButton<int>),
      );
      expect(
        tester.widget<DropdownButton<int>>(unavailableTrendRange).onChanged,
        isNull,
      );
      expect(find.text('Data is unavailable for now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop Home routes use the authoritative Home period and timezone',
    (tester) async {
      final now = DateTime.now().toUtc();
      final transactions = MemoryTransactionRepository();
      final categories = MemoryCategories();
      await categories.save(
        finance_domain.Category(
          id: finance_domain.CategoryId('route-category'),
          name: 'Route category',
          origin: finance_domain.CategoryOrigin.user,
        ),
      );
      final finance = await _desktopHomeFinance(
        transactions: transactions,
        categories: categories,
        analysisRules: _DesktopAnalysisRules([
          _desktopExpenseRule(),
          _desktopCategoryRule(),
        ]),
      );
      final created = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'desktop-home-route-transaction',
          provenanceId: 'desktop-home-route-transaction-provenance',
          timing: KnownTransactionTime(
            DateTime.utc(now.year, now.month, now.day, 12),
          ),
          transactionDate: _dateOnly(now),
          money: Money(
            amount: DecimalValue.parse('10.00'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          categoryId: 'route-category',
          description: 'Route test spending',
        ),
      );
      expect(created, isA<ApplicationSuccess<TransactionDto>>());
      services.registerSingleton<FinanceServices>(finance);
      addTearDown(() => services.unregister<FinanceServices>());

      await _pumpAt(tester, const Size(1200, 800));
      final currentFrom = _dateOnly(DateTime(now.year, now.month, 1));
      final currentTo = _dateOnly(DateTime(now.year, now.month, now.day));

      final categoryCard = find.byKey(
        const ValueKey('desktop-home-category-card'),
      );
      final categoryViewAll = find.descendant(
        of: categoryCard,
        matching: find.text('View all'),
      );
      final categoryButton = find.ancestor(
        of: categoryViewAll,
        matching: find.byType(TextButton),
      );
      await tester.tap(categoryButton);
      await tester.pumpAndSettle();
      final currentAnalysis = tester.widget<AnalysisPage>(
        find.byType(AnalysisPage),
      );
      expect(currentAnalysis.initialMonth, isNull);
      expect(currentAnalysis.initialRange, isNull);

      appRouter.go('/');
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('desktop-home-page')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      final insightsCard = find.byKey(
        const ValueKey('desktop-home-insights-card'),
      );
      final needsAttention = find.descendant(
        of: insightsCard,
        matching: find.text('Needs attention'),
      );
      await tester.ensureVisible(needsAttention);
      await tester.tap(needsAttention);
      await tester.pumpAndSettle();
      final currentInsights = tester.widget<InsightsPage>(
        find.byType(InsightsPage),
      );
      expect(currentInsights.initialMonth, isNull);
      expect(currentInsights.initialRange, isNull);

      appRouter.go('/');
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('desktop-home-page')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      final actionCenter = find.byKey(
        const ValueKey('desktop-home-action-center-card'),
      );
      final needsReview = find.descendant(
        of: actionCenter,
        matching: find.text('Needs review'),
      );
      await tester.ensureVisible(needsReview);
      await tester.tap(needsReview);
      await tester.pumpAndSettle();
      final review = tester.widget<ReviewPage>(find.byType(ReviewPage));
      expect(review.reviewScope.isScoped, isTrue);
      expect(review.reviewScope.period?.startDate, currentFrom);
      expect(review.reviewScope.period?.endDate, currentTo);
      expect(review.reviewScope.period?.timeZoneId, 'UTC');

      appRouter.go('/');
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('desktop-home-page')),
        const Offset(0, -700),
      );
      await tester.pumpAndSettle();
      final recentCard = find.byKey(const ValueKey('desktop-home-recent-card'));
      final recentViewAll = find.descendant(
        of: recentCard,
        matching: find.text('View all'),
      );
      await tester.ensureVisible(recentViewAll);
      await tester.tap(recentViewAll);
      await tester.pumpAndSettle();
      final search = tester.widget<SearchPage>(find.byType(SearchPage));
      expect(search.initialQuery?.from, DateTime.parse(currentFrom));
      expect(search.initialQuery?.to, DateTime.parse(currentTo));
      expect(search.initialQuery?.timeZoneId, 'UTC');

      appRouter.go('/');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('desktop-home-header')),
          matching: find.byIcon(Icons.chevron_left),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('desktop-home-page')),
        const Offset(0, 180),
      );
      await tester.pumpAndSettle();
      final historicalViewAll = find.descendant(
        of: categoryCard,
        matching: find.text('View all'),
      );
      await tester.ensureVisible(historicalViewAll);
      await tester.tap(
        find.ancestor(of: historicalViewAll, matching: find.byType(TextButton)),
      );
      await tester.pumpAndSettle();
      final previous = DateTime(now.year, now.month - 1);
      final historicalAnalysis = tester.widget<AnalysisPage>(
        find.byType(AnalysisPage),
      );
      expect(
        historicalAnalysis.initialMonth,
        DateTime(previous.year, previous.month),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop Home keeps narrow expanded chrome usable at large text scale',
    (tester) async {
      await _pumpAt(tester, const Size(1024, 800));
      final rail = find.byKey(const ValueKey('primary-wide-navigation'));
      if (tester.getSize(rail).width ==
          ButlerlySize.wideNavigationCollapsedWidth) {
        await tester.tap(
          find.byIcon(Icons.keyboard_double_arrow_right_rounded),
        );
        await tester.pumpAndSettle();
      }
      tester.view.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(
        tester.getSize(rail).width,
        ButlerlySize.wideNavigationExpandedWidth,
      );
      final railRect = tester.getRect(rail);
      for (final label in const [
        'Home',
        'Transactions',
        'Add',
        'Tools',
        'More',
      ]) {
        final labelFinder = find.descendant(
          of: rail,
          matching: find.text(label),
        );
        expect(labelFinder, findsOneWidget);
        final labelRect = tester.getRect(labelFinder);
        expect(labelRect.left, greaterThanOrEqualTo(railRect.left));
        expect(labelRect.right, lessThanOrEqualTo(railRect.right));
        expect(labelRect.top, greaterThanOrEqualTo(railRect.top));
        expect(labelRect.bottom, lessThanOrEqualTo(railRect.bottom));
      }
      final collapse = find.ancestor(
        of: find.byIcon(Icons.keyboard_double_arrow_left_rounded),
        matching: find.byType(OutlinedButton),
      );
      expect(collapse, findsOneWidget);
      expect(
        tester.getSize(collapse).height,
        greaterThanOrEqualTo(ButlerlySize.minimumTarget),
      );
      final collapseLabel = find.descendant(
        of: collapse,
        matching: find.text('Collapse'),
      );
      expect(collapseLabel, findsOneWidget);
      final collapseLabelRect = tester.getRect(collapseLabel);
      expect(collapseLabelRect.left, greaterThanOrEqualTo(railRect.left));
      expect(collapseLabelRect.right, lessThanOrEqualTo(railRect.right));
      expect(find.byKey(const ValueKey('desktop-home-header')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop Home trend remains readable with valid data at large text scale',
    (tester) async {
      final transactions = MemoryTransactionRepository();
      final finance = await _desktopHomeFinance(
        transactions: transactions,
        analysisRules: _DesktopAnalysisRules([_desktopExpenseRule()]),
      );
      final now = DateTime.now().toUtc();
      final created = await finance.createTransaction(
        CreateTransactionCommand(
          id: 'desktop-home-large-text-trend',
          provenanceId: 'desktop-home-large-text-trend-provenance',
          timing: KnownTransactionTime(now),
          transactionDate: _dateOnly(now),
          money: Money(
            amount: DecimalValue.parse('1234.56'),
            currency: CurrencyCode('USD'),
          ),
          direction: TransactionDirection.expense,
          description: 'Large text trend transaction',
        ),
      );
      expect(created, isA<ApplicationSuccess<TransactionDto>>());
      services.registerSingleton<FinanceServices>(finance);
      addTearDown(() => services.unregister<FinanceServices>());

      await _pumpAt(tester, const Size(1200, 800));
      tester.view.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      final chart = find.byKey(const ValueKey('desktop-home-trend-chart'));
      expect(chart, findsOneWidget);
      expect(tester.getSize(chart).height, greaterThan(220));
      expect(find.text('No spending trend data'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Desktop Home annotates categories with unavailable currency data', (
    tester,
  ) async {
    final transactions = MemoryTransactionRepository();
    final categories = MemoryCategories();
    await categories.save(
      finance_domain.Category(
        id: finance_domain.CategoryId('category-id'),
        name: 'Foreign category',
        origin: finance_domain.CategoryOrigin.user,
      ),
    );
    final finance = await _desktopHomeFinance(
      transactions: transactions,
      categories: categories,
      analysisRules: _DesktopAnalysisRules([
        _desktopExpenseRule(),
        _desktopCategoryRule(),
      ]),
    );
    services.registerSingleton<FinanceServices>(finance);
    addTearDown(() => services.unregister<FinanceServices>());

    final transactionDate = DateTime.utc(
      DateTime.now().toUtc().year,
      DateTime.now().toUtc().month - 1,
      15,
    );
    final created = await finance.createTransaction(
      CreateTransactionCommand(
        id: 'desktop-home-missing-fx',
        provenanceId: 'desktop-home-missing-fx-provenance',
        timing: KnownTransactionTime(transactionDate),
        transactionDate: transactionDate.toIso8601String().substring(0, 10),
        money: Money(
          amount: DecimalValue.parse('25.00'),
          currency: CurrencyCode('EUR'),
        ),
        direction: TransactionDirection.expense,
        categoryId: 'category-id',
        description: 'Unconverted category expense',
      ),
    );
    expect(created, isA<ApplicationSuccess<TransactionDto>>());

    await _pumpAt(tester, const Size(1200, 800));
    // The test clock is the first day of the month. Selecting the prior
    // month exercises the same persisted analysis path without relying on
    // a current-month partial-window boundary.
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('desktop-home-category-card')),
        matching: find.text(
          'Some categories are unavailable because currency normalization is missing.',
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('desktop-home-trend-card')),
        matching: find.text(
          'Some spending trend values are unavailable because currency normalization is missing.',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Not available'), findsOneWidget);
    expect(find.text('No category data for this period'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Desktop Home does not present zero duplicates when detection is unavailable',
    (tester) async {
      final finance = await _desktopHomeFinance(
        duplicateGroups: _ThrowingDuplicateGroups(),
      );
      services.registerSingleton<FinanceServices>(finance);
      addTearDown(() => services.unregister<FinanceServices>());

      await _pumpAt(tester, const Size(1200, 800));

      expect(
        find.text('Possible duplicate detection unavailable'),
        findsOneWidget,
      );
      expect(find.text('Possible duplicates'), findsNothing);
      final retry = find.descendant(
        of: find.byKey(const ValueKey('desktop-home-action-center-card')),
        matching: find.text('Retry'),
      );
      expect(retry, findsOneWidget);
      await tester.ensureVisible(retry);
      await tester.pumpAndSettle();
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(
        find.text('Possible duplicate detection unavailable'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Desktop Home keeps independent actions visible when review and duplicate data are unavailable',
    (tester) async {
      final finance = await _desktopHomeFinance(
        transactions: _ThrowingReviewTransactions(),
        duplicateGroups: _ThrowingDuplicateGroups(),
      );
      services.registerSingleton<FinanceServices>(finance);
      addTearDown(() => services.unregister<FinanceServices>());

      await _pumpAt(tester, const Size(1200, 800));

      expect(
        find.text('Data quality review is temporarily unavailable'),
        findsOneWidget,
      );
      expect(
        find.text('Possible duplicate detection unavailable'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('desktop-home-action-center-card')),
          matching: find.text('Retry'),
        ),
        findsOneWidget,
      );
      expect(find.text('Import statement'), findsOneWidget);
      expect(find.text('Payment settlements'), findsOneWidget);
      expect(find.text('Needs review'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Wide primary destinations share the same body surface', (
    tester,
  ) async {
    const size = Size(1200, 800);
    await _pumpAt(tester, size);

    for (final route in ['/', '/transactions', '/add', '/tools', '/settings']) {
      appRouter.go(route);
      await tester.pumpAndSettle();

      expect(find.byType(DesktopPrimaryShell), findsOneWidget);
      expect(
        find.byKey(const ValueKey('primary-wide-body-surface')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('primary-wide-home-floating-surface')),
        findsNothing,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('primary-wide-body-surface'))),
        const Size(1200 - ButlerlySize.wideNavigationExpandedWidth, 800),
      );
    }
  });

  testWidgets('Wide More shows the dashboard cards and preferences', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));
    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('More')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-more-protection')),
      findsOneWidget,
    );
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Privacy & data'), findsOneWidget);
    expect(find.text('Optional features'), findsOneWidget);
    expect(find.text('About Butlerly'), findsOneWidget);
    expect(find.text('Manage privacy & data'), findsOneWidget);
    expect(
      find.descendant(of: navigation, matching: find.text('About Butlerly')),
      findsNothing,
    );
  });

  testWidgets('Wide manual Add fills the right pane and groups form cards', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        MemoryTransactionRepository(),
        MemoryPaymentSources(),
        MemoryMerchants(),
        MemoryCategories(),
        MemoryTags(),
        MemoryEvidence(),
        MemoryUserPreferences(),
      ),
    );
    addTearDown(() => services.unregister<FinanceServices>());

    appRouter.go('/transactions/add');
    await tester.pumpAndSettle();

    final rightSide = tester.getRect(
      find.byKey(const ValueKey('primary-wide-body-surface')),
    );
    final editor = tester.getRect(
      find.byKey(const ValueKey('transaction-editor-content')),
    );
    expect(editor.width, closeTo(rightSide.width, 0.1));
    expect(editor.left, closeTo(rightSide.left, 0.1));

    final amount = tester.getRect(
      find.byKey(const ValueKey('transaction-editor-financial-card')),
    );
    final details = tester.getRect(
      find.byKey(const ValueKey('transaction-editor-organization-card')),
    );
    final date = tester.getRect(
      find.byKey(const ValueKey('transaction-editor-date-card')),
    );
    final notes = tester.getRect(
      find.byKey(const ValueKey('transaction-editor-description-card')),
    );
    expect(date.left, greaterThan(amount.right));
    expect(details.left, closeTo(amount.left, 0.1));
    expect(details.top, greaterThan(amount.bottom));
    final merchantField = tester.getRect(
      find.byKey(const ValueKey('transaction-merchant-selector')),
    );
    final categoryField = tester.getRect(
      find.byKey(const ValueKey('transaction-category-selector')),
    );
    expect(
      categoryField.top - merchantField.bottom,
      closeTo(ButlerlySpacing.small, 1),
    );
    final descriptionField = tester.getRect(
      find.byKey(const ValueKey('transaction-description-field')),
    );
    final notesField = tester.getRect(
      find.byKey(const ValueKey('transaction-notes-field')),
    );
    expect(
      notesField.top - descriptionField.bottom,
      closeTo(ButlerlySpacing.small, 1),
    );
    expect(notes.left, closeTo(date.left, 0.1));
    expect(notes.top, greaterThan(date.bottom));

    final save = tester.getRect(
      find.byKey(const ValueKey('transaction-save-locally')),
    );
    expect(save.width, 240);
    expect(
      save.right,
      closeTo(rightSide.right - ButlerlySpacing.pagePadding, 1),
    );
  });

  testWidgets('Compact manual Add preserves the single-column form', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(390, 844));
    services.registerSingleton<FinanceServices>(
      FinanceServices(
        MemoryTransactionRepository(),
        MemoryPaymentSources(),
        MemoryMerchants(),
        MemoryCategories(),
        MemoryTags(),
        MemoryEvidence(),
        MemoryUserPreferences(),
      ),
    );
    addTearDown(() => services.unregister<FinanceServices>());

    appRouter.go('/transactions/add');
    await tester.pumpAndSettle();

    final amount = tester.getRect(
      find.byKey(const ValueKey('transaction-editor-financial-card')),
    );
    final details = tester.getRect(
      find.byKey(const ValueKey('transaction-editor-organization-card')),
    );
    final date = tester.getRect(
      find.byKey(const ValueKey('transaction-editor-date-card')),
    );
    expect(details.top, greaterThan(amount.bottom));
    expect(date.top, greaterThan(details.bottom));
    expect(details.left, closeTo(amount.left, 0.1));

    final save = tester.getRect(
      find.byKey(const ValueKey('transaction-save-locally')),
    );
    expect(save.width, greaterThan(300));
  });

  testWidgets('Wide Add keeps the shell for manual and receipt workflows', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Add')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: navigation,
        matching: find.text('Add transaction manually'),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('desktop-add-actions')), findsOneWidget);
    await tester.tap(find.text('Add transaction manually'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('transaction-storage-unavailable-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('primary-wide-navigation')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('wide-add-navigation')))
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('Wide Add keeps the shell for capture receipt workflow', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    final finance = FinanceServices(
      MemoryTransactionRepository(),
      MemoryPaymentSources(),
      MemoryMerchants(),
      MemoryCategories(),
      MemoryTags(),
      MemoryEvidence(),
      MemoryUserPreferences(),
    );
    services.registerSingleton<FinanceServices>(finance);
    services.registerSingleton<LocalEvidenceStore>(
      LocalEvidenceStore(
        LocalDataManager(
          LocalDatabase(logger: AppLogger()),
          localEvidenceDirectory: Directory.systemTemp,
        ),
        finance,
      ),
    );
    addTearDown(() {
      services.unregister<LocalEvidenceStore>();
      services.unregister<FinanceServices>();
    });

    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Add')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add transaction from receipts'));
    await tester.pumpAndSettle();

    expect(find.byType(ReceiptCapturePage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('primary-wide-navigation')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('wide-add-navigation')))
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('desktop More Legal & licenses opens the existing page', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));
    await tester.tap(find.byKey(const ValueKey('wide-more-navigation')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Legal & licenses'));
    await tester.tap(find.text('Legal & licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LegalLicensesPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('Wide More remains a single selected navigation item', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));
    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    await tester.tap(find.byKey(const ValueKey('wide-more-navigation')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(
      find.descendant(of: navigation, matching: find.text('More')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: navigation, matching: find.text('Assistant')),
      findsNothing,
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('wide-more-navigation')))
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('desktop More Assistant preserves focused route stack', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));
    await tester.tap(find.byKey(const ValueKey('wide-more-navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assistant'));
    await tester.pumpAndSettle();

    expect(find.byType(AssistantUnavailablePage), findsOneWidget);
    await tester.tap(find.text('Search records'));
    await tester.pumpAndSettle();

    expect(find.byType(SearchPage), findsOneWidget);
    expect(appRouter.canPop(), isTrue);
    expect(
      find.byKey(const ValueKey('primary-wide-navigation')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('wide-more-navigation')))
          .properties
          .selected,
      isTrue,
    );

    appRouter.pop();
    await tester.pumpAndSettle();
    expect(find.byType(AssistantUnavailablePage), findsOneWidget);

    appRouter.pop();
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/settings');
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('collapsed Wide navigation exposes grouped actions in a popup', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left_rounded));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('primary-wide-navigation'))),
      const Size(ButlerlySize.wideNavigationCollapsedWidth, 800),
    );
    _expectCollapsedBrandCentered(tester);
    expect(
      tester.getRect(find.byKey(const ValueKey('wide-collapsed-home'))).top,
      lessThan(
        tester
            .getRect(find.byKey(const ValueKey('wide-collapsed-transactions')))
            .top,
      ),
    );
    expect(find.text('Analysis'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('wide-collapsed-tools')));
    await tester.pumpAndSettle();
    expect(find.text('Analysis'), findsOneWidget);

    await tester.tap(find.text('Analysis'));
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisPage), findsOneWidget);
    expect(find.byType(DesktopPrimaryShell), findsOneWidget);
  });

  testWidgets('Wide child navigation pushes and restores the previous shell', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Tools')),
    );
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/tools');

    expect(find.byKey(const ValueKey('desktop-tools-actions')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('desktop-tools-actions')),
        matching: find.text('Analysis'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AnalysisPage), findsOneWidget);
    expect(find.byType(DesktopPrimaryShell), findsOneWidget);
    expect(
      find.byKey(const ValueKey('primary-wide-navigation')),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(appRouter.routeInformationProvider.value.uri.path, '/tools');
    expect(find.byType(DesktopPrimaryShell), findsOneWidget);
    expect(find.byType(ToolsPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('primary-wide-navigation')),
      findsOneWidget,
    );
  });

  testWidgets('Wide menu remains interactive while a secondary page is open', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Tools')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('desktop-tools-actions')),
        matching: find.text('Analysis'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisPage), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('primary-wide-navigation')),
        matching: find.text('Home'),
      ),
    );
    await tester.pumpAndSettle();

    expect(appRouter.routeInformationProvider.value.uri.path, '/');
    expect(find.byKey(const ValueKey('desktop-home-page')), findsOneWidget);
    expect(find.byType(DesktopPrimaryShell), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('wide-home-navigation')))
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('collapsed Wide state survives secondary navigation', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wide-collapsed-tools')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analysis'));
    await tester.pumpAndSettle();

    expect(find.byType(AnalysisPage), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('primary-wide-navigation'))),
      const Size(ButlerlySize.wideNavigationCollapsedWidth, 800),
    );

    await tester.tap(find.byKey(const ValueKey('wide-collapsed-home')));
    await tester.pumpAndSettle();

    expect(appRouter.routeInformationProvider.value.uri.path, '/');
    expect(find.byKey(const ValueKey('desktop-home-page')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('primary-wide-navigation'))),
      const Size(ButlerlySize.wideNavigationCollapsedWidth, 800),
    );
  });

  testWidgets('Compact and Medium keep focused secondary behavior', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(390, 844));
    await tester.tap(find.bySemanticsLabel('Add transaction'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add transaction manually'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transaction-storage-unavailable-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('primary-compact-navigation')),
      findsNothing,
    );

    appRouter.go('/');
    await _pumpAt(tester, const Size(900, 1100));
    await tester.tap(find.bySemanticsLabel('Tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analysis'));
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisPage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('primary-medium-navigation')),
      findsNothing,
    );
  });

  testWidgets('Compact and Medium Review pages provide an escape path', (
    tester,
  ) async {
    final finance = FinanceServices(
      MemoryTransactionRepository(),
      MemoryPaymentSources(),
      MemoryMerchants(),
      MemoryCategories(),
      MemoryTags(),
      MemoryEvidence(),
      MemoryUserPreferences(),
    );
    services.registerSingleton<FinanceServices>(finance);
    addTearDown(() => services.unregister<FinanceServices>());
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await finance.saveUserPreference(
      UserPreference(
        locale: 'en',
        formattingLocale: 'en-US',
        regionCode: 'US',
        baseCurrency: CurrencyCode('USD'),
        timeZoneId: 'UTC',
        firstUseCompleted: true,
      ),
    );

    for (final size in [const Size(390, 844), const Size(900, 1100)]) {
      appRouter.go('/review?view=overview');
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ReviewPage), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(appRouter.routeInformationProvider.value.uri.path, '/');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('Review unavailable state still provides an escape path', (
    tester,
  ) async {
    if (services.isRegistered<FinanceServices>()) {
      await services.unregister<FinanceServices>();
    }
    appRouter.go('/review?view=overview');
    await _pumpAt(tester, const Size(390, 844));

    expect(find.byType(ReviewPage), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(appRouter.routeInformationProvider.value.uri.path, '/');
  });

  testWidgets('direct Wide secondary routes use their documented parent', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));
    appRouter.go('/analysis');
    await tester.pumpAndSettle();

    expect(find.byType(AnalysisPage), findsOneWidget);
    expect(find.byType(DesktopPrimaryShell), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('wide-tools-navigation')),
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('direct Wide Notifications route selects the Home parent', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));
    appRouter.go('/notifications');
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsPage), findsOneWidget);
    expect(find.byType(DesktopPrimaryShell), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('wide-home-navigation')))
          .properties
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<Semantics>(find.byKey(const ValueKey('wide-more-navigation')))
          .properties
          .selected,
      isFalse,
    );
  });

  testWidgets('collapsed Wide More opens its dashboard directly', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wide-collapsed-more')));
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/settings');
    expect(
      find.byKey(const ValueKey('desktop-more-protection')),
      findsOneWidget,
    );
  });

  testWidgets(
    'resizing across modes preserves the active primary destination',
    (tester) async {
      await _pumpAt(tester, const Size(390, 844));
      await tester.tap(find.bySemanticsLabel('Tools'));
      await tester.pumpAndSettle();

      for (final size in const [
        Size(700, 800),
        Size(1200, 800),
        Size(390, 844),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        final tools = ButlerlyLayout.mode(size) == ButlerlyLayoutMode.wide
            ? find.byKey(const ValueKey('wide-tools-navigation'))
            : find.bySemanticsLabel('Tools').last;
        if (ButlerlyLayout.mode(size) == ButlerlyLayoutMode.wide) {
          expect(tester.widget<Semantics>(tools).properties.selected, isTrue);
        } else {
          expect(
            tester.getSemantics(tools).flagsCollection.isSelected,
            Tristate.isTrue,
          );
        }
      }
      expect(find.byType(CompactPrimaryShell), findsOneWidget);
    },
  );

  testWidgets('secondary routes apply the same width-driven body policy', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(900, 1100));
    appRouter.go('/search');
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
    expect(tester.getSize(find.byType(AppBar)).width, 900);
    final content = tester.renderObject<RenderSliver>(
      find.byKey(const ValueKey('butlerly-page-content-sliver')),
    );
    expect(
      content.constraints.crossAxisExtent,
      ButlerlySize.pageContentMaxWidth,
    );
  });

  testWidgets(
    'responsive body keeps full canvas and centered readable content',
    (tester) async {
      const size = Size(900, 1100);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ButlerlyResponsiveBody(
              contentKey: ValueKey('focused-page-content'),
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('butlerly-responsive-body-canvas')),
            )
            .width,
        size.width,
      );
      final content = find.byKey(const ValueKey('focused-page-content'));
      expect(tester.getSize(content).width, ButlerlySize.pageContentMaxWidth);
      expect(
        tester.getRect(content).left,
        closeTo((size.width - ButlerlySize.pageContentMaxWidth) / 2, 0.01),
      );
    },
  );

  testWidgets('legal detail pages keep full-width chrome and capped content', (
    tester,
  ) async {
    const size = Size(900, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: LegalDocumentPage(
          document: LegalDocument(
            'termsOfUse',
            'assets/legal/terms_of_use.txt',
          ),
        ),
      ),
    );
    // This test only verifies geometry. Do not wait for a bundled document
    // loading animation to settle in the widget-test asset environment.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.getSize(find.byType(AppBar)).width, size.width);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('legal-document-content')))
          .width,
      ButlerlySize.pageContentMaxWidth,
    );
  });
}

void _expectCollapsedBrandCentered(WidgetTester tester) {
  final rail = find.byKey(const ValueKey('primary-wide-navigation'));
  final brand = find.descendant(
    of: rail,
    matching: find.byType(ButlerlyBrandIcon),
  );
  expect(brand, findsOneWidget);
  // The 1px right divider is outside the rail's content box. Center
  // the brand in the same content box as the collapsed navigation icons.
  final railContainer = find
      .descendant(of: rail, matching: find.byType(Container))
      .first;
  final railDecoration =
      tester.widget<Container>(railContainer).decoration! as BoxDecoration;
  final dividerWidth = (railDecoration.border! as Border).right.width;
  final contentCenterX = tester.getCenter(rail).dx - dividerWidth / 2;
  expect(tester.getCenter(brand).dx, closeTo(contentCenterX, 0.01));
  for (final (key, icon) in [
    ('wide-collapsed-home', Icons.home_rounded),
    ('wide-collapsed-transactions', Icons.format_list_bulleted_rounded),
    ('wide-collapsed-add', Icons.add_rounded),
    ('wide-collapsed-tools', Icons.bar_chart_rounded),
    ('wide-collapsed-more', Icons.settings_outlined),
  ]) {
    final navIcon = find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byIcon(icon),
    );
    expect(navIcon, findsOneWidget);
    expect(
      tester.getCenter(brand).dx,
      closeTo(tester.getCenter(navIcon).dx, 0.01),
      reason: 'Collapsed brand must line up with $key.',
    );
  }
}

String _dateOnly(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

Future<FinanceServices> _desktopHomeFinance({
  TransactionRepository? transactions,
  CategoryRepository? categories,
  DuplicateCandidateGroupRepository? duplicateGroups,
  AnalysisRuleRepository? analysisRules,
}) async {
  final finance = FinanceServices(
    transactions ?? MemoryTransactionRepository(),
    MemoryPaymentSources(),
    MemoryMerchants(),
    categories ?? MemoryCategories(),
    MemoryTags(),
    MemoryEvidence(),
    MemoryUserPreferences(),
    duplicateGroups: duplicateGroups,
    analysisRules: analysisRules,
  );
  await finance.saveUserPreference(
    UserPreference(
      locale: 'en',
      formattingLocale: 'en-US',
      regionCode: 'US',
      baseCurrency: CurrencyCode('USD'),
      timeZoneId: 'UTC',
      firstUseCompleted: true,
    ),
  );
  return finance;
}

final class _GatedTransactionRepository implements TransactionRepository {
  _GatedTransactionRepository(this.delegate, this.gate);

  final MemoryTransactionRepository delegate;
  final Future<void> gate;
  bool _gateUsed = false;

  @override
  Future<Transaction?> findById(TransactionId id) => delegate.findById(id);

  @override
  Future<List<Transaction>> listAll() => delegate.listAll();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async {
    if (!_gateUsed) {
      _gateUsed = true;
      await gate;
    }
    return delegate.query(query);
  }

  @override
  Future<void> removePermanently(TransactionId id) =>
      delegate.removePermanently(id);

  @override
  Future<void> save(Transaction transaction) => delegate.save(transaction);
}

final class _DesktopAnalysisRules implements AnalysisRuleRepository {
  _DesktopAnalysisRules(this.values);

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

AnalysisRuleDefinition _desktopExpenseRule() => AnalysisRuleDefinition(
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
  definitionHash: RuleDefinitionHash('e' * 64),
);

AnalysisRuleDefinition _desktopCategoryRule() => AnalysisRuleDefinition(
  identity: RuleIdentity('ANL-R002'),
  version: RuleVersion('1.0.0'),
  schemaVersion: '1.0.0',
  type: AnalysisRuleType.metric,
  nameKey: 'ANL-R002',
  descriptionKey: 'ANL-R002',
  enabled: true,
  status: AnalysisRuleStatus.active,
  period: 'selected_period',
  measure: const RuleMeasure(
    operation: RuleOperation.sum,
    field: 'amount',
    currencyBasis: CurrencyBasis.baseCurrency,
  ),
  grouping: RuleGrouping.category,
  baseline: RuleBaseline.none,
  condition: const RuleCondition(operator: 'none'),
  severity: RuleSeverity.info,
  surface: AnalysisSurface.spending,
  role: 'categorySpending',
  filters: const [
    AnalysisFilter(kind: AnalysisFilterKind.direction, values: ['expense']),
  ],
  definitionHash: RuleDefinitionHash('f' * 64),
);

final class _ThrowingReviewTransactions implements TransactionRepository {
  final _delegate = MemoryTransactionRepository();

  @override
  Future<Transaction?> findById(TransactionId id) => _delegate.findById(id);

  @override
  Future<List<Transaction>> listAll() => _delegate.listAll();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) {
    if (query.needsReview == true) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'review data unavailable',
      );
    }
    return _delegate.query(query);
  }

  @override
  Future<void> removePermanently(TransactionId id) =>
      _delegate.removePermanently(id);

  @override
  Future<void> save(Transaction transaction) => _delegate.save(transaction);
}

final class _ThrowingHomeTransactions implements TransactionRepository {
  final _delegate = MemoryTransactionRepository();

  @override
  Future<Transaction?> findById(TransactionId id) => _delegate.findById(id);

  @override
  Future<List<Transaction>> listAll() => _delegate.listAll();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) {
    if (query.needsReview != true) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'home transaction data unavailable',
      );
    }
    return _delegate.query(query);
  }

  @override
  Future<void> removePermanently(TransactionId id) =>
      _delegate.removePermanently(id);

  @override
  Future<void> save(Transaction transaction) => _delegate.save(transaction);
}

final class _ThrowingDuplicateGroups
    implements DuplicateCandidateGroupRepository {
  @override
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  }) async => throw const RepositoryException(
    RepositoryFailureCode.unavailable,
    'duplicate detection unavailable',
  );

  @override
  Future<List<DuplicateTransactionGroupMatch>>
  findActiveDuplicateGroups() async => const [];

  @override
  Future<List<TransactionId>> findActiveTransactionIdsForKey(
    DuplicateTransactionKey key,
  ) async => const [];

  @override
  Future<void> save(DuplicateCandidateGroup group) async {}

  @override
  Future<void> remove(String id) async {}
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
  await tester.pumpAndSettle();
}
