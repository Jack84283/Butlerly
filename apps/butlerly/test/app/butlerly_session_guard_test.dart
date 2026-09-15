import 'dart:ui' as ui;

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
    var elapsed = Duration.zero;
    final router = _guardTestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_guardedApp(router, () => elapsed));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/work');

    elapsed = const Duration(minutes: 5);
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/launch');
    expect(find.byKey(const ValueKey('test-launch')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('pointer activity restarts the inactivity timeout', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    final router = _guardTestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_guardedApp(router, () => elapsed));
    await tester.pump();

    elapsed = const Duration(minutes: 4);
    await tester.pump(const Duration(minutes: 4));
    await tester.tap(find.byKey(const ValueKey('activity-target')));
    await tester.pump();

    elapsed = const Duration(minutes: 8, seconds: 59);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(router.routeInformationProvider.value.uri.path, '/work');

    elapsed = const Duration(minutes: 9);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/launch');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('software text editing restarts the inactivity timeout', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    final router = _guardTestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_guardedApp(router, () => elapsed));
    await tester.pump();

    elapsed = const Duration(minutes: 4, seconds: 50);
    await tester.pump(const Duration(minutes: 4, seconds: 50));
    await tester.tap(find.byKey(const ValueKey('activity-text-input')));
    await tester.pump();

    elapsed = const Duration(minutes: 9, seconds: 40);
    await tester.pump(const Duration(minutes: 4, seconds: 50));
    await tester.enterText(
      find.byKey(const ValueKey('activity-text-input')),
      'still editing',
    );
    await tester.pump();

    elapsed = const Duration(minutes: 14, seconds: 39);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(router.routeInformationProvider.value.uri.path, '/work');

    elapsed = const Duration(minutes: 14, seconds: 40);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/launch');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('accessibility focus semantics restart inactivity timeout', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    final router = _guardTestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_guardedApp(router, () => elapsed));
    await tester.pump();

    elapsed = const Duration(minutes: 4, seconds: 50);
    await tester.pump(const Duration(minutes: 4, seconds: 50));
    final node = tester.getSemantics(
      find.byKey(const ValueKey('activity-target')),
    );
    tester.binding.platformDispatcher.onSemanticsActionEvent?.call(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.didGainAccessibilityFocus,
        viewId: tester.view.viewId,
        nodeId: node.id,
      ),
    );
    await tester.pump();

    elapsed = const Duration(minutes: 9, seconds: 49);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(router.routeInformationProvider.value.uri.path, '/work');

    elapsed = const Duration(minutes: 9, seconds: 50);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/launch');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('changing an injected elapsed source preserves idle duration', (
    tester,
  ) async {
    var firstClock = Duration.zero;
    var secondClock = const Duration(hours: 2);
    final router = _guardTestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(_guardedApp(router, () => firstClock));
    await tester.pump();

    firstClock = const Duration(minutes: 4);
    await tester.pump(const Duration(minutes: 4));
    await tester.pumpWidget(_guardedApp(router, () => secondClock));
    await tester.pump();

    secondClock += const Duration(seconds: 59);
    await tester.pump(const Duration(seconds: 59));
    expect(router.routeInformationProvider.value.uri.path, '/work');

    secondClock += const Duration(seconds: 1);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/launch');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Android inactivity closes the activity after selecting launch', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    var exits = 0;
    final router = _guardTestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _guardedApp(
        router,
        () => elapsed,
        targetPlatform: TargetPlatform.android,
        onPlatformExit: () async {
          exits += 1;
        },
      ),
    );
    await tester.pump();

    elapsed = const Duration(minutes: 5);
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/launch');
    expect(exits, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('iOS uses fresh-launch reset without unsupported forced exit', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    var exits = 0;
    final router = _guardTestRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _guardedApp(
        router,
        () => elapsed,
        targetPlatform: TargetPlatform.iOS,
        onPlatformExit: () async {
          exits += 1;
        },
      ),
    );
    await tester.pump();

    elapsed = const Duration(minutes: 5);
    await tester.pump(const Duration(minutes: 5));
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/launch');
    expect(exits, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('short background interval preserves the current route', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    var wall = DateTime.utc(2026, 9, 15, 12);
    final router = _guardTestRouter();
    addTearDown(router.dispose);
    addTearDown(() => _restoreResumed(tester));

    await tester.pumpWidget(
      _guardedApp(router, () => elapsed, wallNow: () => wall),
    );
    await tester.pump();

    _sendToBackground(tester);
    elapsed = const Duration(minutes: 4);
    wall = wall.add(const Duration(minutes: 4));
    await tester.pump(const Duration(minutes: 4));
    _resumeFromBackground(tester);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/work');
    expect(find.text('Work'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('timely resume restarts the full inactivity timeout', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    var wall = DateTime.utc(2026, 9, 15, 12);
    final router = _guardTestRouter();
    addTearDown(router.dispose);
    addTearDown(() => _restoreResumed(tester));

    await tester.pumpWidget(
      _guardedApp(router, () => elapsed, wallNow: () => wall),
    );
    await tester.pump();

    elapsed = const Duration(minutes: 4, seconds: 50);
    await tester.pump(const Duration(minutes: 4, seconds: 50));
    _sendToBackground(tester);

    wall = wall.add(const Duration(seconds: 5));
    elapsed = const Duration(minutes: 4, seconds: 55);
    await tester.pump(const Duration(seconds: 5));
    _resumeFromBackground(tester);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/work');

    elapsed = const Duration(minutes: 9, seconds: 54);
    await tester.pump(const Duration(minutes: 4, seconds: 59));
    expect(router.routeInformationProvider.value.uri.path, '/work');

    elapsed = const Duration(minutes: 9, seconds: 55);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(router.routeInformationProvider.value.uri.path, '/launch');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('suspended background time expires even if monotonic clock pauses', (
    tester,
  ) async {
    final elapsed = Duration.zero;
    var wall = DateTime.utc(2026, 9, 15, 12);
    final router = _guardTestRouter();
    addTearDown(router.dispose);
    addTearDown(() => _restoreResumed(tester));

    await tester.pumpWidget(
      _guardedApp(router, () => elapsed, wallNow: () => wall),
    );
    await tester.pump();

    _sendToBackground(tester);
    wall = wall.add(const Duration(minutes: 6));
    await tester.pump(const Duration(minutes: 6));
    _resumeFromBackground(tester);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/launch');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('backward clock change while backgrounded fails closed', (
    tester,
  ) async {
    final elapsed = Duration.zero;
    var wall = DateTime.utc(2026, 9, 15, 12);
    final router = _guardTestRouter();
    addTearDown(router.dispose);
    addTearDown(() => _restoreResumed(tester));

    await tester.pumpWidget(
      _guardedApp(router, () => elapsed, wallNow: () => wall),
    );
    await tester.pump();

    _sendToBackground(tester);
    wall = wall.subtract(const Duration(minutes: 1));
    _resumeFromBackground(tester);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/launch');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Android resume after timeout launches without re-closing', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    var wall = DateTime.utc(2026, 9, 15, 12);
    var exits = 0;
    final router = _guardTestRouter();
    addTearDown(router.dispose);
    addTearDown(() => _restoreResumed(tester));

    await tester.pumpWidget(
      _guardedApp(
        router,
        () => elapsed,
        wallNow: () => wall,
        targetPlatform: TargetPlatform.android,
        onPlatformExit: () async {
          exits += 1;
        },
      ),
    );
    await tester.pump();

    _sendToBackground(tester);
    elapsed = const Duration(minutes: 6);
    wall = wall.add(const Duration(minutes: 6));
    await tester.pump(const Duration(minutes: 6));
    _resumeFromBackground(tester);
    await tester.pump();

    expect(router.routeInformationProvider.value.uri.path, '/launch');
    expect(find.byKey(const ValueKey('test-launch')), findsOneWidget);
    expect(exits, 0);
    await tester.pumpWidget(const SizedBox.shrink());
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
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

void _sendToBackground(WidgetTester tester) {
  final binding = tester.binding;
  final state = binding.lifecycleState;
  if (state == null || state == AppLifecycleState.detached) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
  if (binding.lifecycleState == AppLifecycleState.resumed) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState == AppLifecycleState.inactive) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }
}

void _resumeFromBackground(WidgetTester tester) {
  final binding = tester.binding;
  if (binding.lifecycleState == AppLifecycleState.paused) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (binding.lifecycleState == AppLifecycleState.hidden) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (binding.lifecycleState == AppLifecycleState.inactive ||
      binding.lifecycleState == AppLifecycleState.detached) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

void _restoreResumed(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.resumed ||
      tester.binding.lifecycleState == null) {
    return;
  }
  _resumeFromBackground(tester);
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                key: const ValueKey('activity-target'),
                onPressed: () {},
                child: const Text('Work'),
              ),
              const SizedBox(
                width: 220,
                child: TextField(
                  key: ValueKey('activity-text-input'),
                ),
              ),
            ],
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

Widget _guardedApp(
  GoRouter router,
  ButlerlyElapsedNow elapsedNow, {
  ButlerlyWallNow wallNow = DateTime.now,
  TargetPlatform targetPlatform = TargetPlatform.iOS,
  ButlerlyPlatformExit? onPlatformExit,
}) => MaterialApp.router(
  routerConfig: router,
  builder: (_, child) => ButlerlySessionGuard(
    router: router,
    elapsedNow: elapsedNow,
    wallNow: wallNow,
    targetPlatform: targetPlatform,
    onPlatformExit: onPlatformExit,
    child: child ?? const SizedBox.shrink(),
  ),
);
