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

  testWidgets('Help searches locally and opens FAQ to full guide chapter', (
    tester,
  ) async {
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();

    expect(find.text('Help & FAQ'), findsOneWidget);
    expect(find.byKey(const ValueKey('help-full-guide')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('help-search')),
      'merge replace',
    );
    await tester.pumpAndSettle();
    final result = find.byKey(const ValueKey('help-hit-FAQ-022'));
    expect(result, findsOneWidget);
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pumpAndSettle();

    expect(find.text('Read detailed guide'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('help-read-guide')));
    await tester.pumpAndSettle();
    expect(find.textContaining('19. RESTORE'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Help no results has a way back to browse', (tester) async {
    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('help-search')),
      'thiscannotpossiblymatchanyhelp',
    );
    await tester.pumpAndSettle();
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
      await tester.enterText(
        find.byKey(const ValueKey('help-search')),
        locale.languageCode == 'zh' ? '同步' : 'sincronizar',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('help-hit-FAQ-009')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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
        final chapter = find.byKey(const ValueKey('help-article-ch-19'));
        await tester.scrollUntilVisible(chapter, 300);
        // The ValueKey is attached directly to the ListTile, not a child.
        // An ancestor lookup therefore incorrectly returns zero matches.
        expect(chapter, findsOneWidget);
        final title = tester.widget<ListTile>(chapter).title! as Text;
        expect(
          title.data,
          locale.languageCode == 'zh' ? contains('恢复') : contains('RESTAURAR'),
        );
        // Open the localized article, not just its table-of-contents entry.
        await tester.tap(chapter);
        await tester.pumpAndSettle();
        expect(find.byType(HelpGuideArticlePage), findsOneWidget);
        expect(
          find.text(
            catalog.articleById('ch-19', languageCode: locale.languageCode)!.title,
          ),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('full User Guide is browsable on a wide layout', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(const Locale('en')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('help-full-guide')));
    await tester.pumpAndSettle();

    expect(find.text('User Guide'), findsOneWidget);
    expect(find.byKey(const ValueKey('help-article-ch-1')), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
