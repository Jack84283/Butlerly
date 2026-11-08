import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Rules is the approved visual reference for all three Add/Help headers.
  // Test both layout modes and themes so device defaults cannot change the
  // 32px filled Add control or the 12px visible-circle gap.
  for (final path in ['/rules', '/master-data', '/payment-settlements']) {
    for (final width in [390.0, 1400.0]) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        testWidgets('Header Add/Help at $path, $width, $brightness', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final router = GoRouter(
            initialLocation: path,
            routes: [
              GoRoute(
                path: path,
                builder: (context, state) => Scaffold(
                  body: ButlerlyPage(
                    title: path,
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
              theme: ThemeData(useMaterial3: true, brightness: brightness),
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

          final addButton = tester.widget<IconButton>(add);
          expect(tester.getSize(add), const Size.square(32));
          expect(
            addButton.style?.fixedSize?.resolve({}),
            const Size.square(32),
          );
          expect(addButton.style?.padding?.resolve({}), EdgeInsets.zero);
          expect(
            addButton.style?.iconSize?.resolve({}),
            ButlerlySize.standardIcon,
          );
          expect(
            addButton.style?.shape?.resolve({}),
            isA<CircleBorder>(),
          );

          final addRect = tester.getRect(add);
          final helpRect = tester.getRect(help);
          expect(addRect.center.dy, closeTo(helpRect.center.dy, 1.1));
          expect(
            helpRect.left - addRect.right,
            closeTo(ButlerlySpacing.small, 0.5),
            reason: 'Rules, Master Data and Settlements must all use 12px',
          );
          expect(helpRect.left, greaterThan(addRect.center.dx));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  for (final width in [390.0, 1400.0]) {
    testWidgets('Custom header: Help last, 12px gap at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            appBar: AppBar(
              actions: [
                IconButton(
                  key: const ValueKey('test-custom-header-action'),
                  tooltip: 'Edit',
                  onPressed: () {},
                  icon: const Icon(Icons.edit_outlined),
                ),
                const ButlerlyContextHelpButton(articleId: 'ch-5'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final action = tester.getRect(
        find.byKey(const ValueKey('test-custom-header-action')),
      );
      final help = tester.getRect(
        find.byKey(const ValueKey('page-context-help')),
      );
      expect(help.left - action.right, closeTo(ButlerlySpacing.small, 0.5));
      expect(help.center.dx, greaterThan(action.center.dx));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Shared header: Help last, 12px gap at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final router = GoRouter(
        initialLocation: '/payment-settlements',
        routes: [
          GoRoute(
            path: '/payment-settlements',
            builder: (_, _) => Scaffold(
              body: ButlerlyPage(
                title: 'Payment Settlements',
                actions: [
                  IconButton(
                    key: const ValueKey('test-page-header-action'),
                    tooltip: 'Edit',
                    onPressed: () {},
                    icon: const Icon(Icons.edit_outlined),
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

      final action = tester.getRect(
        find.byKey(const ValueKey('test-page-header-action')),
      );
      final help = tester.getRect(
        find.byKey(const ValueKey('page-context-help')),
      );
      expect(help.left - action.right, closeTo(ButlerlySpacing.small, 0.5));
      expect(help.center.dx, greaterThan(action.center.dx));
      expect(tester.takeException(), isNull);
    });
  }
}
