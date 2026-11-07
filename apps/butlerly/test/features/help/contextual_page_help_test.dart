import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/features/desktop/presentation/desktop_primary_shell.dart';
import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/features/help/presentation/help_faq_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
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
    '/': 'ch-12',
    '/welcome': 'ch-2',
    '/transactions': 'ch-5',
    '/transactions/add': 'ch-5',
    '/add': 'ch-5',
    '/tools': 'ch-16',
    '/settings': 'ch-17',
    '/legal-licenses': 'ch-17',
    '/analysis': 'ch-14',
    '/insights': 'ch-14',
    '/budgets': 'ch-15',
    '/financial-profile': 'ch-4',
    '/review': 'ch-11',
    '/search': 'ch-13',
    '/payment-settlements': 'ch-16',
    '/rules': 'ch-16',
    '/payment-sources': 'ch-7',
    '/import-export': 'ch-10',
    '/statements': 'ch-10',
    '/receipts/capture': 'ch-9',
    '/privacy-data': 'ch-20',
    '/master-data': 'ch-8',
    '/notifications': 'ch-3',
    '/assistant': 'ch-25',
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
    expect(contextualHelpArticleForPath('/future-page'), 'ch-3');
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
      await tester.tap(help);
      await tester.pumpAndSettle();
      // GoRouter's imperative push can retain the source public URI.
      // Verify the actual destination and selected article instead.
      expect(
        tester.widget<HelpFaqPage>(find.byType(HelpFaqPage)).articleId,
        'ch-14',
      );
      expect(find.byType(HelpGuideArticlePage), findsOneWidget);
      expect(find.text(catalog.articleById('ch-14')!.title), findsWidgets);
      // The Help page must not show a link that points to itself.
      expect(find.byKey(const ValueKey('page-context-help')), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Analysis body'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/analysis');
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
            body: HelpFaqPage(preloadedCatalog: catalog, articleId: 'ch-15'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HelpGuideArticlePage), findsOneWidget);
      expect(
        find.text(catalog.articleById('ch-15', languageCode: language)!.title),
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
                    ButlerlyContextHelpButton(articleId: 'ch-19'),
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
    expect(find.text(catalog.articleById('ch-19')!.title), findsWidgets);
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
    'restore': 'ch-19',
    'portable backup': 'ch-18',
    'evidence deletion': 'ch-21',
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
    expect(find.text(catalog.articleById('ch-3')!.title), findsWidgets);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('router-error-content')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    testWidgets(
      'Help takes the full viewport without navigation panels at $size',
      (tester) async {
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

        expect(find.byType(DesktopPrimaryShell), findsNothing);
        expect(
          find.byKey(const ValueKey('primary-wide-navigation')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('help-search')), findsOneWidget);
        expect(
          tester.widget<ButlerlyPage>(find.byType(ButlerlyPage)).fullWidth,
          isTrue,
        );
        final canvas = find.byKey(const ValueKey('butlerly-page-canvas'));
        expect(tester.getSize(canvas).width, closeTo(size.width, 1));
        expect(tester.getTopLeft(canvas).dx, closeTo(0, 1));

        // The full guide is also a page: it must not restore the side rail or
        // regress to the standard constrained-width layout.
        await tester.tap(find.byKey(const ValueKey('help-full-guide')));
        await tester.pumpAndSettle();
        expect(find.byType(HelpGuideIndexPage), findsOneWidget);
        expect(find.byType(DesktopPrimaryShell), findsNothing);
        expect(
          tester.widget<ButlerlyPage>(find.byType(ButlerlyPage)).fullWidth,
          isTrue,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('direct Help chapter fills the desktop document canvas', (
    tester,
  ) async {
    const size = Size(1440, 900);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appRouter.go('/help?article=ch-14');
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

    expect(find.byType(HelpGuideArticlePage), findsOneWidget);
    expect(find.byType(DesktopPrimaryShell), findsNothing);
    expect(
      tester.widget<ButlerlyPage>(find.byType(ButlerlyPage)).fullWidth,
      isTrue,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('butlerly-page-canvas'))).width,
      closeTo(size.width, 1),
    );
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
