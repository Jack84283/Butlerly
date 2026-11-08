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

  for (final (width, locale, dark) in <(double, Locale, bool)>[
    (320, const Locale('en'), false),
    (390, const Locale('en'), false),
    (430, const Locale('en'), false),
    (390, const Locale('zh'), false),
    (390, const Locale('es'), false),
    (390, const Locale('en'), true),
  ]) {
    testWidgets(
      'device Home brand row and subtitle at $width $locale (dark: $dark)',
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
            theme: dark ? AppTheme.dark : AppTheme.light,
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

        // Test the rendered visual centers, not merely membership of a Row.
        // The old +6/-6 transforms made the buttons appear misaligned even
        // though their parent had crossAxisAlignment.center.
        expect(
          find.byKey(const ValueKey('home-month-vertical-offset')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('home-help-vertical-offset')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('home-brand-title-optical-adjustment')),
          findsNothing,
        );

        final brandRect = tester.getRect(brand);
        final monthRect = tester.getRect(month);
        final helpRect = tester.getRect(help);
        final iconRect = tester.getRect(
          find.descendant(of: brand, matching: find.byType(ButlerlyBrandIcon)),
        );
        final pillRect = tester.getRect(
          find.descendant(of: month, matching: find.byType(Ink)),
        );
        final helpCircleRect = tester.getRect(
          find.byKey(const ValueKey('page-context-help-visual')),
        );
        expect(brandRect.right, lessThan(monthRect.left));
        expect(monthRect.right, lessThanOrEqualTo(helpRect.left));
        expect(helpRect.right, lessThanOrEqualTo(width));
        for (final actualCenter in [
          brandRect.center.dy,
          monthRect.center.dy,
          iconRect.center.dy,
          pillRect.center.dy,
          helpCircleRect.center.dy,
        ]) {
          expect(
            actualCenter,
            closeTo(helpRect.center.dy, 1.1),
            reason: 'Header visuals must share a vertical center',
          );
        }

        final tagline = find.byKey(const ValueKey('home-brand-tagline'));
        final taglineRect = tester.getRect(tagline);
        final topRowRect = tester.getRect(
          find.byKey(const ValueKey('home-brand-month-help-row')),
        );
        // No layout spacer remains between the header row and tagline.
        expect(taglineRect.top, closeTo(topRowRect.bottom, 0.1));
        expect(taglineRect.top, greaterThanOrEqualTo(brandRect.bottom - 0.5));
        final taglineColor = tester.widget<Text>(tagline).style!.color!;
        expect(
          taglineColor,
          dark ? const Color(0xFFFFE3A3) : const Color(0xFF784B0B),
        );
        expect(
          taglineColor.computeLuminance(),
          dark
              ? greaterThan(const Color(0xFFECC778).computeLuminance())
              : lessThan(const Color(0xFF9B6410).computeLuminance()),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
