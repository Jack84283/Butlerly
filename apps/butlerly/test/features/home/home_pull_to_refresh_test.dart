import 'package:butlerly/app/theme/app_theme.dart';
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

  testWidgets('Home uses native sliver pull-to-refresh on iOS', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const _TestApp());
    await tester.pumpAndSettle();

    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    final refreshControls = scrollView.slivers
        .whereType<CupertinoSliverRefreshControl>()
        .toList();
    expect(refreshControls, hasLength(1));
    final refreshControl = refreshControls.single;
    expect(
      refreshControl.key,
      const ValueKey('home-cupertino-refresh-control'),
    );
    expect(refreshControl.onRefresh, isNotNull);
    expect(find.byKey(const ValueKey('home-refresh-indicator')), findsNothing);

    final headerIndex = scrollView.slivers.indexWhere(
      (sliver) => sliver is SliverPersistentHeader,
    );
    final refreshIndex = scrollView.slivers.indexWhere(
      (sliver) => sliver is CupertinoSliverRefreshControl,
    );
    expect(refreshIndex, greaterThan(headerIndex));

    expect(scrollView.physics, isA<BouncingScrollPhysics>());
    expect(
      (scrollView.physics! as BouncingScrollPhysics).parent,
      isA<AlwaysScrollableScrollPhysics>(),
    );
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
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
