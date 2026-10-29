import 'package:butlerly/app/session/butlerly_session_guard.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_brand_icon.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/features/foundation/presentation/butlerly_launch_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('wide launch opens Home', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var elapsed = Duration.zero;
    final router = GoRouter(
      initialLocation: '/launch',
      routes: [
        GoRoute(
          path: '/launch',
          builder: (_, _) => ButlerlyLaunchPage(elapsedNow: () => elapsed),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();
    final brand = find.byType(ButlerlyBrandIcon);
    expect(brand, findsOneWidget);
    expect(tester.widget<ButlerlyBrandIcon>(brand).size, 80);
    final tagline = find.byKey(const ValueKey('butlerly-launch-tagline'));
    expect(tagline, findsOneWidget);
    final taglineText = tester.widget<Text>(tagline);
    expect(taglineText.data, 'YOUR MONEY. YOUR DEVICE. YOUR CONTROL.');
    expect(
      taglineText.style?.fontFamily,
      ButlerlyTypography.editorialFontFamily,
    );
    expect(taglineText.textAlign, TextAlign.center);
    expect(taglineText.style?.color, ButlerlySemanticColors.light.warning);
    expect(
      tester.getTopLeft(tagline).dy,
      greaterThan(tester.getBottomLeft(find.text('Butlerly')).dy),
    );
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
    elapsed = ButlerlySessionConfig.launchDuration;
    await tester.pump(ButlerlySessionConfig.launchDuration);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('dark launch uses the existing gold accent', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: const ButlerlyLaunchSurface()),
    );
    await tester.pumpAndSettle();

    final tagline = tester.widget<Text>(
      find.byKey(const ValueKey('butlerly-launch-tagline')),
    );
    expect(tagline.data, 'YOUR MONEY. YOUR DEVICE. YOUR CONTROL.');
    expect(tagline.style?.color, ButlerlySemanticColors.dark.warning);
    expect(tagline.style?.fontFamily, ButlerlyTypography.editorialFontFamily);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact launch tagline is localized and fits', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        locale: const Locale('zh', 'CN'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const ButlerlyLaunchSurface(),
      ),
    );
    await tester.pumpAndSettle();

    final name = find.text('账房先生');
    final tagline = find.byKey(const ValueKey('butlerly-launch-tagline'));
    expect(name, findsOneWidget);
    expect(tagline, findsOneWidget);
    final text = tester.widget<Text>(tagline);
    expect(text.data, '财务数据，尽在掌控。');
    expect(text.style?.fontFamily, ButlerlyTypography.editorialFontFamily);
    expect(text.style?.color, ButlerlySemanticColors.light.warning);
    expect(
      tester.getTopLeft(tagline).dy,
      greaterThan(tester.getBottomLeft(name).dy),
    );
    expect(tester.getRect(tagline).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(tagline).right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('launch countdown pauses while Butlerly is backgrounded', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    final router = GoRouter(
      initialLocation: '/launch',
      routes: [
        GoRoute(
          path: '/launch',
          builder: (_, _) => ButlerlyLaunchPage(elapsedNow: () => elapsed),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();

    elapsed = const Duration(seconds: 2);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    elapsed = const Duration(seconds: 12);
    await tester.pump(const Duration(seconds: 10));
    expect(
      find.byKey(const ValueKey('butlerly-launch-screen')),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    elapsed = const Duration(seconds: 14, milliseconds: 999);
    await tester.pump(const Duration(seconds: 2, milliseconds: 999));
    expect(
      find.byKey(const ValueKey('butlerly-launch-screen')),
      findsOneWidget,
    );

    elapsed = const Duration(seconds: 15);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('redundant resume does not restart the launch countdown', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    final router = GoRouter(
      initialLocation: '/launch',
      routes: [
        GoRoute(
          path: '/launch',
          builder: (_, _) => ButlerlyLaunchPage(elapsedNow: () => elapsed),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();

    elapsed = const Duration(seconds: 2);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    elapsed = const Duration(seconds: 4, milliseconds: 999);
    await tester.pump(const Duration(seconds: 2, milliseconds: 999));
    expect(
      find.byKey(const ValueKey('butlerly-launch-screen')),
      findsOneWidget,
    );

    elapsed = const Duration(seconds: 5);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
