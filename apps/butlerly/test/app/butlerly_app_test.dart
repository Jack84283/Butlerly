import 'dart:io';

import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_button.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supported translations cover every English UI key', () {
    expect(AppLocalizations.missingKeysFor('es'), isEmpty);
    expect(AppLocalizations.missingKeysFor('zh'), isEmpty);
  });

  test('theme surfaces use the approved palette', () {
    expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xFF000000));
    expect(AppTheme.dark.cardTheme.color, const Color(0xFF1C1C1E));
    expect(
      AppTheme.dark.colorScheme.surfaceContainerHighest,
      const Color(0xFF2C2C2E),
    );
    expect(
      AppTheme.dark.textTheme.bodyMedium?.color,
      const Color.fromRGBO(198, 198, 198, 1),
    );
    expect(AppTheme.light.textTheme.bodyMedium?.color, const Color(0xFF6E6E73));
    expect(AppTheme.light.textTheme.bodySmall?.color, const Color(0xFF6E6E73));
    expect(AppTheme.light.cardTheme.color, const Color(0xFFFFFFFF));
    expect(
      AppTheme.light.extension<ButlerlySemanticColors>()?.cardDivider,
      const Color.fromRGBO(198, 198, 200, 0.6),
    );
    expect(
      AppTheme.dark.extension<ButlerlySemanticColors>()?.cardDivider,
      const Color.fromRGBO(78, 78, 78, 1),
    );
  });

  test('button themes use centralized Butlerly geometry', () {
    final theme = AppTheme.light;
    expect(
      theme.filledButtonTheme.style?.padding?.resolve({}),
      const EdgeInsets.symmetric(
        horizontal: ButlerlyButtonTokens.horizontalPadding,
        vertical: ButlerlyButtonTokens.verticalPadding,
      ),
    );
    expect(
      theme.outlinedButtonTheme.style?.minimumSize?.resolve({}),
      const Size(
        ButlerlyButtonTokens.compactHeight,
        ButlerlyButtonTokens.height,
      ),
    );
    expect(
      theme.textButtonTheme.style?.minimumSize?.resolve({}),
      const Size(
        ButlerlyButtonTokens.compactHeight,
        ButlerlyButtonTokens.height,
      ),
    );
    expect(
      theme.textButtonTheme.style?.padding?.resolve({}),
      const EdgeInsets.symmetric(
        horizontal: ButlerlyButtonTokens.horizontalPadding,
        vertical: ButlerlyButtonTokens.verticalPadding,
      ),
    );
    expect(
      theme.iconButtonTheme.style?.minimumSize?.resolve({}),
      const Size.square(ButlerlySize.minimumTarget),
    );
    expect(
      theme.iconButtonTheme.style?.iconSize?.resolve({}),
      ButlerlyButtonTokens.iconSize,
    );
    expect(
      theme.iconButtonTheme.style?.foregroundColor?.resolve({}),
      theme.colorScheme.onSurface,
    );

    final dark = AppTheme.dark;
    expect(
      dark.textButtonTheme.style?.padding?.resolve({}),
      const EdgeInsets.symmetric(
        horizontal: ButlerlyButtonTokens.horizontalPadding,
        vertical: ButlerlyButtonTokens.verticalPadding,
      ),
    );
    expect(
      dark.iconButtonTheme.style?.foregroundColor?.resolve({}),
      dark.colorScheme.onSurface,
    );
  });

  test('selects a local-time greeting', () {
    expect(homeGreetingKey(DateTime(2026, 8, 14, 9)), 'greetingMorning');
    expect(homeGreetingKey(DateTime(2026, 8, 14, 14)), 'greetingAfternoon');
    expect(homeGreetingKey(DateTime(2026, 8, 14, 20)), 'greetingEvening');
  });

  testWidgets('shows the local-first Butlerly home and P0 navigation', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsAtLeastNWidgets(1));
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Local records'), findsOneWidget);
    expect(find.text('Add data'), findsOneWidget);
    expect(find.text('Scan receipt'), findsNothing);
    expect(find.text('Import data'), findsNothing);
    expect(find.text('Search records'), findsNothing);
  });

  testWidgets('Home Add data opens the centralized Add hub', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add data'));
    await tester.pumpAndSettle();

    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Add transaction manually'), findsOneWidget);
    expect(find.text('Add transaction from receipt'), findsOneWidget);
    expect(find.text('Add transaction from statement'), findsOneWidget);
    expect(find.text('Add transaction from local file'), findsOneWidget);
    expect(find.text('Payment sources'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'matches the approved dark Home composition',
    (tester) async {
      setPhoneViewport(tester);
      tester.view.platformDispatcher.platformBrightnessTestValue =
          Brightness.dark;
      addTearDown(
        tester.view.platformDispatcher.clearPlatformBrightnessTestValue,
      );
      HomePage.debugCurrentDate = DateTime(2026, 8, 13);
      addTearDown(() => HomePage.debugCurrentDate = null);

      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pumpAndSettle();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_dark_390x844.png'),
      );
    },
    // This approved baseline was captured with the macOS Flutter renderer.
    // Linux rasterizes text and composited surfaces differently, so an exact
    // pixel comparison there produces a large false-positive diff.
    skip: !Platform.isMacOS,
  );

  for (final size in const [Size(320, 568), Size(390, 844), Size(430, 932)]) {
    testWidgets('Home has no layout overflow at ${size.width}x${size.height}', (
      tester,
    ) async {
      HomePage.debugCurrentDate = DateTime(2026, 8, 13, 9);
      addTearDown(() => HomePage.debugCurrentDate = null);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pumpAndSettle();

      final exception = tester.takeException();
      if (exception is FlutterError) {
        fail(exception.toStringDeep());
      }
      expect(exception, isNull);
      expect(find.text('Good morning'), findsOneWidget);
      expect(find.text('Recent transactions'), findsOneWidget);
    });
  }

  testWidgets('opens the Review and Search destinations', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('You’re all caught up'), findsOneWidget);
    expect(
      find.text('Resolve only the records that genuinely need attention.'),
      findsNothing,
    );

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(
      find.text('Search by merchant, date, amount, category, or notes.'),
      findsNothing,
    );
  });

  testWidgets('uses adaptive navigation at tablet widths', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('allows the user to select dark appearance', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark').last);
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
  });

  testWidgets('allows the user to switch the interface to Simplified Chinese', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chinese (Simplified)').last);
    await tester.pumpAndSettle();

    expect(find.text('设置'), findsAtLeastNWidgets(1));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('交易'), findsAtLeastNWidgets(1));
    expect(find.text('简体中文'), findsOneWidget);
  });

  testWidgets('opens the offline Legal & licenses surface', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Legal & licenses'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Legal & licenses'));
    await tester.pumpAndSettle();

    expect(find.text('Terms of Use'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Software License & Third-Party Notices'), findsOneWidget);
    expect(find.text('AI & Professional-Advice Disclosures'), findsOneWidget);
    expect(find.byType(Card), findsNWidgets(2));
    expect(find.byType(Divider), findsNWidgets(3));

    await tester.tap(find.text('Terms of Use'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Acceptance of Terms'), findsOneWidget);
  });
}

void setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
