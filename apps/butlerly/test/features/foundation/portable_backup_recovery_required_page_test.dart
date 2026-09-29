import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/portable_backup_recovery_required_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

  Widget app({required Future<XFile?> Function() selectLocation}) =>
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PortableBackupRecoveryRequiredPage(
          selectLocation: selectLocation,
        ),
      );

  testWidgets('shows recovery instructions and retries after reauthorization', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(selectLocation: () async => XFile('/selected/backup')),
    );

    expect(find.text('Backup recovery required'), findsOneWidget);
    expect(find.text('Select backup location'), findsOneWidget);
    expect(find.text('Keep recovery data'), findsOneWidget);

    gateway.fail = true;
    await tester.tap(find.text('Select backup location'));
    await tester.pumpAndSettle();
    expect(gateway.recoveries, 1);
    expect(
      find.textContaining('Recovery could not be completed'),
      findsOneWidget,
    );

    gateway.fail = false;
    await tester.tap(find.text('Select backup location'));
    await tester.pumpAndSettle();
    expect(gateway.recoveries, 2);
  });
}

final class _RecoveryGateway implements LocalDataGateway {
  bool fail = false;
  int recoveries = 0;

  @override
  Future<void> recoverPortableBackupPublication(String destination) async {
    recoveries++;
    if (fail) throw StateError('recovery remains required');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
