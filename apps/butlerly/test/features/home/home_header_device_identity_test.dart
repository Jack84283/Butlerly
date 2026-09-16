import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appRouter.go('/'));

  testWidgets(
    'iPhone landscape right-aligns Home context while keeping phone canvas',
    (tester) async {
      const size = Size(932, 430);
      await _pumpOnIos(tester, size, displaySize: size);

      final expectedRight = size.width - ButlerlySize.phoneGutter;
      expect(
        tester.getRect(find.byKey(const ValueKey('home-header-context'))).right,
        closeTo(expectedRight, 0.01),
      );
      expect(
        tester.getRect(find.byKey(const ValueKey('home-greeting'))).right,
        closeTo(expectedRight, 0.01),
      );
      expect(
        tester.getRect(find.byKey(const Key('home-month-selector'))).right,
        closeTo(expectedRight, 0.01),
      );

      final canvas = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('home-page-canvas')),
      );
      final contentSurface = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('home-page-content-surface')),
      );
      expect(canvas.color, contentSurface.color);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'narrow iPad keeps tablet Home header behavior from device identity',
    (tester) async {
      const windowSize = Size(500, 800);
      await _pumpOnIos(
        tester,
        windowSize,
        displaySize: const Size(1024, 1366),
      );

      final expectedRight = windowSize.width - ButlerlySize.phoneGutter;
      expect(
        tester.getRect(find.byKey(const ValueKey('home-header-context'))).right,
        closeTo(expectedRight, 0.01),
      );
      expect(
        tester.getRect(find.byKey(const Key('home-month-selector'))).right,
        closeTo(expectedRight, 0.01),
      );

      final canvas = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('home-page-canvas')),
      );
      final contentSurface = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('home-page-content-surface')),
      );
      expect(canvas.color, isNot(contentSurface.color));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'Home keeps pull-to-refresh available across the scroll surface',
    (tester) async {
      const size = Size(390, 844);
      await _pumpOnIos(tester, size, displaySize: size);

      final refreshIndicator = tester.widget<RefreshIndicator>(
        find.byKey(const ValueKey('home-refresh-indicator')),
      );
      expect(
        refreshIndicator.triggerMode,
        RefreshIndicatorTriggerMode.anywhere,
      );

      final scrollView = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView).first,
      );
      expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

Future<void> _pumpOnIos(
  WidgetTester tester,
  Size windowSize, {
  required Size displaySize,
}) async {
  tester.view.physicalSize = windowSize;
  tester.view.devicePixelRatio = 1;
  tester.view.display.size = displaySize;
  tester.view.display.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.display.resetSize);
  addTearDown(tester.view.display.resetDevicePixelRatio);

  await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
  await tester.pumpAndSettle();
}
