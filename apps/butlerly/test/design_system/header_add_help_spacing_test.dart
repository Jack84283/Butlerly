import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final width in [390.0, 1400.0]) {
    testWidgets(
      'Page header Add is adjacent to Help at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final router = GoRouter(
          initialLocation: '/rules',
          routes: [
            GoRoute(
              path: '/rules',
              builder: (context, state) => Scaffold(
                body: ButlerlyPage(
                  title: 'Rules',
                  actions: [
                    ButlerlyHeaderAddButton(
                      buttonKey: const ValueKey('test-header-add'),
                      label: 'Add',
                      onPressed: () {},
                      closeToHelp: true,
                    ),
                  ],
                  children: const [SizedBox(height: 50)],
                ),
              ),
            ),
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

        final add = find.byKey(const ValueKey('test-header-add'));
        final help = find.byKey(const ValueKey('page-context-help-visual'));
        expect(add, findsOneWidget);
        expect(help, findsOneWidget);

        final addRect = tester.getRect(add);
        final helpRect = tester.getRect(help);
        expect(addRect.center.dy, closeTo(helpRect.center.dy, 1.1));
        expect(
          helpRect.left - addRect.right,
          closeTo(ButlerlySpacing.small, 0.5),
          reason: 'The visible Add/Help circles must use medium spacing',
        );
        expect(helpRect.left, greaterThan(addRect.center.dx));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
