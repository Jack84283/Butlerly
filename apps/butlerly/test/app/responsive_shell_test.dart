import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appRouter.go('/'));

  test('window class and readable width use the shortest logical side', () {
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
    expect(
      ButlerlySize.pageContentMaxWidthFor(const Size(932, 430)),
      ButlerlySize.phoneContentMaxWidth,
    );
    expect(
      ButlerlySize.pageContentMaxWidthFor(const Size(1133, 744)),
      ButlerlySize.pageContentMaxWidth,
    );
  });

  testWidgets('iPhone portrait keeps phone navigation and normal page gutters', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(390, 844));

    expect(find.byType(NavigationRail), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,
      390 - ButlerlySize.phoneGutter * 2,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('primary-phone-navigation')))
          .width,
      390,
    );
  });

  testWidgets(
    'iPhone landscape keeps full-width Home chrome and caps body at 600',
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
        tester.getSize(find.byKey(const ValueKey('home-header-surface'))).width,
        932,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,
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

  testWidgets(
    'landscape Search keeps a full-width header and the same 600 point body',
    (tester) async {
      await _pumpAt(tester, const Size(932, 430));

      appRouter.go('/search');
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byKey(const ValueKey('primary-phone-navigation')), findsNothing);
      expect(tester.getSize(find.byType(AppBar)).width, 932);
      final content = tester.renderObject<RenderSliver>(
        find.byKey(const ValueKey('butlerly-page-content-sliver')),
      );
      expect(
        content.constraints.crossAxisExtent,
        ButlerlySize.phoneContentMaxWidth,
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
      },
    );
  }

  testWidgets('iPad mini landscape keeps the 760 point readable body', (
    tester,
  ) async {
    await _pumpAt(tester, const Size(1133, 744));

    expect(
      tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,
      ButlerlySize.pageContentMaxWidth,
    );
  });
}

Future<void> _pumpAt(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
  await tester.pumpAndSettle();
}
