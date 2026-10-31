import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/evidence_deletion_recovery_state.dart';
import 'package:butlerly/features/foundation/presentation/evidence_deletion_recovery_required_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EvidenceDeletionRecoveryState recoveryState;
  late int retries;
  late _RecoveryGateway gateway;

  setUp(() async {
    await services.reset();
    recoveryState = EvidenceDeletionRecoveryState();
    recoveryState.markRequired(StateError('staged evidence is unresolved'));
    retries = 0;
    gateway = _RecoveryGateway();
    services.registerSingleton<EvidenceDeletionRecoveryState>(recoveryState);
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(
        gateway,
        refreshSystemData: () async => gateway.events.add('system-data'),
      ),
    );
  });

  tearDown(() => services.reset());

  Widget app() => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: EvidenceDeletionRecoveryRequiredPage(
      retryRecovery: () async {
        retries++;
        throw StateError('still unresolved');
      },
      resetRecovery: () => services<WorkspaceDataService>().eraseAll(),
    ),
  );

  testWidgets('restart recovery remains visible and permits retry', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expect(find.text('Evidence deletion needs review'), findsOneWidget);
    expect(find.text('Export preserved evidence'), findsOneWidget);
    await tester.tap(find.text('Retry secure cleanup'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(find.text('Evidence deletion needs review'), findsOneWidget);
    expect(recoveryState.isRecoveryRequired, isTrue);
  });

  testWidgets('offers an explicit destructive reset after recovery fails', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Erase local data and start over'));
    await tester.pumpAndSettle();
    expect(find.text('Erase local Butlerly data?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gateway.eraseCalls, 0);
    expect(recoveryState.isRecoveryRequired, isTrue);

    await tester.tap(find.text('Erase local data and start over'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase and restart'));
    await tester.pumpAndSettle();
    expect(gateway.eraseCalls, 1);
    expect(gateway.events, ['erase', 'system-data']);
    expect(recoveryState.isRecoveryRequired, isFalse);
  });
}

final class _RecoveryGateway implements LocalDataGateway {
  final events = <String>[];
  int eraseCalls = 0;

  @override
  bool get hasRecoverySafetyCopy => false;

  @override
  Future<void> eraseAll() async {
    eraseCalls++;
    events.add('erase');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
