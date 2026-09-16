import 'dart:ui' show Tristate;

import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
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
  setUp(() => appRouter.go('/'));

  test('supported translations cover every English UI key', () {
    expect(AppLocalizations.missingKeysFor('es'), isEmpty);
    expect(AppLocalizations.missingKeysFor('zh'), isEmpty);
  });

  test('theme surfaces use the quiet-premium palette', () {
    expect(AppTheme.dark.scaffoldBackgroundColor, const Color(0xFF0A0A0D));
    expect(AppTheme.dark.cardTheme.color, const Color(0xFF111114));
    expect(
      AppTheme.dark.colorScheme.surfaceContainerHighest,
      const Color(0xFF17171C),
    );
    expect(
      AppTheme.dark.textTheme.bodyMedium?.color,
      const Color(0xFFB8B2AA),
    );
    expect(AppTheme.light.textTheme.bodyMedium?.color, const Color(0xFF68635E));
    expect(AppTheme.light.textTheme.bodySmall?.color, const Color(0xFF68635E));
    expect(AppTheme.light.cardTheme.color, const Color(0xFFFFFFFF));
    expect(
      AppTheme.light.extension<ButlerlySemanticColors>()?.cardDivider,
      const Color(0xFFD9D4CE),
    );
    expect(
      AppTheme.dark.extension<ButlerlySemanticColors>()?.cardDivider,
      const Color(0xFF25252B),
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

  testWidgets('shows the monthly spending Home and P0 navigation', (
    tester,
  ) async {
    HomePage.debugCurrentDate = DateTime(2026, 8, 13, 9);
    addTearDown(() => HomePage.debugCurrentDate = null);
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    expect(find.text('Butlerly'), findsOneWidget);
    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Total spending'), findsOneWidget);
    expect(find.text('Spending trend'), findsOneWidget);
    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('Recent transactions'), findsOneWidget);
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Home'), findsAtLeastNWidgets(1));
    expect(find.text('Transactions'), findsOneWidget);
    expect(find.text('Tools'), findsOneWidget);
    expect(find.bySemanticsLabel('Add transaction'), findsOneWidget);
    expect(find.text('More'), findsAtLeastNWidgets(1));
    expect(find.text('More...'), findsNothing);
    expect(find.text('Local records'), findsNothing);
    expect(find.text('Add data'), findsNothing);
    expect(find.text('Quick actions'), findsNothing);
  });

  testWidgets('Home month selector switches months and disables the future', (
    tester,
  ) async {
    HomePage.debugCurrentDate = DateTime(2026, 8, 13, 9);
    addTearDown(() => HomePage.debugCurrentDate = null);
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-month-selector')));
    await tester.pumpAndSettle();
    expect(find.text('2026'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-month-2026-7')));
    await tester.pumpAndSettle();
    expect(find.text('July 2026'), findsOneWidget);
    expect(find.text('Total spending'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-month-selector')));
    await tester.pumpAndSettle();
    final future = tester.widget<OutlinedButton>(
      find.byKey(const Key('home-month-2026-9')),
    );
    expect(future.onPressed, isNull);
  });

  testWidgets(
    'Add primary tab opens the existing Add hub and system back returns Home',
    (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Add transaction'));
      await tester.pumpAndSettle();

      expect(find.text('Add'), findsAtLeastNWidgets(1));
      expect(
        tester
                .getSemantics(find.bySemanticsLabel('Add transaction'))
                .flagsCollection
                .isSelected ==
            Tristate.isTrue,
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('No transactions yet'), findsOneWidget);
    },
  );

  testWidgets('primary navigation restores every selected tab after Add', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    for (final destination in const ['Transactions', 'Tools', 'More']) {
      await tester.tap(find.text(destination).last);
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Add transaction'));
      await tester.pumpAndSettle();
      expect(find.text('Add'), findsAtLeastNWidgets(1));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
                .getSemantics(find.text(destination).last)
                .flagsCollection
                .isSelected ==
            Tristate.isTrue,
        isTrue,
      );
      expect(
        tester
                .getSemantics(find.bySemanticsLabel('Add transaction'))
                .flagsCollection
                .isSelected ==
            Tristate.isTrue,
        isFalse,
      );
      final selectedCount = const ['Home', 'Transactions', 'Tools', 'More']
          .where(
            (label) =>
                tester
                    .getSemantics(find.text(label).last)
                    .flagsCollection
                    .isSelected ==
                Tristate.isTrue,
          )
          .length;
      expect(selectedCount, 1);
    }
  });

  testWidgets('Tools cards preserve order and all direct routes', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    appRouter.go('/tools');
    await tester.pumpAndSettle();
    final labels = ['Search', 'Review', 'Analysis', 'Insights'];
    final positions = labels
        .map((label) => tester.getTopLeft(find.text(label).last).dy)
        .toList();
    expect(positions, orderedEquals([...positions]..sort()));
    for (final label in labels) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      switch (label) {
        case 'Search':
          expect(find.byType(SearchBar), findsOneWidget);
        case 'Review':
          expect(find.text('You’re all caught up'), findsOneWidget);
        case 'Analysis':
          expect(find.text('Analysis'), findsOneWidget);
        case 'Insights':
          expect(find.text('Insights'), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Add transaction'), findsNothing);
      appRouter.go('/tools');
      await tester.pumpAndSettle();
    }
    for (final route in const [
      '/search',
      '/review',
      '/review?view=duplicates',
      '/analysis',
      '/insights',
    ]) {
      appRouter.go(route);
      await tester.pumpAndSettle();
      switch (route) {
        case '/search':
          expect(find.byType(SearchBar), findsOneWidget);
        case '/review':
        case '/review?view=duplicates':
          expect(find.text('You’re all caught up'), findsOneWidget);
        case '/analysis':
          expect(find.text('Analysis'), findsOneWidget);
        case '/insights':
          expect(find.text('Insights'), findsOneWidget);
      }
      expect(find.bySemanticsLabel('Add transaction'), findsNothing);
      appRouter.go('/tools');
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'More opens More without duplicate Transactions or optional features',
    (tester) async {
      setPhoneViewport(tester);
      await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('More').last);
      await tester.pumpAndSettle();

      expect(find.text('More'), findsAtLeastNWidgets(1));
      expect(find.text('Add transaction'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Optional features'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Optional features'), findsOneWidget);
      expect(find.text('Insights'), findsNothing);
      expect(find.text('Notifications'), findsNothing);

      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
    },
  );

  testWidgets('dark Home preserves the approved monthly hierarchy', (
    tester,
  ) async {
    setPhoneViewport(tester);
    tester.view.platformDispatcher.platformBrightnessTestValue =
        Brightness.dark;
    addTearDown(
      tester.view.platformDispatcher.clearPlatformBrightnessTestValue,
    );
    HomePage.debugCurrentDate = DateTime(2026, 8, 13, 20);
    addTearDown(() => HomePage.debugCurrentDate = null);

    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    expect(find.text('Butlerly'), findsOneWidget);
    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('Good evening'), findsOneWidget);
    expect(find.text('Total spending'), findsOneWidget);
    expect(find.text('Spending trend'), findsOneWidget);
    expect(find.text('Spending by category'), findsOneWidget);
    expect(find.text('Recent transactions'), findsOneWidget);
  });

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
      expect(find.text('August 2026'), findsOneWidget);
      expect(find.text('Total spending'), findsOneWidget);
      expect(find.text('Recent transactions'), findsOneWidget);
    });
  }

  testWidgets('opens Tools and its Review and Search destinations', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();
    expect(
      find.text('Useful ways to explore and understand your records.'),
      findsOneWidget,
    );
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Analysis'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('You’re all caught up'), findsOneWidget);
    expect(
      find.text('Resolve only the records that genuinely need attention.'),
      findsNothing,
    );

    appRouter.go('/tools');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(
      find.text('Search by merchant, date, amount, category, or notes.'),
      findsNothing,
    );
  });

  testWidgets('uses bottom navigation at tablet widths', (tester) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationRail), findsNothing);
    expect(
      find.byKey(const ValueKey('primary-ipad-navigation')),
      findsOneWidget,
    );
  });

  testWidgets('allows the user to select dark appearance', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('More').last);
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

    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chinese (Simplified)').last);
    await tester.pumpAndSettle();

    expect(find.text('更多'), findsAtLeastNWidgets(1));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('交易'), findsAtLeastNWidgets(1));
    expect(find.text('简体中文'), findsOneWidget);
  });

  testWidgets('opens the offline Legal & licenses surface', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('More').last);
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