import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/features/help/presentation/help_faq_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HelpCatalog catalog;

  setUpAll(() async {
    catalog = await HelpCatalog.load();
  });

  Widget app(Locale locale) => MaterialApp(
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: HelpFaqPage(preloadedCatalog: catalog),
  );

  Future<void> enterHelpQuery(WidgetTester tester, String query) async {
    await tester.enterText(find.byKey(const ValueKey('help-search')), query);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('Help searches locally and opens FAQ to full guide chapter', (
    tester,
  ) async {
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Help & FAQ'), findsOneWidget);
    expect(find.byKey(const ValueKey('help-full-guide')), findsOneWidget);

    await enterHelpQuery(tester, 'merge replace');
    final result = find.byKey(const ValueKey('help-hit-FAQ-022'));
    expect(result, findsOneWidget);
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pumpAndSettle();

    expect(find.text('Read detailed guide'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('help-read-guide')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Restore'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Help no results has a way back to browse', (tester) async {
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();
    await enterHelpQuery(tester, 'thiscannotpossiblymatchanyhelp');
    expect(
      find.byKey(const ValueKey('help-no-results-topic-Backup & Recovery')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('help-no-results-support')),
      findsOneWidget,
    );
    expect(find.text('No matching help topics'), findsOneWidget);
    await tester.tap(find.text('All topics'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('help-full-guide')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('zh', 'CN'), const Locale('es')]) {
    testWidgets('Help displays localized FAQ at ${locale.languageCode}', (
      tester,
    ) async {
      await tester.pumpWidget(app(locale));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('help-search')), findsOneWidget);
      await enterHelpQuery(
        tester,
        locale.languageCode == 'zh' ? '同步' : 'sincronizar',
      );
      expect(find.byKey(const ValueKey('help-hit-FAQ-009')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Help debounces rapid typing and cancels pending search', (
    tester,
  ) async {
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();

    final input = find.byKey(const ValueKey('help-search'));
    await tester.enterText(input, 'unmatched string');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('help-hit-FAQ-022')), findsNothing);

    await tester.enterText(input, 'merge replace');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('help-hit-FAQ-022')), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('help-hit-FAQ-022')), findsOneWidget);

    await tester.enterText(input, 'another pending query');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('help-full-guide')), findsOneWidget);
    expect(find.byKey(const ValueKey('help-hit-FAQ-022')), findsNothing);
  });

  for (final locale in [
    const Locale('en'),
    const Locale('zh', 'CN'),
    const Locale('es'),
  ]) {
    testWidgets(
      'no-results topics and safe support for ${locale.languageCode}',
      (tester) async {
        await tester.pumpWidget(app(locale));
        await tester.pumpAndSettle();
        await enterHelpQuery(tester, 'zzzzunknownhelpterm');
        expect(
          find.byKey(const ValueKey('help-no-results-support')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('help-no-results-topic-Backup & Recovery')),
          findsOneWidget,
        );

        final support = find.byKey(const ValueKey('help-no-results-support'));
        await tester.ensureVisible(support);
        await tester.tap(support);
        await tester.pumpAndSettle();
        expect(find.byType(HelpFaqDetailPage), findsOneWidget);
        expect(
          find.text(
            catalog
                .faqById('FAQ-030')!
                .translation(locale.languageCode)
                .question,
          ),
          findsOneWidget,
        );
        Navigator.of(tester.element(find.byType(HelpFaqDetailPage))).pop();
        await tester.pumpAndSettle();

        final topic = find.byKey(
          const ValueKey('help-no-results-topic-Backup & Recovery'),
        );
        await tester.ensureVisible(topic);
        await tester.tap(topic);
        await tester.pumpAndSettle();
        // The selected topic can be below the fold after returning from
        // the support article. Scroll to the actual FAQ before asserting.
        final faq = find.byKey(const ValueKey('help-faq-FAQ-022'));
        // Explicitly use the page's outer scroll view. TextField adds an
        // inner Scrollable, making the default finder ambiguous.
        await tester.scrollUntilVisible(
          faq,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        // scrollUntilVisible builds the lazy row but can leave its center
        // outside the hit-testable viewport, particularly in Chinese.
        // Align the row well inside the outer page before tapping it.
        await Scrollable.ensureVisible(
          tester.element(faq),
          alignment: 0.35,
          duration: const Duration(milliseconds: 150),
        );
        await tester.pumpAndSettle();
        expect(faq, findsOneWidget);
        await tester.tap(faq);
        await tester.pumpAndSettle();
        expect(find.byType(HelpFaqDetailPage), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in [const Locale('zh', 'CN'), const Locale('es')]) {
    testWidgets(
      'full guide uses the selected language: ${locale.languageCode}',
      (tester) async {
        await tester.pumpWidget(app(locale));
        await tester.pumpAndSettle();
        final guide = find.byKey(const ValueKey('help-full-guide'));
        await tester.ensureVisible(guide);
        await tester.tap(guide);
        await tester.pumpAndSettle();
        final chapter = find.byKey(const ValueKey('help-article-more.restore'));
        await tester.scrollUntilVisible(chapter, 300);
        // The ValueKey is attached directly to the ListTile, not a child.
        // An ancestor lookup therefore incorrectly returns zero matches.
        expect(chapter, findsOneWidget);
        final title = tester.widget<ListTile>(chapter).title! as Text;
        expect(
          title.data,
          locale.languageCode == 'zh' ? contains('恢复') : contains('Restaurar'),
        );
        // Open the localized article, not just its table-of-contents entry.
        await tester.tap(chapter);
        await tester.pumpAndSettle();
        expect(find.byType(HelpGuideArticlePage), findsOneWidget);
        expect(
          find.text(
            catalog
                .articleById('more.restore', languageCode: locale.languageCode)!
                .title,
          ),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in [
    const Locale('en'),
    const Locale('zh', 'CN'),
    const Locale('es'),
  ]) {
    testWidgets(
      'related topics open localized article on phone: ${locale.languageCode}',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: HelpGuideArticlePage(
              article: catalog.articleById(
                'home.overview',
                languageCode: locale.languageCode,
              )!,
              catalog: catalog,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final link = find.byKey(const ValueKey('help-related-home.summary'));
        // Related Topics are below a lazily built guide article.
        await tester.scrollUntilVisible(
          link,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(link);
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(
          find.text(
            catalog
                .articleById('home.summary', languageCode: locale.languageCode)!
                .title,
          ),
          findsWidgets,
        );
        await tester.tap(find.byIcon(Icons.arrow_back_rounded).last);
        await tester.pumpAndSettle();
        // The original article can remain scrolled to its related links;
        // verify the restored route's article instead of offscreen text.
        expect(
          tester
              .widget<HelpGuideArticlePage>(find.byType(HelpGuideArticlePage))
              .article
              .id,
          'home.overview',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'desktop related links select a new topic in the same workspace',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(const Locale('en')));
      await tester.pumpAndSettle();
      final first = find.byKey(
        const ValueKey('help-desktop-item-home.overview'),
      );
      await tester.scrollUntilVisible(
        first,
        220,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('help-desktop-item-list')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(first);
      await tester.pumpAndSettle();
      final related = find.byKey(const ValueKey('help-related-home.summary'));
      await tester.scrollUntilVisible(
        related,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(
                const ValueKey('help-desktop-detail-home.overview'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(related);
      await tester.tap(related);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-desktop-article-home.summary')),
        findsOneWidget,
      );
      final next = find.byKey(const ValueKey('help-related-home.trends'));
      await tester.scrollUntilVisible(
        next,
        300,
        scrollable: find
            .descendant(
              of: find.byKey(
                const ValueKey('help-desktop-detail-home.summary'),
              ),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-desktop-article-home.trends')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('help-related-back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-desktop-article-home.summary')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('help-related-back')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('help-desktop-article-home.overview')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('help-related-back')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop FAQ Read more returns to search and originating FAQ', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();
    await enterHelpQuery(tester, 'merge replace');
    final faq = find.byKey(const ValueKey('help-desktop-item-FAQ-022'));
    expect(faq, findsOneWidget);
    await tester.tap(faq);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('help-desktop-read-guide')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('help-desktop-article-more.restore')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('help-related-back')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('help-desktop-faq-FAQ-022')),
      findsOneWidget,
    );
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('help-search')))
          .controller!
          .text,
      'merge replace',
    );
    expect(find.byKey(const ValueKey('help-related-back')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full User Guide is browsable on a wide layout', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();
    // Wide Help now opens directly into the three-pane guide workspace.
    expect(
      find.byKey(const ValueKey('help-desktop-workspace')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('help-desktop-menu')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('help-desktop-item-guide.introduction')),
      findsOneWidget,
    );
    // The first displayed chapter need not be guide.introduction; choose it explicitly.
    await tester.tap(
      find.byKey(const ValueKey('help-desktop-item-guide.introduction')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('help-desktop-article-guide.introduction')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
