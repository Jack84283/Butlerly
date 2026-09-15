import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appRouter.go('/'));

  test('window class uses the shortest logical side', () {
    expect(
      ButlerlySize.isTabletViewport(const Size(390, 844)),
      isFalse,
    );
    expect(
      ButlerlySize.isTabletViewport(const Size(932, 430)),
      isFalse,
    );
    expect(
      ButlerlySize.isTabletViewport(const Size(744, 1133)),
      isTrue,
    );
    expect(
      ButlerlySize.isTabletViewport(const Size(1133, 744)),
      isTrue,
    );
  });

  testWidgets('iPhone portrait keeps full-width phone content and footer', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(390, 844));

    expect(find.byType(NavigationRail), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('primary-phone-content'))).width,
      390,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('primary-phone-navigation')))
          .width,
      390,
    );
  });

  testWidgets(
    'iPhone landscape keeps full-width chrome and caps page content at 600',
    (tester) async {
      await _pumpAt(tester, const Size(932, 430));

      expect(find.byType(NavigationRail), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('primary-phone-body-surface')))
            .width,
        932,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('primary-phone-content')))
            .width,
        ButlerlySize.phoneContentMaxWidth,
      );
      expect(
        tester
            .getSize(find.byKey(const ValueKey('primary-phone-navigation')))
            .width,
        932,
      );
    },
  );

  for (final size in const [Size(744, 1133), Size(1133, 744)]) {
    testWidgets(
      'iPad mini uses tablet navigation at ${size.width}x${size.height}',
      (tester) async {
        await _pumpAt(tester, size);

        expect(find.byType(NavigationRail), findsOneWidget);
        expect(
          find.byKey(const ValueKey('primary-phone-navigation')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('primary-phone-content')),
          findsNothing,
        );
      },
    );
  }
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
  await tester.pumpAndSettle();
}
