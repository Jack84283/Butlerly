import 'package:butlerly/design_system/components/butlerly_components.dart';
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
