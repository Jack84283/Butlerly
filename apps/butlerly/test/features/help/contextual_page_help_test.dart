import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/features/desktop/presentation/desktop_primary_shell.dart';
import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/features/help/presentation/help_desktop_workspace.dart';
import 'package:butlerly/features/help/presentation/help_faq_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late HelpCatalog catalog;
  setUpAll(() async {
    catalog = await HelpCatalog.load();
  });

  const paths = <String, String>{
    '/welcome': 'guide.getting-started',
    '/': 'home.overview',
    '/transactions': 'transactions.list',
    '/transactions/add': 'add.manual',
    '/add': 'add.overview',
    '/tools': 'tools.overview',
    '/rules': 'tools.rules',
    '/payment-settlements': 'tools.settlements',
    '/settings': 'more.overview',
    '/legal-licenses': 'more.about',
    '/analysis': 'tools.analysis',
    '/insights': 'tools.insights',
    '/budgets': 'tools.budgets',
    '/financial-profile': 'more.financial-profile',
    '/review': 'tools.review',
    '/search': 'transactions.search',
    '/payment-sources': 'add.payment-source',
    '/import-export': 'add.import',
    '/statements': 'add.statement',
    '/receipts/capture': 'add.receipt',
    '/privacy-data': 'more.privacy',
    '/master-data': 'tools.master-data',
    '/notifications': 'more.operational-features',
    '/assistant': 'tools.assistant',
  };

  test('all active destinations have existing, localized guide chapters', () {
    for (final entry in paths.entries) {
      expect(contextualHelpArticleForPath(entry.key), entry.value);
      for (final locale in ['en', 'zh', 'es']) {
        expect(
          catalog.articleById(entry.value, languageCode: locale),
          isNotNull,
          reason: '${entry.key} → ${entry.value} must exist in $locale',
        );
      }
    }
    for (final path in ['/help', '/launch']) {
      expect(contextualHelpArticleForPath(path), isNull);
    }
    expect(contextualHelpArticleForPath('/future-page'), 'guide.getting-started');
  });

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('page ? opens the correct chapter and returns at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        initialLocation: '/analysis',
        routes: [
          GoRoute(
            path: '/analysis',
            builder: (_, _) => const Scaffold(
              body: ButlerlyPage(
                title: 'Analysis',
                children: [Text('Analysis body')],
              ),
            ),
          ),
          GoRoute(
            path: '/help',
            builder: (_, state) => Scaffold(
              body: HelpFaqPage(
                preloadedCatalog: catalog,
                articleId: state.uri.queryParameters['article'],
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final help = find.byKey(const ValueKey('page-context-help'));
      expect(help, findsOneWidget);
      expect(find.byTooltip('Help for this page'), findsOneWidget);
      final visual = find.byKey(const ValueKey('page-context-help-visual'));
      expect(visual, findsOneWidget);
      expect(tester.getSize(visual), const Size.square(32));
      // The 12px leading inset is separate from the 44px touch target.
      expect(
        find.ancestor(
          of: help,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Padding &&
                widget.padding == const EdgeInsets.only(left: 12),
          ),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(help), const Size.square(44));
      final helpIcon = tester.widget<Icon>(
        find.descendant(
          of: visual,
          matching: find.byIcon(Icons.question_mark_rounded),
        ),
      );
      expect(helpIcon.size, 16);
      final colors = Theme.of(tester.element(help)).colorScheme;
      expect(helpIcon.color, colors.onPrimary);
      final paintedCircle = tester.widget<DecoratedBox>(
        find.descendant(of: visual, matching: find.byType(DecoratedBox)),
      );
      final decoration = paintedCircle.decoration as BoxDecoration;
      expect(decoration.color, colors.primary);
      expect(decoration.shape, BoxShape.circle);
      await tester.tap(help);
      await tester.pumpAndSettle();
      // GoRouter's imperative push can retain the source public URI.
      // Verify the actual destination and selected article instead.
      expect(
        tester.widget<HelpFaqPage>(find.byType(HelpFaqPage)).articleId,
        'tools.analysis',
      );
      if (size.width >= 1024) {
        expect(find.byType(HelpDesktopWorkspace), findsOneWidget);
        expect(
          find.byKey(const ValueKey('help-desktop-article-tools.analysis')),
          findsOneWidget,
        );
      } else {
        expect(find.byType(HelpGuideArticlePage), findsOneWidget);
      }
      expect(find.text(catalog.articleById('tools.analysis')!.title), findsWidgets);
      // The Help page must not show a link that points to itself.
      expect(find.byKey(const ValueKey('page-context-help')), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Analysis body'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/analysis');
      expect(tester.takeException(), isNull);
    });
  }

  // Payment Settlement details are pushed with Navigator.push(MaterialPageRoute),
  // not declared as a GoRouter route. Contextual Help must not attempt to
  // recover a GoRouterState from that imperative route during build.
  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('Settlement detail Help survives MaterialPageRoute at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/payment-settlements',
        routes: [
          GoRoute(
            path: '/payment-settlements',
            builder: (_, _) => Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    key: const ValueKey('open-settlement-detail'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: ButlerlyPage(
                            title: 'Payment Settlement',
                            children: [Text('Settlement detail body')],
                          ),
                        ),
                      ),
                    ),
                    child: const Text('Open settlement'),
                  ),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/help',
            builder: (_, state) => Scaffold(
              body: HelpFaqPage(
                preloadedCatalog: catalog,
                articleId: state.uri.queryParameters['article'],
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('open-settlement-detail')));
      await tester.pumpAndSettle();
      expect(find.text('Settlement detail body'), findsOneWidget);
      expect(find.byKey(const ValueKey('page-context-help')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('page-context-help')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<HelpFaqPage>(find.byType(HelpFaqPage)).articleId,
        'tools.settlements',
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Settlement detail body'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final language in ['en', 'zh', 'es']) {
    testWidgets('direct page Help uses the $language guide', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: HelpFaqPage(preloadedCatalog: catalog, articleId: 'tools.budgets'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HelpGuideArticlePage), findsOneWidget);
      expect(
        find.text(catalog.articleById('tools.budgets', languageCode: language)!.title),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('setup or recovery can read Help without a router', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  actions: const [
                    ButlerlyContextHelpButton(articleId: 'more.restore'),
                  ],
                ),
                body: const Text('Safe recovery screen'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-context-help')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('page-context-help')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('context-help-offline-reader')),
      findsOneWidget,
    );
    expect(find.text(catalog.articleById('more.restore')!.title), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('context-help-close')));
    await tester.pumpAndSettle();
    expect(find.text('Safe recovery screen'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('context-help-offline-reader')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  // Mirrors MaterialApp.router.builder in ButlerlyApp: the recovery workflow
  // replaces the GoRouter child and is hosted in a local Navigator.
  for (final recovery in const <String, String>{
    'restore': 'more.restore',
    'portable backup': 'more.backup',
    'evidence deletion': 'guide.getting-started1',
  }.entries) {
    testWidgets('${recovery.key} recovery Help returns to the blocked flow', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: Text('Normal router content')),
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
          builder: (_, child) => ButlerlyRouterlessRecoveryHost(
            key: ValueKey('${recovery.key}-help-host'),
            child: Scaffold(
              appBar: AppBar(
                actions: [ButlerlyContextHelpButton(articleId: recovery.value)],
              ),
              body: Text('${recovery.key} recovery remains active'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Normal router content'), findsNothing);
      expect(
        find.text('${recovery.key} recovery remains active'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('page-context-help')));
      await tester.pumpAndSettle();
      final helpReader = find.byKey(
        const ValueKey('context-help-offline-reader'),
      );
      expect(helpReader, findsOneWidget);
      expect(
        find.text(catalog.articleById(recovery.value)!.title),
        findsWidgets,
      );

      // A navigator pop is also the action used for system Back on this route.
      final navigator = Navigator.of(tester.element(helpReader));
      expect(navigator.canPop(), isTrue);
      expect(await navigator.maybePop(), isTrue);
      await tester.pumpAndSettle();

      expect(helpReader, findsNothing);
      expect(
        find.text('${recovery.key} recovery remains active'),
        findsOneWidget,
      );
      expect(find.text('Normal router content'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  // The app root now uses ButlerlyRouterlessRecoveryHost for first-use,
  // rather than injecting its setup screen into a raw OverlayEntry.
  for (final stage in const <String, String>{
    'preferences': 'guide.getting-started',
    'financial profile introduction': 'more.financial-profile',
  }.entries) {
    testWidgets('${stage.key} Help dismisses via system Back and Escape', (
      tester,
    ) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('Underlying app')),
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
          builder: (_, child) => ButlerlyRouterlessRecoveryHost(
            key: const ValueKey('first-use-help-host'),
            child: Scaffold(
              appBar: AppBar(
                actions: [ButlerlyContextHelpButton(articleId: stage.value)],
              ),
              body: Text('${stage.key} stays active'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Underlying app'), findsNothing);
      expect(find.text('${stage.key} stays active'), findsOneWidget);
      final help = find.byKey(const ValueKey('page-context-help'));

      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('context-help-offline-reader')),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('context-help-offline-reader')),
        findsNothing,
      );
      expect(find.text('${stage.key} stays active'), findsOneWidget);

      await tester.tap(help);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('context-help-offline-reader')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('context-help-offline-reader')),
        findsNothing,
      );
      expect(find.text('${stage.key} stays active'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('unrecognized route provides Help and returns to error', (
    tester,
  ) async {
    appRouter.go('/unknown-context-help-test-route');
    addTearDown(() => appRouter.go('/'));
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: appRouter,
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
    expect(find.byKey(const ValueKey('router-error-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-context-help')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('page-context-help')));
    await tester.pumpAndSettle();
    expect(find.byType(HelpGuideArticlePage), findsOneWidget);
    expect(find.text(catalog.articleById('guide.getting-started')!.title), findsWidgets);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('router-error-content')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact Help keeps the single-column browse and guide', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appRouter.go('/help');
    addTearDown(() => appRouter.go('/'));

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: appRouter,
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

    expect(find.byType(HelpDesktopWorkspace), findsNothing);
    expect(find.byKey(const ValueKey('help-search')), findsOneWidget);
    expect(find.byKey(const ValueKey('help-full-guide')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('help-full-guide')));
    await tester.pumpAndSettle();
    expect(find.byType(HelpGuideIndexPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Help has menu, content card and detail card', (
    tester,
  ) async {
    const size = Size(1440, 900);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appRouter.go('/help');
    addTearDown(() => appRouter.go('/'));

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: appRouter,
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

    expect(find.byType(HelpDesktopWorkspace), findsOneWidget);
    expect(find.byType(DesktopPrimaryShell), findsNothing);
    final menu = find.byKey(const ValueKey('help-desktop-menu'));
    final content = find.byKey(const ValueKey('help-desktop-content'));
    final detail = find.byKey(const ValueKey('help-desktop-detail'));
    expect(menu, findsOneWidget);
    expect(content, findsOneWidget);
    expect(detail, findsOneWidget);
    expect(tester.getRect(menu).right, lessThan(tester.getRect(content).left));
    expect(
      tester.getRect(content).right,
      lessThan(tester.getRect(detail).left),
    );
    expect(tester.getRect(detail).right, lessThanOrEqualTo(size.width));
    expect(find.byKey(const ValueKey('help-search')), findsOneWidget);

    // Selecting a different middle-column entry updates the detail in place.
    final secondChapter = catalog.guide[1];
    await tester.tap(
      find.byKey(ValueKey('help-desktop-item-${secondChapter.id}')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('help-desktop-article-${secondChapter.id}')),
      findsOneWidget,
    );

    final category = catalog.categories.first;
    await tester.tap(find.byKey(ValueKey('help-desktop-menu-$category')));
    await tester.pumpAndSettle();
    final faq = catalog.faqs.firstWhere((entry) => entry.category == category);
    expect(find.byKey(ValueKey('help-desktop-faq-${faq.id}')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('help-desktop-read-guide')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('help-desktop-article-${faq.guideId}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Help search updates the list and detail selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(home: HelpFaqPage(preloadedCatalog: catalog)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('help-search')), 'backup');
    await tester.pumpAndSettle();
    final results = catalog.search('backup');
    expect(results, isNotEmpty);
    expect(
      find.byKey(ValueKey('help-desktop-item-${results.first.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('help-desktop-detail-${results.first.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('direct Help chapter selects detail in the desktop workspace', (
    tester,
  ) async {
    const size = Size(1440, 900);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appRouter.go('/help?article=tools.analysis');
    addTearDown(() => appRouter.go('/'));

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: appRouter,
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

    expect(find.byType(HelpDesktopWorkspace), findsOneWidget);
    expect(find.byType(DesktopPrimaryShell), findsNothing);
    expect(
      find.byKey(const ValueKey('help-desktop-article-tools.analysis')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('help-desktop-content')), findsOneWidget);
    expect(find.byKey(const ValueKey('help-desktop-detail')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown direct chapter falls back to Help browsing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HelpFaqPage(
            preloadedCatalog: catalog,
            articleId: 'missing-chapter',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('help-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
