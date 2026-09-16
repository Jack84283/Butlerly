import 'package:butlerly/app/butlerly_app.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/shell/ipad/ipad_primary_shell.dart';
import 'package:butlerly/app/shell/iphone/iphone_primary_shell.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/legal_licenses_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => appRouter.go('/'));

  test('layout policy distinguishes phone, tablet, and desktop devices', () {
    expect(
      ButlerlyLayout.deviceClass(
        const Size(390, 844),
        platform: TargetPlatform.iOS,
      ),
      ButlerlyDeviceClass.phone,
    );
    expect(
      ButlerlyLayout.deviceClass(
        const Size(932, 430),
        platform: TargetPlatform.iOS,
      ),
      ButlerlyDeviceClass.phone,
    );
    expect(
      ButlerlyLayout.deviceClass(
        const Size(744, 1133),
        platform: TargetPlatform.iOS,
      ),
      ButlerlyDeviceClass.tablet,
    );
    expect(
      ButlerlyLayout.deviceClass(
        const Size(1133, 744),
        platform: TargetPlatform.iOS,
      ),
      ButlerlyDeviceClass.tablet,
    );
    expect(
      ButlerlyLayout.deviceClass(
        const Size(1200, 500),
        platform: TargetPlatform.macOS,
      ),
      ButlerlyDeviceClass.desktop,
    );
    expect(
      ButlerlyLayout.contentMaxWidth(
        const Size(932, 430),
        platform: TargetPlatform.iOS,
      ),
      ButlerlySize.phoneContentMaxWidth,
    );
    expect(
      ButlerlyLayout.contentMaxWidth(
        const Size(1133, 744),
        platform: TargetPlatform.iOS,
      ),
      ButlerlySize.pageContentMaxWidth,
    );
    expect(
      ButlerlyLayout.contentMaxWidth(
        const Size(1200, 500),
        platform: TargetPlatform.macOS,
      ),
      ButlerlySize.pageContentMaxWidth,
    );
  });

  testWidgets(
    'iPhone portrait keeps iPhone bottom navigation and normal page gutters',
    (tester) async {
      await _pumpAt(
        tester,
        const Size(390, 844),
        platform: TargetPlatform.iOS,
      );

      expect(find.byType(IPhonePrimaryShell), findsOneWidget);
      expect(find.byType(IPadPrimaryShell), findsNothing);
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
    },
  );

  testWidgets(
    'iPhone landscape keeps full-width Home chrome and bottom navigation',
    (tester) async {
      const size = Size(932, 430);
      await _pumpAt(tester, size, platform: TargetPlatform.iOS);

      expect(find.byType(IPhonePrimaryShell), findsOneWidget);
      expect(find.byType(IPadPrimaryShell), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('primary-phone-body-surface')))
            .width,
        size.width,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('home-header-surface'))).width,
        size.width,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,
        ButlerlySize.phoneContentMaxWidth,
      );
      final navigation = find.byKey(const ValueKey('primary-phone-navigation'));
      expect(tester.getSize(navigation).width, size.width);
      expect(tester.getRect(navigation).bottom, size.height);
    },
  );

  testWidgets(
    'landscape Search keeps a full-width header and the phone readable body',
    (tester) async {
      await _pumpAt(
        tester,
        const Size(932, 430),
        platform: TargetPlatform.iOS,
      );

      appRouter.go('/search');
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsNothing);
      expect(
        find.byKey(const ValueKey('primary-phone-navigation')),
        findsNothing,
      );
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

  testWidgets(
    'landscape Import/Export keeps a full-width header and phone body width',
    (tester) async {
      await _pumpAt(
        tester,
        const Size(932, 430),
        platform: TargetPlatform.iOS,
      );

      appRouter.go('/import-export');
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsNothing);
      expect(
        find.byKey(const ValueKey('primary-phone-navigation')),
        findsNothing,
      );
      expect(tester.getSize(find.byType(AppBar)).width, 932);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('import-export-content')))
            .width,
        ButlerlySize.phoneContentMaxWidth,
      );
    },
  );

  testWidgets(
    'focused responsive body keeps AppBar full-width and caps phone content',
    (tester) async {
      await _pumpResponsiveBodyAt(
        tester,
        const Size(932, 430),
        platform: TargetPlatform.iOS,
      );

      expect(tester.getSize(find.byType(AppBar)).width, 932);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('focused-page-content')))
            .width,
        ButlerlySize.phoneContentMaxWidth,
      );
    },
  );

  testWidgets('focused responsive body keeps the iPad readable width', (
    tester,
  ) async {
    await _pumpResponsiveBodyAt(
      tester,
      const Size(1133, 744),
      platform: TargetPlatform.iOS,
    );

    expect(tester.getSize(find.byType(AppBar)).width, 1133);
    expect(
      tester.getSize(find.byKey(const ValueKey('focused-page-content'))).width,
      ButlerlySize.pageContentMaxWidth,
    );
  });

  for (final size in const [Size(744, 1133), Size(1133, 744)]) {
    testWidgets(
      'iPad uses bottom navigation at ${size.width}x${size.height}',
      (tester) async {
        await _pumpAt(tester, size, platform: TargetPlatform.iOS);

        expect(find.byType(IPadPrimaryShell), findsOneWidget);
        expect(find.byType(IPhonePrimaryShell), findsNothing);
        expect(find.byType(NavigationRail), findsNothing);
        expect(
          find.byKey(const ValueKey('primary-phone-navigation')),
          findsNothing,
        );
        final navigation = find.byKey(
          const ValueKey('primary-ipad-navigation'),
        );
        expect(navigation, findsOneWidget);
        expect(tester.getSize(navigation).width, size.width);
        expect(tester.getRect(navigation).bottom, size.height);
      },
    );
  }

  testWidgets('iPad landscape keeps the tablet readable body', (tester) async {
    await _pumpAt(
      tester,
      const Size(1133, 744),
      platform: TargetPlatform.iOS,
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,
      ButlerlySize.pageContentMaxWidth,
    );
  });

  testWidgets('desktop uses the isolated desktop shell', (tester) async {
    await _pumpAt(
      tester,
      const Size(1200, 500),
      platform: TargetPlatform.macOS,
    );

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(
      find.byKey(const ValueKey('primary-desktop-navigation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('primary-phone-navigation')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('primary-ipad-navigation')),
      findsNothing,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-page-content'))).width,
      ButlerlySize.pageContentMaxWidth,
    );
  });

  testWidgets(
    'landscape Legal document keeps full-width AppBar and capped content',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(932, 430);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: LegalDocumentPage(
            document: LegalDocument(
              'termsOfUse',
              'assets/legal/terms_of_use.txt',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.getSize(find.byType(AppBar)).width, 932);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('legal-document-content')))
            .width,
        ButlerlySize.phoneContentMaxWidth,
      );
    },
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  required TargetPlatform platform,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const ProviderScope(child: ButlerlyApp()));
  await tester.pumpAndSettle();
}

Future<void> _pumpResponsiveBodyAt(
  WidgetTester tester,
  Size size, {
  required TargetPlatform platform,
}) async {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Focused page')),
        body: const ButlerlyResponsiveBody(
          contentKey: ValueKey('focused-page-content'),
          child: SizedBox.expand(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
