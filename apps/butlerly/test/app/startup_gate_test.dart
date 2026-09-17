import 'dart:async';

import 'package:butlerly/app/bootstrap.dart';
import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/logging/app_logger.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final logger = AppLogger()..initialize();

  for (final size in const [Size(744, 1133), Size(1133, 744)]) {
    testWidgets(
      'startup paints immediately at iPad mini ${size.width}x${size.height}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final initialization = Completer<void>();
        await tester.pumpWidget(
          ButlerlyStartupGate(
            logger: logger,
            initialize: () => initialization.future,
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('butlerly-startup-screen')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('butlerly-startup-progress')),
          findsOneWidget,
        );
        expect(find.text('Butlerly'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('fatal startup failure is visible and retryable', (tester) async {
    var attempts = 0;
    final retryInitialization = Completer<void>();

    Future<void> initialize() {
      attempts += 1;
      if (attempts == 1) {
        return Future<void>.error(StateError('simulated startup failure'));
      }
      return retryInitialization.future;
    }

    await tester.pumpWidget(
      ButlerlyStartupGate(
        logger: logger,
        initialize: initialize,
        minimumLaunchDuration: Duration.zero,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(attempts, 1);
    expect(
      find.byKey(const ValueKey('butlerly-startup-error')),
      findsOneWidget,
    );
    expect(find.text('Page unavailable'), findsOneWidget);
    expect(find.text('Diagnostic: STARTUP-UNKNOWN'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('butlerly-startup-retry')));
    await tester.pump();

    expect(attempts, 2);
    expect(find.byKey(const ValueKey('butlerly-startup-error')), findsNothing);
    expect(
      find.byKey(const ValueKey('butlerly-startup-progress')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('classifies database migration failures without exposing details', () {
    final failure = classifyStartupFailure(
      'database initialization',
      const RepositoryException(
        RepositoryFailureCode.migration,
        'apply database migration',
      ),
    );

    expect(failure.code, 'DB-MIGRATION');
    expect(failure.phase, 'database initialization');
    expect(startupDiagnosticCode(failure), 'DB-MIGRATION');
    expect(failure.toString(), isNot(contains('apply database migration')));
  });

  test('classifies restore-state startup failures by phase', () {
    final failure = classifyStartupFailure(
      'restore recovery initialization',
      StateError('simulated recovery failure'),
    );

    expect(failure.code, 'RECOVERY-STATE');
    expect(startupDiagnosticCode(failure), 'RECOVERY-STATE');
  });

  test(
    'storage availability failure becomes a retryable storage error',
    () async {
      final database = _FailingLocalDatabase(
        logger,
        const RepositoryException(
          RepositoryFailureCode.unavailable,
          'open database',
        ),
      );

      await expectLater(
        initializeLocalDatabaseForStartup(database, logger),
        throwsA(isA<ButlerlyStorageUnavailableException>()),
      );
      expect(database.status, DatabaseStatus.unavailable);
    },
  );

  test('migration failure remains fatal and is not reclassified', () async {
    final database = _FailingLocalDatabase(
      logger,
      const RepositoryException(
        RepositoryFailureCode.migration,
        'apply database migration',
      ),
    );

    await expectLater(
      initializeLocalDatabaseForStartup(database, logger),
      throwsA(
        isA<RepositoryException>().having(
          (error) => error.code,
          'code',
          RepositoryFailureCode.migration,
        ),
      ),
    );
    expect(database.status, DatabaseStatus.notInitialized);
  });

  test('unexpected database exception remains fatal', () async {
    final database = _FailingLocalDatabase(
      logger,
      StateError('unexpected database failure'),
    );

    await expectLater(
      initializeLocalDatabaseForStartup(database, logger),
      throwsStateError,
    );
    expect(database.status, DatabaseStatus.notInitialized);
  });

  testWidgets('storage unavailable never falls through to the workspace', (
    tester,
  ) async {
    await tester.pumpWidget(
      ButlerlyStartupGate(
        logger: logger,
        initialize: () async =>
            throw const ButlerlyStorageUnavailableException(),
        minimumLaunchDuration: Duration.zero,
        readyBuilder: (_) =>
            const MaterialApp(home: Scaffold(body: Text('ready'))),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Local storage is unavailable'), findsOneWidget);
    expect(find.text('Diagnostic: DB-UNAVAILABLE'), findsOneWidget);
    expect(find.text('ready'), findsNothing);
  });

  testWidgets('classified migration failure shows only the safe code', (
    tester,
  ) async {
    const failure = ButlerlyStartupFailure(
      code: 'DB-MIGRATION',
      phase: 'database initialization',
      cause: RepositoryException(
        RepositoryFailureCode.migration,
        'apply database migration',
      ),
    );

    await tester.pumpWidget(
      ButlerlyStartupGate(
        logger: logger,
        initialize: () async => throw failure,
        minimumLaunchDuration: Duration.zero,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Page unavailable'), findsOneWidget);
    expect(find.text('Diagnostic: DB-MIGRATION'), findsOneWidget);
    expect(find.textContaining('apply database migration'), findsNothing);
  });

  testWidgets('cold startup uses one five-second launch window', (
    tester,
  ) async {
    var ready = false;

    await tester.pumpWidget(
      ButlerlyStartupGate(
        logger: logger,
        initialize: () async {},
        onReady: () => ready = true,
        readyBuilder: (_) =>
            const MaterialApp(home: Scaffold(body: Text('ready'))),
      ),
    );
    await tester.pump();

    await tester.pump(const Duration(seconds: 4, milliseconds: 999));
    expect(ready, isFalse);
    expect(find.text('ready'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(ready, isTrue);
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('cold startup countdown pauses while backgrounded', (
    tester,
  ) async {
    var elapsed = Duration.zero;
    var ready = false;
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );

    await tester.pumpWidget(
      ButlerlyStartupGate(
        logger: logger,
        initialize: () async {},
        launchElapsedNow: () => elapsed,
        onReady: () => ready = true,
        readyBuilder: (_) =>
            const MaterialApp(home: Scaffold(body: Text('ready'))),
      ),
    );
    await tester.pump();

    elapsed = const Duration(seconds: 2);
    await tester.pump(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    elapsed = const Duration(seconds: 12);
    await tester.pump(const Duration(seconds: 10));
    expect(ready, isFalse);
    expect(
      find.byKey(const ValueKey('butlerly-startup-screen')),
      findsOneWidget,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    elapsed = const Duration(seconds: 14, milliseconds: 999);
    await tester.pump(const Duration(seconds: 2, milliseconds: 999));
    expect(ready, isFalse);

    elapsed = const Duration(seconds: 15);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(ready, isTrue);
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('cold startup skips the second launch route after success', (
    tester,
  ) async {
    appRouter.go('/launch');
    addTearDown(() => appRouter.go('/'));

    await tester.pumpWidget(
      ButlerlyStartupGate(
        logger: logger,
        initialize: () async {},
        minimumLaunchDuration: Duration.zero,
        readyBuilder: (_) =>
            const MaterialApp(home: Scaffold(body: Text('ready'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(appRouter.routeInformationProvider.value.uri.path, '/');
    expect(find.text('ready'), findsOneWidget);
  });
}

final class _FailingLocalDatabase extends LocalDatabase {
  _FailingLocalDatabase(AppLogger logger, this.error) : super(logger: logger);

  final Object error;

  @override
  Future<void> initialize() async => throw error;
}
