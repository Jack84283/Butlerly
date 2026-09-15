import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/features/foundation/presentation/butlerly_launch_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets('launch countdown pauses while Butlerly is backgrounded', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 15, 12);
    final router = GoRouter(
      initialLocation: '/launch',
      routes: [
        GoRoute(
          path: '/launch',
          builder: (_, _) => ButlerlyLaunchPage(now: () => now),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();

    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    now = now.add(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(
      find.byKey(const ValueKey('butlerly-launch-screen')),
      findsOneWidget,
    );

    await tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    now = now.add(const Duration(seconds: 2, milliseconds: 999));
    await tester.pump(const Duration(seconds: 2, milliseconds: 999));
    expect(
      find.byKey(const ValueKey('butlerly-launch-screen')),
      findsOneWidget,
    );

    now = now.add(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Home'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
