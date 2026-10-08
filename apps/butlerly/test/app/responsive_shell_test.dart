import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/shell/compact/compact_primary_shell.dart';
import 'package:butlerly/app/shell/medium/medium_primary_shell.dart';
import 'package:butlerly/app/shell/wide/wide_primary_shell.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_page.dart';
import 'package:butlerly/features/foundation/presentation/contextual_pages.dart';
import 'package:butlerly/features/foundation/presentation/legal_licenses_page.dart';
import 'package:butlerly/features/foundation/presentation/receipt_capture_page.dart';
import 'package:butlerly/features/foundation/presentation/search_page.dart';
import 'package:butlerly/features/foundation/presentation/settings_page.dart';
import 'package:butlerly/features/tools/presentation/tools_page.dart';
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
    expect(ButlerlyLayout.modeForWidth(599), ButlerlyLayoutMode.compact);
    expect(ButlerlyLayout.modeForWidth(600), ButlerlyLayoutMode.medium);
    expect(ButlerlyLayout.modeForWidth(1023), ButlerlyLayoutMode.medium);
    expect(ButlerlyLayout.modeForWidth(1024), ButlerlyLayoutMode.wide);

    for (final width in [390.0, 500.0]) {
      expect(ButlerlyLayout.modeForWidth(width), ButlerlyLayoutMode.compact);
    }
    for (final width in [744.0, 800.0, 900.0]) {
      expect(ButlerlyLayout.modeForWidth(width), ButlerlyLayoutMode.medium);
    }
    for (final width in [1133.0, 1200.0]) {
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
          ButlerlyLayout.mode(const Size(800, 390)),
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
      ButlerlyLayout.contentMaxWidth(const Size(800, 800)),
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
      const Size(390, 80),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,
      390 - ButlerlySize.contentGutter * 2,
    );
  });

  testWidgets('Medium keeps bottom navigation and centers readable content', (
    tester,
  ) async {
    const size = Size(800, 800);
    await _pumpAt(tester, size);

    expect(find.byType(MediumPrimaryShell), findsOneWidget);
    expect(find.byType(CompactPrimaryShell), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('primary-medium-body-surface'))),
      const Size(800, 720),
    );
    final content = find.byKey(const ValueKey('home-page-content'));
    expect(tester.getSize(content).width, ButlerlySize.pageContentMaxWidth);
    expect(
      tester.getRect(content).left,
      closeTo((size.width - ButlerlySize.pageContentMaxWidth) / 2, 0.01),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('primary-medium-navigation')))
          .width,
      size.width,
    );
    final navigation = find.byKey(const ValueKey('primary-medium-navigation'));
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
  });

  testWidgets('Wide uses the left navigation shell', (tester) async {
    const size = Size(1200, 800);
    await _pumpAt(tester, size);

    expect(ButlerlyLayout.mode(size), ButlerlyLayoutMode.wide);
    expect(find.byType(WidePrimaryShell), findsOneWidget);
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
    for (final label in const [
      'Add transaction manually',
      'Scan receipt',
      'Import statement',
      'Import file',
      'Payment sources',
      'Review',
      'Analysis',
      'Insights',
      'Payment settlements',
      'Master data',
      'Rules',
    ]) {
      expect(
        find.descendant(of: navigation, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(
      tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,
      ButlerlySize.pageContentMaxWidth,
    );
    expect(
      find.byKey(const ValueKey('primary-wide-body-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('primary-wide-home-floating-surface')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('home-page-content-surface')),
      findsOneWidget,
    );
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

  testWidgets('Wide primary destinations share the same body surface', (
    tester,
  ) async {
    const size = Size(1200, 800);
    await _pumpAt(tester, size);

    for (final route in ['/', '/transactions', '/add', '/tools', '/settings']) {
      appRouter.go(route);
      await tester.pumpAndSettle();

      expect(find.byType(WidePrimaryShell), findsOneWidget);
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

  testWidgets('Wide More exposes Privacy, Assistant, and About actions', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    expect(
      find.descendant(of: navigation, matching: find.text('Appearance')),
      findsNothing,
    );
    expect(
      find.descendant(of: navigation, matching: find.text('About Butlerly')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wide-collapsed-more')));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsNothing);
    expect(find.text('About Butlerly'), findsOneWidget);

    await tester.tap(find.text('About Butlerly'));
    await tester.pumpAndSettle();
    expect(
      appRouter.routeInformationProvider.value.uri.toString(),
      '/legal-licenses',
    );
    expect(find.byType(LegalLicensesPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(
      appRouter.routeInformationProvider.value.uri.toString(),
      '/settings',
    );
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
    await tester.tap(
      find.descendant(
        of: navigation,
        matching: find.text('Add transaction manually'),
      ),
    );
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
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Scan receipt')),
    );
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

  testWidgets('expanded Wide About Butlerly opens Legal & licenses', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    await tester.ensureVisible(
      find.descendant(of: navigation, matching: find.text('About Butlerly')),
    );
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('About Butlerly')),
    );
    await tester.pumpAndSettle();
    expect(
      appRouter.routeInformationProvider.value.uri.toString(),
      '/legal-licenses',
    );
    expect(find.byType(LegalLicensesPage), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(
      appRouter.routeInformationProvider.value.uri.toString(),
      '/settings',
    );
    expect(find.byType(SettingsPage), findsOneWidget);
  });

  testWidgets('selecting Wide More reveals its child actions', (tester) async {
    await _pumpAt(tester, const Size(1200, 800));

    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    await tester.ensureVisible(
      find.descendant(of: navigation, matching: find.text('More')),
    );
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('More')),
    );
    await tester.pumpAndSettle();

    final about = find.descendant(
      of: navigation,
      matching: find.text('About Butlerly'),
    );
    expect(tester.getRect(about).bottom, lessThanOrEqualTo(800));
    expect(
      find.descendant(of: navigation, matching: find.text('Appearance')),
      findsNothing,
    );
  });

  testWidgets('Assistant Search navigation preserves the focused route stack', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    final navigation = find.byKey(const ValueKey('primary-wide-navigation'));
    await tester.ensureVisible(
      find.descendant(of: navigation, matching: find.text('More')),
    );
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('More')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Assistant')),
    );
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
    expect(find.byType(WidePrimaryShell), findsOneWidget);
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

    await tester.tap(
      find.descendant(of: navigation, matching: find.text('Analysis')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AnalysisPage), findsOneWidget);
    expect(find.byType(WidePrimaryShell), findsOneWidget);
    expect(
      find.byKey(const ValueKey('primary-wide-navigation')),
      findsOneWidget,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(appRouter.routeInformationProvider.value.uri.path, '/tools');
    expect(find.byType(WidePrimaryShell), findsOneWidget);
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
      find.descendant(of: navigation, matching: find.text('Analysis')),
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
    expect(find.byKey(const ValueKey('home-page-content')), findsOneWidget);
    expect(find.byType(WidePrimaryShell), findsOneWidget);
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
    expect(find.byKey(const ValueKey('home-page-content')), findsOneWidget);
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
    await _pumpAt(tester, const Size(800, 800));
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

  testWidgets('direct Wide secondary routes use their documented parent', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));
    appRouter.go('/analysis');
    await tester.pumpAndSettle();

    expect(find.byType(AnalysisPage), findsOneWidget);
    expect(find.byType(WidePrimaryShell), findsOneWidget);
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
    expect(find.byType(WidePrimaryShell), findsOneWidget);
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

  testWidgets('collapsed Wide group popups anchor to their own rail items', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1200, 800));

    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left_rounded));
    await tester.pumpAndSettle();

    Future<({double itemRight, double popupLeft, double popupTop})>
    popupPositionFor(Key itemKey, String parentLabel) async {
      final itemRect = tester.getRect(find.byKey(itemKey));
      await tester.tap(find.byKey(itemKey));
      await tester.pumpAndSettle();
      final popupLabel = find.text(parentLabel).last;
      final popupRect = tester.getRect(
        find.ancestor(of: popupLabel, matching: find.byType(Material)).last,
      );
      await tester.tap(popupLabel);
      await tester.pumpAndSettle();
      return (
        itemRight: itemRect.right,
        popupLeft: popupRect.left,
        popupTop: popupRect.top,
      );
    }

    final add = await popupPositionFor(
      const ValueKey('wide-collapsed-add'),
      'Add',
    );
    final tools = await popupPositionFor(
      const ValueKey('wide-collapsed-tools'),
      'Tools',
    );
    final more = await popupPositionFor(
      const ValueKey('wide-collapsed-more'),
      'More',
    );

    const tolerance = 8.0;
    expect(add.popupLeft, closeTo(add.itemRight, tolerance));
    expect(tools.popupLeft, closeTo(tools.itemRight, tolerance));
    expect(more.popupLeft, closeTo(more.itemRight, tolerance));
    expect({add.popupTop, tools.popupTop, more.popupTop}, hasLength(3));
  });

  testWidgets(
    'resizing across modes preserves the active primary destination',
    (tester) async {
      await _pumpAt(tester, const Size(390, 844));
      await tester.tap(find.bySemanticsLabel('Tools'));
      await tester.pumpAndSettle();

      for (final size in const [
        Size(800, 800),
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
    await _pumpAt(tester, const Size(900, 800));
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
      const size = Size(800, 800);
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
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(AppBar)).width, size.width);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('legal-document-content')))
          .width,
      ButlerlySize.pageContentMaxWidth,
    );
  });
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
  await tester.pumpAndSettle();
}
