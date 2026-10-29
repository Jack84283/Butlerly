import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/design_system/components/butlerly_brand_icon.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/budgets/presentation/budgets_page.dart';
import 'package:butlerly/features/financial_profile/presentation/financial_profile_page.dart';
import 'package:butlerly/features/foundation/presentation/privacy_data_page.dart';
import 'package:butlerly/features/foundation/presentation/settings_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app({Locale locale = const Locale('en')}) => ProviderScope(
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SettingsPage(),
    ),
  );

  testWidgets(
    'More Legal card shows approved logo and version on all layouts',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final size in [
        const Size(390, 844),
        const Size(900, 1100),
        const Size(1200, 900),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();

        final versionTile = find.byType(ButlerlyBrandVersionTile);
        for (
          var attempt = 0;
          attempt < 12 && versionTile.evaluate().isEmpty;
          attempt++
        ) {
          final scrollable = find.byType(CustomScrollView);
          if (scrollable.evaluate().isEmpty) break;
          await tester.drag(scrollable.first, const Offset(0, -350));
          await tester.pump();
        }

        expect(versionTile, findsOneWidget, reason: 'viewport $size');
        expect(
          tester.widget<ButlerlyBrandVersionTile>(versionTile).centered,
          isTrue,
          reason: 'More uses the same centered brand style at $size',
        );
        final brandColumn = find.descendant(
          of: versionTile,
          matching: find.byType(Column),
        );
        expect(brandColumn, findsOneWidget);
        final brandPadding = find
            .ancestor(of: brandColumn, matching: find.byType(Padding))
            .first;
        expect(
          tester.widget<Padding>(brandPadding).padding,
          const EdgeInsets.symmetric(vertical: ButlerlySpacing.small),
        );
        expect(
          tester.widget<Column>(brandColumn).children.first,
          isA<Center>(),
        );
        expect(
          find.descendant(
            of: versionTile,
            matching: find.byType(ButlerlyBrandIcon),
          ),
          findsOneWidget,
        );
        expect(find.text('Legal & licenses'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('More has no duplicate transaction or import entries', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Transactions'), findsNothing);
    expect(find.text('Add transaction'), findsNothing);
    expect(find.text('Import & export'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Optional features'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Optional features'), findsOneWidget);
  });

  testWidgets('More display-name label uses regular font weight', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('Display name').first);
    expect(label.style?.fontWeight, FontWeight.w400);
  });

  testWidgets(
    'More exposes separate Budget Settings and Backup & Restore entries',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Budget Settings'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Budget Settings'), findsOneWidget);
      expect(find.text('Backup & Restore'), findsOneWidget);
    },
  );

  testWidgets('settings destinations navigate to their pages', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appRouter.go('/settings');
    addTearDown(() => appRouter.go('/'));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: appRouter,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Budget Settings'));
    await tester.tap(
      find.ancestor(
        of: find.text('Budget Settings'),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/budgets');
    expect(find.byType(BudgetsPage), findsOneWidget);

    appRouter.go('/settings');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Backup & Restore'));
    await tester.tap(
      find.ancestor(
        of: find.text('Backup & Restore'),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/privacy-data');
    expect(find.byType(PrivacyDataPage), findsOneWidget);

    appRouter.go('/settings');
    await tester.pumpAndSettle();
    appRouter.go('/financial-profile');
    await tester.pumpAndSettle();
    expect(
      appRouter.routeInformationProvider.value.uri.path,
      '/financial-profile',
    );
    expect(find.byType(FinancialProfilePage), findsOneWidget);
  });

  testWidgets('compact secondary settings destinations have back affordance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    appRouter.go('/settings');
    addTearDown(() => appRouter.go('/'));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(
          routerConfig: appRouter,
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/settings');
    expect(find.byType(SettingsPage), findsOneWidget);
    for (var attempt = 0; attempt < 10; attempt++) {
      if (find.text('Budget Settings').evaluate().isNotEmpty) break;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pump();
    }
    expect(find.text('Budget Settings'), findsOneWidget);
    await tester.tap(
      find
          .ancestor(
            of: find.text('Budget Settings'),
            matching: find.byType(InkWell),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/budgets');
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(appRouter.routeInformationProvider.value.uri.path, '/settings');
  });

  testWidgets('financial settings entries use localized labels', (
    tester,
  ) async {
    await tester.pumpWidget(app(locale: const Locale('zh')));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('预算设置'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('财务设置'), findsOneWidget);
    expect(find.text('预算设置'), findsOneWidget);
    expect(find.text('财务档案'), findsOneWidget);
    expect(find.text('备份与恢复'), findsOneWidget);
  });

  testWidgets('display-name sheet saves and can reopen without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Display name').first);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('settings-display-name-input'));
    expect(input, findsOneWidget);
    await tester.enterText(input, 'Mia');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Mia'), findsOneWidget);

    await tester.tap(find.text('Display name').first);
    await tester.pumpAndSettle();
    final reopened = tester.widget<TextFormField>(input);
    expect(reopened.initialValue, 'Mia');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('More uses Cupertino symbols for native iOS settings controls', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byIcon(CupertinoIcons.paintbrush), findsOneWidget);
    expect(find.byIcon(Icons.palette_outlined), findsNothing);
    expect(find.byIcon(CupertinoIcons.chevron_down), findsNWidgets(5));
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('desktop More follows the two-column card mockup', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-more-protection')),
      findsOneWidget,
    );
    expect(find.text('Preferences'), findsOneWidget);
    expect(find.text('Privacy & data'), findsOneWidget);
    expect(find.text('Budget Settings'), findsOneWidget);
    expect(find.text('Backup & Restore'), findsOneWidget);
    expect(find.text('Optional features'), findsOneWidget);
    expect(find.text('About Butlerly'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.text('Base currency'), findsOneWidget);
    expect(find.text('External AI consent'), findsOneWidget);

    final valueColumns = find.byKey(
      const ValueKey('desktop-more-value-column'),
    );
    expect(valueColumns, findsNWidgets(8));
    final firstRight = tester.getRect(valueColumns.at(0)).right;
    for (var index = 0; index < 8; index++) {
      expect(tester.getSize(valueColumns.at(index)).width, 140);
      final valueText = tester.widget<Text>(
        find.descendant(
          of: valueColumns.at(index),
          matching: find.byType(Text),
        ),
      );
      expect(valueText.textAlign, TextAlign.end);
      if (index < 7) {
        expect(
          tester.getRect(valueColumns.at(index)).right,
          closeTo(firstRight, 0.1),
        );
      }
    }

    final preferences = tester.getRect(find.text('Preferences'));
    final privacy = tester.getRect(find.text('Privacy & data'));
    expect(preferences.left, lessThan(privacy.left));
    expect(preferences.top, closeTo(privacy.top, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop More shows the dark protection banner palette', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ThemeData.dark(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final banner = tester.widget<Container>(
      find.byKey(const ValueKey('desktop-more-protection')),
    );
    expect(
      (banner.decoration! as BoxDecoration).color,
      const Color(0xFF1E342B),
    );
    expect(tester.takeException(), isNull);
  });
}
