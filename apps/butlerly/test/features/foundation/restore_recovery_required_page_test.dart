import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/restore_recovery_required_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _RecoveryGateway gateway;
  setUp(() async {
    await services.reset();
    gateway = _RecoveryGateway();
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
  });
  tearDown(() => services.reset());

  Widget app() => const ProviderScope(
    child: MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: RestoreRecoveryRequiredPage(),
    ),
  );

  testWidgets('failed recovery remains visible and permits retry', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Recover Butlerly'));
    await tester.pumpAndSettle();
    expect(gateway.recoveries, 1);
    expect(find.textContaining('Recovery is still required'), findsOneWidget);
    await tester.tap(find.text('Recover Butlerly'));
    await tester.pumpAndSettle();
    expect(gateway.recoveries, 2);
  });

  testWidgets(
    'reset requires explicit confirmation and cancellation is inert',
    (tester) async {
      gateway.safetyCopy = false;
      await tester.pumpWidget(app());
      expect(find.text('Recover Butlerly'), findsNothing);
      await tester.tap(find.text('Erase local data and start over'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(gateway.resets, 0);
      await tester.tap(find.text('Erase local data and start over'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Erase and restart'));
      await tester.pumpAndSettle();
      expect(gateway.resets, 1);
    },
  );
}

class _RecoveryGateway implements LocalDataGateway {
  bool safetyCopy = true;
  int recoveries = 0;
  int resets = 0;
  @override
  bool get hasRecoverySafetyCopy => safetyCopy;
  @override
  Future<void> recoverControlledState({
    required Future<void> Function() postActivationRefresh,
  }) async {
    recoveries++;
    throw StateError('recovery remains required');
  }

  @override
  Future<void> resetControlledRecovery({
    required Future<void> Function() postResetRefresh,
  }) async {
    resets++;
    await postResetRefresh();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
