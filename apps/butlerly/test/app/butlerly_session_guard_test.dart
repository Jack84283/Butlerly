import 'package:butlerly/app/session/butlerly_session_guard.dart';
import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/features/foundation/presentation/butlerly_launch_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('session timing is centralized at five minutes and five seconds', () {
    expect(ButlerlySessionConfig.inactivityTimeout, const Duration(minutes: 5));
    expect(ButlerlySessionConfig.launchDuration, const Duration(seconds: 5));
  });

  testWidgets('foreground inactivity resets the UI session to launch', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 15, 12);
    final router = _guardTestRouter();
    addTearDown(router.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    await tester.pumpWidget(_guardedApp(router, () => now));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/work');

    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/launch');
    expect(find.byKey(const ValueKey('test-launch')), findsOneWidget);
  });

  testWidgets('pointer activity restarts the inactivity timeout', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 15, 12);
    final router = _guardTestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_guardedApp(router, () => now));
    await tester.pump();

    now = now.add(const Duration(minutes: 4));
    await tester.pump(const Duration(minutes: 4));
    await tester.tap(find.byKey(const ValueKey('activity-target')));
    await tester.pump();

    now = now.add(const Duration(minutes: 4, seconds: 59));
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(router.routeInformationProvider.value.uri.path, '/work');

    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/launch');
  });

  testWidgets('short background interval preserves the current route', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 15, 12);
    final router = _guardTestRouter();
    addTearDown(router.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    await tester.pumpWidget(_guardedApp(router, () => now));
    await tester.pump();

    await tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 4));
    await tester.pump(const Duration(minutes: 4));
    await tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/work');
    expect(find.text('Work'), findsOneWidget);
  });

  testWidgets('resume after timeout starts a fresh launch flow', (tester) async {
    var now = DateTime(2026, 9, 15, 12);
    final router = _guardTestRouter();
    addTearDown(router.dispose);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    await tester.pumpWidget(_guardedApp(router, () => now));
    await tester.pump();

    await tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(minutes: 6));
    await tester.pump(const Duration(minutes: 6));
    await tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/launch');
    expect(find.byKey(const ValueKey('test-launch')), findsOneWidget);
  });

  testWidgets('Butlerly launch surface remains for five seconds then opens Home', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/launch',
      routes: [
        GoRoute(
          path: '/launch',
          builder: (_, _) => const ButlerlyLaunchPage(),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('Home')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('butlerly-launch-screen')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 4, milliseconds: 999));
    expect(
      find.byKey(const ValueKey('butlerly-launch-screen')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Home'), findsOneWidget);
  });
}

GoRouter _guardTestRouter() => GoRouter(
  initialLocation: '/work',
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => const Scaffold(body: Text('Home')),
    ),
    GoRoute(
      path: '/work',
      builder: (_, _) => Scaffold(
        body: Center(
          child: TextButton(
            key: const ValueKey('activity-target'),
            onPressed: () {},
            child: const Text('Work'),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/launch',
      builder: (_, _) => const Scaffold(
        key: ValueKey('test-launch'),
        body: Text('Launch'),
      ),
    ),
  ],
);

Widget _guardedApp(GoRouter router, DateTime Function() now) =>
    MaterialApp.router(
      routerConfig: router,
      builder: (_, child) => ButlerlySessionGuard(
        router: router,
        now: now,
        child: child ?? const SizedBox.shrink(),
      ),
    );
