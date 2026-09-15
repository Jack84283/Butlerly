import 'dart:async';

import 'package:butlerly/app/bootstrap.dart';
import 'package:butlerly/core/logging/app_logger.dart';
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

  testWidgets('startup failure is visible and retryable without a blank screen', (
    tester,
  ) async {
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
      ButlerlyStartupGate(logger: logger, initialize: initialize),
    );
    await tester.pump();
    await tester.pump();

    expect(attempts, 1);
    expect(
      find.byKey(const ValueKey('butlerly-startup-error')),
      findsOneWidget,
    );
    expect(
      find.text("Butlerly couldn't initialize local storage."),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('butlerly-startup-retry')));
    await tester.pump();

    expect(attempts, 2);
    expect(
      find.byKey(const ValueKey('butlerly-startup-error')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('butlerly-startup-progress')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
