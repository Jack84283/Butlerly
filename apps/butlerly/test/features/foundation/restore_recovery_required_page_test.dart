import 'dart:io';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/data/restore_recovery_state.dart';
import 'package:butlerly/core/database/local_database.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/logging/app_logger.dart';
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

  Widget app({Future<void> Function(String diagnostic)? copyDiagnostic}) =>
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: RestoreRecoveryRequiredPage(copyDiagnostic: copyDiagnostic),
        ),
      );

  testWidgets('shows and copies bounded recovery diagnostics', (tester) async {
    final root = Directory(
      '${Directory.current.path}/.butlerly-restore-recovery-diagnostic-'
      '${DateTime.now().microsecondsSinceEpoch}',
    )..createSync(recursive: true);
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final recoveryState = RestoreRecoveryState(
      LocalDataManager(
        LocalDatabase(logger: AppLogger()),
        localEvidenceDirectory: root,
      ),
    );
    recoveryState.setDiagnostic(
      const RestoreRecoveryDiagnostic(
        stageCode: 'restore_validation',
        errorCode: 'database',
      ),
    );
    services.registerSingleton<RestoreRecoveryStatus>(recoveryState);

    String? copiedDiagnostic;
    await tester.pumpWidget(
      app(copyDiagnostic: (value) async => copiedDiagnostic = value),
    );
    await tester.pump();

    expect(find.text('Failure stage: restore validation'), findsOneWidget);
    expect(find.text('Error category: database validation'), findsOneWidget);
    await tester.tap(find.text('Copy diagnostic'));
    await tester.pump();
    expect(
      copiedDiagnostic,
      'operation=restore\n'
      'stage_code=restore_validation\n'
      'error_code=database\n'
      'recovery_required=true',
    );
  });

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
