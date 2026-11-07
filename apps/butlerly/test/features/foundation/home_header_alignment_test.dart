import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_brand_icon.dart';
import 'package:butlerly/features/foundation/presentation/home_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (width, locale) in <(double, Locale)>[
    (320, const Locale('en')),
    (390, const Locale('en')),
    (430, const Locale('en')),
    (390, const Locale('zh')),
    (390, const Locale('es')),
  ]) {
    testWidgets(
      'device Home keeps brand, month and Help on one row at $width $locale',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const HomePage()),
            GoRoute(
              path: '/help',
              builder: (_, _) => const Scaffold(body: Text('Help')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            locale: locale,
            theme: AppTheme.light,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('home-brand-month-help-row')),
          findsOneWidget,
        );
        final brand = find.byType(ButlerlyBrandTitle);
        final month = find.byKey(const Key('home-month-selector'));
        final help = find.byKey(const ValueKey('page-context-help'));
        expect(brand, findsOneWidget);
        expect(month, findsOneWidget);
        expect(help, findsOneWidget);

        final monthShift = tester.widget<Transform>(
          find.byKey(const ValueKey('home-month-vertical-offset')),
        );
        final helpShift = tester.widget<Transform>(
          find.byKey(const ValueKey('home-help-vertical-offset')),
        );
        expect(monthShift.transform.getTranslation().y, 6);
        expect(helpShift.transform.getTranslation().y, -6);

        final brandRect = tester.getRect(brand);
        final monthRect = tester.getRect(month);
        final helpRect = tester.getRect(help);
        expect(brandRect.right, lessThan(monthRect.left));
        expect(monthRect.right, lessThanOrEqualTo(helpRect.left));
        expect((brandRect.center.dy - monthRect.center.dy).abs(), lessThan(12));
        expect((monthRect.center.dy - helpRect.center.dy).abs(), lessThan(12));
        expect(helpRect.right, lessThanOrEqualTo(width));

        final tagline = find.byKey(const ValueKey('home-brand-tagline'));
        expect(tester.getRect(tagline).top, greaterThan(brandRect.bottom));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
