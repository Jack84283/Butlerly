import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/features/desktop/presentation/desktop_home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home breakdown header actions align to the right edge', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const Scaffold(body: DesktopHomePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final trendCard = find.byKey(const ValueKey('desktop-home-trend-card'));
    final categoryCard = find.byKey(
      const ValueKey('desktop-home-category-card'),
    );
    final month = find.byKey(const ValueKey('desktop-home-trend-months'));
    final viewAll = find.byKey(
      const ValueKey('desktop-home-category-view-all'),
    );
    expect(trendCard, findsOneWidget);
    expect(categoryCard, findsOneWidget);
    expect(month, findsOneWidget);
    expect(viewAll, findsOneWidget);

    expect(
      tester.widget<DropdownButton<int>>(month).alignment,
      AlignmentDirectional.centerEnd,
    );
    expect(
      tester.widget<TextButton>(viewAll).style?.alignment,
      Alignment.centerRight,
    );

    final trendRight = tester.getRect(trendCard).right;
    final categoryRight = tester.getRect(categoryCard).right;
    expect(trendRight - tester.getRect(month).right, inInclusiveRange(0, 30));
    expect(
      categoryRight - tester.getRect(viewAll).right,
      inInclusiveRange(0, 30),
    );
    expect(tester.takeException(), isNull);
  });
}
