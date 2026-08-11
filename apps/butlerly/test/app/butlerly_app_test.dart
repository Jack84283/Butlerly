import 'dart:io';

import 'package:butlerly/app/butlerly_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    expect(find.text('Add transaction'), findsOneWidget);
    expect(find.text('Scan receipt'), findsOneWidget);
    expect(find.text('Import data'), findsOneWidget);
    expect(find.text('Search records'), findsOneWidget);
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

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchBar), findsOneWidget);
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
}

void setPhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
