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
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/analysis/presentation/analysis_page.dart';
import 'package:butlerly/features/desktop/presentation/desktop_primary_shell.dart';
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
      expect(tester.getSize(bodySurface), size);
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

    expect(ButlerlyLayout.mode(size), ButlerlyLayoutMode.wide);
    expect(find.byType(DesktopPrimaryShell), findsOneWidget);
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

  testWidgets(
    'collapsed Wide Add and Tools open their hubs, More anchors a popup',
    (tester) async {
      await _pumpAt(tester, const Size(1200, 800));

      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_left_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('wide-collapsed-add')));
      await tester.pumpAndSettle();
      expect(appRouter.routeInformationProvider.value.uri.path, '/add');
      expect(find.byKey(const ValueKey('desktop-add-actions')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('wide-collapsed-tools')));
      await tester.pumpAndSettle();
      expect(appRouter.routeInformationProvider.value.uri.path, '/tools');
      expect(
        find.byKey(const ValueKey('desktop-tools-actions')),
        findsOneWidget,
      );

      final moreItem = find.byKey(const ValueKey('wide-collapsed-more'));
      final itemRect = tester.getRect(moreItem);
      await tester.tap(moreItem);
      await tester.pumpAndSettle();

      final popupLabel = find.text('More').last;
      final popupRect = tester.getRect(
        find.ancestor(of: popupLabel, matching: find.byType(Material)).last,
      );
      expect(popupRect.left, closeTo(itemRect.right, 8));
      await tester.tap(popupLabel);
      await tester.pumpAndSettle();
    },
  );

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
