import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    HomePage.debugCurrentDate = DateTime(2026, 9, 16, 15);
  });

  tearDown(() {
    HomePage.debugCurrentDate = null;
  });

  testWidgets(
    'Home keeps the pinned header above a real iOS pull refresh',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const _TestApp());
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(CustomScrollView);
      final scrollView = tester.widget<CustomScrollView>(scrollFinder);
      final headerIndex = scrollView.slivers.indexWhere(
        (sliver) => sliver is SliverPersistentHeader,
      );
      final refreshIndex = scrollView.slivers.indexWhere(
        (sliver) => sliver is CupertinoSliverRefreshControl,
      );
      expect(headerIndex, isNonNegative);
      expect(refreshIndex, isNonNegative);
      expect(headerIndex, lessThan(refreshIndex));
      expect(
        (scrollView.slivers[headerIndex] as SliverPersistentHeader).pinned,
        isTrue,
      );

      final refreshControl =
          scrollView.slivers[refreshIndex] as CupertinoSliverRefreshControl;
      expect(
        refreshControl.key,
        const ValueKey('home-cupertino-refresh-control'),
      );
      expect(refreshControl.onRefresh, isNotNull);
      expect(find.byKey(const ValueKey('home-refresh-indicator')), findsNothing);

      final colors = AppTheme.light.extension<ButlerlySemanticColors>()!;
      final canvas = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('home-page-canvas')),
      );
      final bodySurface = tester.widget<ColoredBox>(
        find.byKey(const ValueKey('home-page-content-surface')),
      );
      expect(canvas.color, colors.subtleSurface);
      expect(bodySurface.color, colors.background);
      expect(canvas.color, isNot(bodySurface.color));

      final bodyPadding = tester.widget<Padding>(
        find.byKey(const ValueKey('home-page-content-padding')),
      );
      expect(
        bodyPadding.padding,
        const EdgeInsets.fromLTRB(
          ButlerlySize.phoneGutter,
          ButlerlySpacing.small,
          ButlerlySize.phoneGutter,
          ButlerlySpacing.large,
        ),
      );

      final bodyFinder = find.byKey(const ValueKey('home-body-data'));
      final headerFinder = find.byKey(const ValueKey('home-header-surface'));
      final beforeRefresh = (tester.widget(bodyFinder) as FutureBuilder).future;
      final headerTopBefore = tester.getTopLeft(headerFinder).dy;

      await tester.drag(scrollFinder, const Offset(0, 320));
      await tester.pump();

      // The refresh is allowed to animate, but completed Home data must not be
      // replaced by the generic loading state while the new snapshot is swapped.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getTopLeft(headerFinder).dy, closeTo(headerTopBefore, 0.01));

      await tester.pumpAndSettle();

      final afterRefresh = (tester.widget(bodyFinder) as FutureBuilder).future;
      expect(identical(beforeRefresh, afterRefresh), isFalse);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getTopLeft(headerFinder).dy, closeTo(headerTopBefore, 0.01));

      expect(scrollView.physics, isA<BouncingScrollPhysics>());
      expect(
        (scrollView.physics! as BouncingScrollPhysics).parent,
        isA<AlwaysScrollableScrollPhysics>(),
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.light,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: const Scaffold(body: HomePage()),
  );
}
