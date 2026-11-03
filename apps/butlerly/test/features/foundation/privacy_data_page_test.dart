import 'dart:io';

import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/features/foundation/presentation/privacy_data_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart'
    as share_platform;

void main() {
  setUpAll(() async {
    await Future.wait([
      initializeDateFormatting('en'),
      initializeDateFormatting('es'),
      initializeDateFormatting('zh'),
    ]);
  });

  Widget app({
    share_plus.SharePlus? shareClient,
    Future<FileSaveLocation?> Function()? selectBackupLocation,
    Future<XFile?> Function()? selectRestoreFile,
    Future<XFile?> Function()? selectEvidenceRecoveryFile,
    Locale locale = const Locale('en'),
  }) => ProviderScope(
    child: MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: PrivacyDataPage(
        shareClient: shareClient,
        selectBackupLocation: selectBackupLocation,
        selectRestoreFile: selectRestoreFile,
        selectEvidenceRecoveryFile: selectEvidenceRecoveryFile,
      ),
    ),
  );

  testWidgets(
    'Privacy and data uses Cupertino symbols for native iOS actions',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.byIcon(CupertinoIcons.archivebox), findsOneWidget);
      expect(
        find.byIcon(CupertinoIcons.arrow_counterclockwise),
        findsOneWidget,
      );
      expect(find.byIcon(CupertinoIcons.arrow_down_doc), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.trash), findsOneWidget);
      expect(find.byIcon(Icons.backup_outlined), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'wide Privacy & Data shows real actions in a two-column dashboard',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      for (final key in const [
        'desktop-privacy-local-banner',
        'desktop-privacy-backup',
        'desktop-privacy-export',
        'desktop-privacy-management',
        'desktop-privacy-danger',
      ]) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      expect(find.text('Backup & Recovery'), findsOneWidget);
      expect(find.text('Data Export'), findsOneWidget);
      expect(find.text('Data Management'), findsOneWidget);
      expect(find.text('Danger Zone'), findsOneWidget);

      final backup = tester.getRect(
        find.byKey(const ValueKey('desktop-privacy-backup')),
      );
      final export = tester.getRect(
        find.byKey(const ValueKey('desktop-privacy-export')),
      );
      final management = tester.getRect(
        find.byKey(const ValueKey('desktop-privacy-management')),
      );
      expect(backup.left, lessThan(export.left));
      expect(backup.top, closeTo(export.top, 1));
      expect(management.top, greaterThan(backup.top));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact Privacy & Data preserves its original action list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-privacy-local-banner')),
      findsNothing,
    );
    expect(find.text('Local data controls'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile backup shares and then removes its temporary file', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-share-test-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    root.createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root);
    final platform = _SharePlatform();
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      app(shareClient: share_plus.SharePlus.custom(platform)),
    );
    await tester.pump();
    await tester.tap(find.text('Back up Butlerly'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'correct horse battery staple');
    await tester.enterText(fields.at(1), 'correct horse battery staple');
    await tester.tap(find.text('Create encrypted backup'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(platform.params, isNotNull);
    expect(platform.sawFileDuringShare, isTrue);
    debugDefaultTargetPlatformOverride = null;
    expect(gateway.discardedPath, isNotNull);
    expect(File(gateway.discardedPath!).existsSync(), isFalse);
  });

  testWidgets('mobile backup reports unavailable share outcome', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-share-unavailable-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root);
    final platform = _SharePlatform(
      status: share_plus.ShareResultStatus.unavailable,
    );
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      app(shareClient: share_plus.SharePlus.custom(platform)),
    );
    await tester.pumpAndSettle();
    await _completeBackupPasswordFlow(tester);

    debugDefaultTargetPlatformOverride = null;
    expect(
      find.text(
        'The encrypted backup was created, but the platform could not confirm whether it was shared or saved.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Backup could not be created.'), findsNothing);
    expect(gateway.discardedPath, isNotNull);
    expect(File(gateway.discardedPath!).existsSync(), isFalse);
  });

  testWidgets('mobile backup reports encryption failures separately', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-encryption-failure-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root)
      ..createFailure = const BackupEncryptionException();
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _completeBackupPasswordFlow(tester);

    debugDefaultTargetPlatformOverride = null;
    expect(
      find.text(
        'Backup encryption or verification failed. No backup was saved.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Backup could not be created because analysis rules failed validation. Choose Repair analysis rules and try again.',
      ),
      findsNothing,
    );
  });

  testWidgets('desktop backup reports publication recovery separately', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-publication-recovery-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root)
      ..createFailure = const BackupPublicationRecoveryException();
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(
      app(
        selectBackupLocation: () async =>
            FileSaveLocation(path.join(root.path, 'selected.butlerlybackup')),
      ),
    );
    await tester.pumpAndSettle();
    await _completeBackupPasswordFlow(tester);

    debugDefaultTargetPlatformOverride = null;
    expect(
      find.text(
        'Backup could not be finalized safely. Recovery is required; the destination file status is unknown. Open Backup recovery to continue.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Backup could not be saved to device storage.'),
      findsNothing,
    );
    expect(
      find.text(
        'Backup could not be created because analysis rules failed validation. Choose Repair analysis rules and try again.',
      ),
      findsNothing,
    );
  });

  testWidgets(
    'mobile backup reports native share exceptions when cleanup also fails',
    (tester) async {
      final root = Directory(
        path.join(
          Directory.systemTemp.path,
          'butlerly-share-exception-${DateTime.now().microsecondsSinceEpoch}',
        ),
      )..createSync(recursive: true);
      addTearDown(() async {
        await services.reset();
        if (root.existsSync()) root.deleteSync(recursive: true);
        debugDefaultTargetPlatformOverride = null;
      });
      final gateway = _ShareGateway(root)
        ..discardFailure = StateError('cleanup fixture');
      final platform = _SharePlatform(
        failure: PlatformException(code: 'share_fixture'),
      );
      services.registerSingleton<WorkspaceDataService>(
        WorkspaceDataService(gateway, refreshSystemData: () async {}),
      );
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      await tester.pumpWidget(
        app(shareClient: share_plus.SharePlus.custom(platform)),
      );
      await tester.pumpAndSettle();
      await _completeBackupPasswordFlow(tester);

      debugDefaultTargetPlatformOverride = null;
      expect(
        find.text(
          'The encrypted backup was created, but the share sheet could not be opened. No saved backup was confirmed.',
        ),
        findsOneWidget,
      );
      expect(find.text('Backup could not be created.'), findsNothing);
      expect(
        find.text(
          'Backup could not be created because analysis rules failed validation. Choose Repair analysis rules and try again.',
        ),
        findsNothing,
      );
      expect(gateway.discardedPath, isNotNull);
      expect(File(gateway.discardedPath!).existsSync(), isTrue);
    },
  );

  testWidgets('desktop backup reports destination selection failures', (
    tester,
  ) async {
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(
      app(selectBackupLocation: () async => throw StateError('fixture')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back up Butlerly'));
    await tester.pumpAndSettle();

    expect(find.text('Backup location could not be selected.'), findsOneWidget);
    expect(find.text('Backup could not be created.'), findsNothing);
    expect(
      find.text('Backup could not be saved to device storage.'),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('restore reports restore-file selection failures', (
    tester,
  ) async {
    addTearDown(() => services.reset());
    await tester.pumpWidget(
      app(selectRestoreFile: () async => throw StateError('fixture')),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Backup could not be restored. Failure stage: restore file selection. Error type: StateError. No restore was confirmed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('restore reports generic failures with diagnostics', (
    tester,
  ) async {
    final gateway = _ShareGateway(Directory.systemTemp);
    await services.reset();
    addTearDown(() async => services.reset());
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );

    await tester.pumpWidget(
      app(selectRestoreFile: () async => XFile('/unused/backup.butlerly')),
    );
    await tester.pumpAndSettle();
    await _openRestorePreview(tester);
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Backup could not be restored. Failure stage: restore activation. Error type: StateError. No restore was confirmed.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('restore mode captured'), findsNothing);
  });

  testWidgets('desktop backup reports destination storage failures', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-storage-failure-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root)
      ..createFailure = const BackupStorageException();
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(
      app(
        selectBackupLocation: () async =>
            FileSaveLocation(path.join(root.path, 'selected.butlerlybackup')),
      ),
    );
    await tester.pumpAndSettle();
    await _completeBackupPasswordFlow(tester);

    debugDefaultTargetPlatformOverride = null;
    expect(
      find.text('Backup could not be saved to device storage.'),
      findsOneWidget,
    );
    expect(find.text('Backup could not be created.'), findsNothing);
    expect(
      find.text(
        'Backup could not be created because analysis rules failed validation. Choose Repair analysis rules and try again.',
      ),
      findsNothing,
    );
  });

  testWidgets('mobile backup recommends repair only for rule validation', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-rule-validation-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root)
      ..createFailure = const BackupAnalysisRuleValidationException(
        'fixture',
        canRepair: true,
      );
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _completeBackupPasswordFlow(tester);

    debugDefaultTargetPlatformOverride = null;
    expect(
      find.text(
        'Backup could not be created because analysis rules failed validation. Choose Repair analysis rules and try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Backup could not be created.'), findsNothing);
  });

  testWidgets('mobile backup reports temporary-file creation failure', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-share-create-failure-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root)..createFailure = StateError('fixture');
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await _completeBackupPasswordFlow(tester);

    debugDefaultTargetPlatformOverride = null;
    expect(
      find.text(
        'Backup could not be created. Failure stage: temporary backup creation. Error type: StateError. Your financial data was not changed.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Backup could not be created because analysis rules failed validation. Choose Repair analysis rules and try again.',
      ),
      findsNothing,
    );
    expect(gateway.discardedPath, isNull);
  });

  testWidgets('desktop backup reports generic failures with diagnostics', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-desktop-backup-failure-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root)..createFailure = StateError('fixture');
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(
      app(
        selectBackupLocation: () async =>
            FileSaveLocation(path.join(root.path, 'selected.butlerly')),
      ),
    );
    await tester.pumpAndSettle();
    await _completeBackupPasswordFlow(tester);

    debugDefaultTargetPlatformOverride = null;
    expect(
      find.text(
        'Backup could not be created. Failure stage: portable backup creation. Error type: StateError. Your financial data was not changed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('analysis rule repair requires explicit approval', (
    tester,
  ) async {
    var repairs = 0;
    final gateway = _ShareGateway(Directory.systemTemp);
    addTearDown(() async => services.reset());
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(
        gateway,
        refreshSystemData: () async {},
        repairAnalysisRulesCallback: () async => repairs++,
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(repairs, 0);

    await tester.tap(find.text('Repair analysis rules'));
    await tester.pumpAndSettle();
    expect(repairs, 0);
    await tester.tap(
      find.widgetWithText(FilledButton, 'Repair analysis rules'),
    );
    await tester.pumpAndSettle();

    expect(repairs, 1);
    expect(find.text('Analysis rules repaired successfully.'), findsOneWidget);
  });

  testWidgets(
    'legacy unencrypted archive reaches validated restore preview without password',
    (tester) async {
      final gateway = _ShareGateway(Directory.systemTemp)..encrypted = false;
      await services.reset();
      addTearDown(() async => services.reset());
      services.registerSingleton<WorkspaceDataService>(
        WorkspaceDataService(gateway, refreshSystemData: () async {}),
      );

      await tester.pumpWidget(
        app(selectRestoreFile: () async => XFile('/unused/legacy.butlerly')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();

      expect(find.text('Unlock'), findsNothing);
      expect(gateway.inspectionCalls, 1);
      expect(gateway.inspectionPassword, isNull);
      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      expect(
        find.textContaining('older backup is not encrypted'),
        findsOneWidget,
      );

      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();
      expect(gateway.selectedRestoreMode, LocalRestoreMode.merge);
    },
  );

  testWidgets(
    'restore preview offers Merge and routes selection without Replace confirmation',
    (tester) async {
      final gateway = _ShareGateway(Directory.systemTemp);
      await services.reset();
      addTearDown(() async => services.reset());
      services.registerSingleton<WorkspaceDataService>(
        WorkspaceDataService(gateway, refreshSystemData: () async {}),
      );

      await tester.pumpWidget(
        app(selectRestoreFile: () async => XFile('/unused/backup.butlerly')),
      );
      await tester.pumpAndSettle();
      await _openRestorePreview(tester);

      expect(find.text('Merge'), findsOneWidget);
      expect(find.text('Replace'), findsOneWidget);
      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();

      expect(gateway.selectedRestoreMode, LocalRestoreMode.merge);
      expect(find.text('Replace current Butlerly data?'), findsNothing);
    },
  );

  testWidgets('restore preview accepts a supported unencrypted backup', (
    tester,
  ) async {
    final gateway = _ShareGateway(Directory.systemTemp)..encrypted = false;
    await services.reset();
    addTearDown(() async => services.reset());
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );

    await tester.pumpWidget(
      app(selectRestoreFile: () async => XFile('/unused/historical.butler')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore backup'));
    await tester.pumpAndSettle();

    expect(find.text('Merge'), findsOneWidget);
    expect(gateway.inspectPassword, isNull);
  });

  testWidgets('evidence recovery is an explicit file operation', (
    tester,
  ) async {
    final gateway = _ShareGateway(Directory.systemTemp)
      ..evidenceRecoveryResult = const EvidenceRecoveryResult(
        recoveredCount: 3,
        alreadyPresentCount: 1,
        unresolvedCount: 0,
      );
    await services.reset();
    addTearDown(() async => services.reset());
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );

    await tester.pumpWidget(
      app(
        selectEvidenceRecoveryFile: () async =>
            XFile('/unused/evidence-recovery.butlerly'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recover missing evidence'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'correct horse battery staple',
    );
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();

    expect(gateway.recoveredEvidencePassword, 'correct horse battery staple');
    expect(
      find.text('Evidence recovery finished: 3 restored, 1 already present.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Replace requires separate confirmation before invoking restore',
    (tester) async {
      final gateway = _ShareGateway(Directory.systemTemp);
      await services.reset();
      addTearDown(() async => services.reset());
      services.registerSingleton<WorkspaceDataService>(
        WorkspaceDataService(gateway, refreshSystemData: () async {}),
      );

      await tester.pumpWidget(
        app(selectRestoreFile: () async => XFile('/unused/backup.butlerly')),
      );
      await tester.pumpAndSettle();
      await _openRestorePreview(tester);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();

      expect(find.text('Replace current Butlerly data?'), findsOneWidget);
      expect(gateway.selectedRestoreMode, isNull);
      await tester.tap(
        find.widgetWithText(ButlerlyDestructiveButton, 'Replace'),
      );
      await tester.pumpAndSettle();
      expect(gateway.selectedRestoreMode, LocalRestoreMode.replace);
    },
  );

  testWidgets('restore preview formats its creation date for each locale', (
    tester,
  ) async {
    final date = DateTime(2026, 10, 31, 13, 45);
    for (final locale in const [
      Locale('en'),
      Locale('es'),
      Locale('zh', 'CN'),
    ]) {
      await tester.pumpWidget(app(locale: locale));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(PrivacyDataPage));
      final formatted = formatBackupInspectionDate(context, date);

      expect(formatted, contains('2026'));
      expect(formatted, isNot(contains('T13:45:00')));
    }
  });
}

Future<void> _openRestorePreview(WidgetTester tester) async {
  await tester.tap(find.text('Restore backup'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byType(TextField).last,
    'correct horse battery staple',
  );
  await tester.tap(find.text('Unlock'));
  await tester.pumpAndSettle();
}

Future<void> _completeBackupPasswordFlow(WidgetTester tester) async {
  await tester.tap(find.text('Back up Butlerly'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(2));
  await tester.enterText(fields.at(0), 'correct horse battery staple');
  await tester.enterText(fields.at(1), 'correct horse battery staple');
  await tester.tap(find.text('Create encrypted backup'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

final class _SharePlatform extends share_platform.SharePlatform {
  _SharePlatform({
    this.status = share_plus.ShareResultStatus.success,
    this.failure,
  });

  final share_plus.ShareResultStatus status;
  final Object? failure;
  share_plus.ShareParams? params;
  bool sawFileDuringShare = false;

  @override
  Future<share_plus.ShareResult> share(share_plus.ShareParams value) async {
    params = value;
    final file = value.files!.single;
    sawFileDuringShare = File(file.path).existsSync();
    if (failure != null) throw failure!;
    return share_plus.ShareResult('shared', status);
  }
}

final class _ShareGateway implements LocalDataGateway {
  _ShareGateway(this.root);

  final Directory root;
  String? discardedPath;
  Object? createFailure;
  Object? discardFailure;
  LocalRestoreMode? selectedRestoreMode;
  bool encrypted = true;
  int inspectionCalls = 0;
  String? inspectionPassword;
  String? inspectPassword;
  EvidenceRecoveryResult? evidenceRecoveryResult;
  String? recoveredEvidencePassword;

  @override
  Future<void> createPortableBackup(
    String destination, {
    required String password,
  }) async {
    if (createFailure != null) throw createFailure!;
  }

  @override
  Future<String> createTemporaryBackup(
    String fileName, {
    required String password,
  }) async {
    if (createFailure != null) throw createFailure!;
    final file = File(path.join(root.path, fileName));
    file.writeAsBytesSync(const [1, 2, 3]);
    return file.path;
  }

  @override
  Future<void> discardTemporaryBackup(String filePath) async {
    discardedPath = filePath;
    if (discardFailure != null) throw discardFailure!;
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  Future<bool> isEncryptedBackup(String filePath) async => encrypted;

  @override
  Future<BackupInspection> inspect(String filePath, {String? password}) async {
    inspectionCalls++;
    inspectionPassword = password;
    inspectPassword = password;
    return BackupInspection(
      createdAtUtc: DateTime.utc(2026, 11, 1),
      recordCount: 8,
      evidenceCount: 2,
      changes: const BackupChangeSummary(
        transactionsAdded: 1,
        transactionsChanged: 0,
        masterDataChanged: 0,
        deletedEntities: 0,
      ),
    );
  }

  @override
  Future<EvidenceRecoveryResult> recoverMissingEvidence(
    String filePath, {
    String? password,
  }) async {
    recoveredEvidencePassword = password;
    return evidenceRecoveryResult ??
        const EvidenceRecoveryResult(
          recoveredCount: 0,
          alreadyPresentCount: 0,
          unresolvedCount: 0,
        );
  }

  @override
  Future<LocalRestoreResult> restore(
    String filePath, {
    required LocalRestoreMode mode,
    String? password,
    required Future<void> Function() postActivationRefresh,
  }) async {
    selectedRestoreMode = mode;
    // Stop the fake before any refresh or real database write.
    throw StateError('restore mode captured for regression test');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
