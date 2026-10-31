import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/evidence_deletion_recovery_state.dart';
import 'package:butlerly/features/foundation/presentation/evidence_deletion_recovery_required_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late EvidenceDeletionRecoveryState recoveryState;
  late int retries;
  late int resets;

  setUp(() async {
    await services.reset();
    recoveryState = EvidenceDeletionRecoveryState();
    recoveryState.markRequired(StateError('staged evidence is unresolved'));
    retries = 0;
    resets = 0;
    services.registerSingleton<EvidenceDeletionRecoveryState>(recoveryState);
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
      resetRecovery: () async {
        resets++;
      },
    ),
  );

  testWidgets('restart recovery remains visible and permits retry', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    expect(find.text('Evidence deletion needs review'), findsOneWidget);
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
    expect(resets, 0);
    expect(recoveryState.isRecoveryRequired, isTrue);

    await tester.tap(find.text('Erase local data and start over'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase and restart'));
    await tester.pumpAndSettle();
    expect(resets, 1);
    expect(recoveryState.isRecoveryRequired, isFalse);
  });
}
