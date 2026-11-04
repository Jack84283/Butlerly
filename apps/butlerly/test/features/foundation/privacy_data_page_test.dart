import 'dart:io';

import 'package:butlerly/core/di/service_locator.dart';
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
    Future<void> Function(String diagnostic)? copyDiagnostic,
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
        copyDiagnostic: copyDiagnostic,
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
    expect(find.text('Repair analysis rules'), findsNothing);
    expect(find.text('Recover missing evidence'), findsNothing);
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

  testWidgets('backup warning copy stays generic for rule warnings', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-warning-copy-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root)
      ..inspectionWarnings = const [
        BackupWarning(code: 'invalid_custom_analysis_rule', count: 1),
      ];
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(
      app(
        selectBackupLocation: () async =>
            FileSaveLocation(path.join(root.path, 'warning.butlerly')),
      ),
    );
    await tester.pumpAndSettle();
    await _completeBackupPasswordFlow(tester);

    debugDefaultTargetPlatformOverride = null;
    expect(
      find.text(
        'Encrypted backup created with warnings. Open Data Integrity Reports for details.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('optional files'), findsNothing);
  });

  testWidgets('restore warning copy stays generic for relationship warnings', (
    tester,
  ) async {
    final gateway = _ShareGateway(Directory.systemTemp)
      ..inspectionWarnings = const [
        BackupWarning(code: 'relationship_inconsistency', count: 1),
      ]
      ..successfulRestore = const LocalRestoreResult(
        mode: LocalRestoreMode.merge,
        restoredRows: 1,
        keptNewerLocalRows: 0,
        restoredEvidence: 0,
        warnings: [BackupWarning(code: 'relationship_inconsistency', count: 1)],
      );
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
      find.textContaining(
        'Restore completed with warnings. Open Data Integrity Reports for details.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Some content'), findsNothing);
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
        'Backup could not be restored. Failure stage: restore file selection. No restore was confirmed.',
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
        'Backup could not be restored. Failure stage: restore activation. No restore was confirmed.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('restore mode captured'), findsNothing);
    expect(
      find.byKey(const ValueKey('privacy-diagnostic-banner')),
      findsOneWidget,
    );
    final viewDetails = find.descendant(
      of: find.byKey(const ValueKey('privacy-diagnostic-banner')),
      matching: find.text('View details'),
    );
    await tester.ensureVisible(viewDetails);
    await tester.tap(viewDetails);
    await tester.pumpAndSettle();
    expect(find.text('Failure details'), findsOneWidget);
    expect(find.textContaining('Merge'), findsAtLeastNWidgets(1));
  });

  testWidgets('restore reports database validation failures distinctly', (
    tester,
  ) async {
    final gateway = _ShareGateway(Directory.systemTemp)
      ..restoreFailure = const RestoreFailureException(
        stage: 'staged database validation',
        errorCode: 'database',
      );
    await services.reset();
    addTearDown(() async => services.reset());
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );

    String? copiedDiagnostic;
    await tester.pumpWidget(
      app(
        selectRestoreFile: () async => XFile('/unused/backup.butlerly'),
        copyDiagnostic: (value) async => copiedDiagnostic = value,
      ),
    );
    await tester.pumpAndSettle();
    await _openRestorePreview(tester);
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    final viewDetails = find.descendant(
      of: find.byKey(const ValueKey('privacy-diagnostic-banner')),
      matching: find.text('View details'),
    );
    await tester.ensureVisible(viewDetails);
    await tester.tap(viewDetails);
    await tester.pumpAndSettle();
    expect(find.text('Failure stage: restore validation'), findsOneWidget);
    expect(find.text('Error category: database validation'), findsOneWidget);
    await tester.tap(find.text('Copy diagnostic'));
    await tester.pumpAndSettle();

    expect(
      copiedDiagnostic,
      'operation=restore\n'
      'stage_code=restore_validation\n'
      'error_code=database\n'
      'restore_mode=merge\n'
      'recovery_required=false',
    );
  });

  testWidgets('restore preview classifies database failures safely', (
    tester,
  ) async {
    final gateway = _ShareGateway(Directory.systemTemp)
      ..inspectionFailure = const BackupFailureException(
        stage: 'archive inspection',
        errorCode: 'database',
      );
    await services.reset();
    addTearDown(() async => services.reset());
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );

    String? copiedDiagnostic;
    await tester.pumpWidget(
      app(
        selectRestoreFile: () async => XFile('/unused/backup.butlerly'),
        copyDiagnostic: (value) async => copiedDiagnostic = value,
      ),
    );
    await tester.pumpAndSettle();
    await _openRestorePreview(tester);

    final viewDetails = find.descendant(
      of: find.byKey(const ValueKey('privacy-diagnostic-banner')),
      matching: find.text('View details'),
    );
    await tester.ensureVisible(viewDetails);
    await tester.tap(viewDetails);
    await tester.pumpAndSettle();
    expect(find.text('Failure stage: archive inspection'), findsOneWidget);
    expect(find.text('Error category: database validation'), findsOneWidget);
    await tester.tap(find.text('Copy diagnostic'));
    await tester.pumpAndSettle();
    expect(
      copiedDiagnostic,
      'operation=restore\n'
      'stage_code=archive_inspection\n'
      'error_code=database\n'
      'recovery_required=false',
    );
  });

  testWidgets('restore recovery diagnostics preserve failure details', (
    tester,
  ) async {
    final gateway = _ShareGateway(Directory.systemTemp)
      ..restoreFailure = const RestoreRecoveryRequiredException(
        stage: 'post-activation validation and refresh',
        errorCode: 'database',
      );
    await services.reset();
    addTearDown(() async => services.reset());
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );

    String? copiedDiagnostic;
    await tester.pumpWidget(
      app(
        selectRestoreFile: () async => XFile('/unused/backup.butlerly'),
        copyDiagnostic: (value) async => copiedDiagnostic = value,
      ),
    );
    await tester.pumpAndSettle();
    await _openRestorePreview(tester);
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    final viewDetails = find.descendant(
      of: find.byKey(const ValueKey('privacy-diagnostic-banner')),
      matching: find.text('View details'),
    );
    await tester.ensureVisible(viewDetails);
    await tester.tap(viewDetails);
    await tester.pumpAndSettle();
    expect(find.text('Failure stage: restore validation'), findsOneWidget);
    expect(find.text('Error category: database validation'), findsOneWidget);
    await tester.tap(find.text('Copy diagnostic'));
    await tester.pumpAndSettle();

    expect(
      copiedDiagnostic,
      'operation=restore\n'
      'stage_code=restore_validation\n'
      'error_code=database\n'
      'restore_mode=merge\n'
      'recovery_required=true',
    );
  });

  testWidgets('restore diagnostics preserve the pre-restore evidence stage', (
    tester,
  ) async {
    final gateway = _ShareGateway(Directory.systemTemp)
      ..restoreFailure = const RestoreFailureException(
        stage: 'pre-restore safety backup: evidence collection',
        errorCode: 'filesystem',
      );
    await services.reset();
    addTearDown(() async => services.reset());
    services.registerSingleton<WorkspaceDataService>(
      WorkspaceDataService(gateway, refreshSystemData: () async {}),
    );

    String? copiedDiagnostic;
    await tester.pumpWidget(
      app(
        selectRestoreFile: () async => XFile('/unused/backup.butlerly'),
        copyDiagnostic: (value) async => copiedDiagnostic = value,
      ),
    );
    await tester.pumpAndSettle();
    await _openRestorePreview(tester);
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();

    final viewDetails = find.descendant(
      of: find.byKey(const ValueKey('privacy-diagnostic-banner')),
      matching: find.text('View details'),
    );
    await tester.ensureVisible(viewDetails);
    await tester.tap(viewDetails);
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Failure stage: pre-restore safety backup: evidence collection',
      ),
      findsOneWidget,
    );
    expect(find.text('Error category: storage operation'), findsOneWidget);
    await tester.tap(find.text('Copy diagnostic'));
    await tester.pumpAndSettle();

    expect(
      copiedDiagnostic,
      'operation=restore\n'
      'stage_code=restore_preflight_safety_backup_evidence_collection\n'
      'error_code=filesystem\n'
      'restore_mode=merge\n'
      'recovery_required=false',
    );
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
    final diagnostic = find.descendant(
      of: find.byKey(const ValueKey('privacy-diagnostic-banner')),
      matching: find.text('View details'),
    );
    await tester.ensureVisible(diagnostic);
    await tester.tap(diagnostic);
    await tester.pumpAndSettle();
    expect(find.textContaining('destination storage'), findsAtLeastNWidgets(1));
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
        'Backup could not be created. Failure stage: temporary backup creation. Your financial data was not changed.',
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
        'Backup could not be created. Failure stage: portable backup creation. Your financial data was not changed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('backup failure details remain available and copy safe codes', (
    tester,
  ) async {
    final root = Directory(
      path.join(
        Directory.systemTemp.path,
        'butlerly-desktop-backup-diagnostic-${DateTime.now().microsecondsSinceEpoch}',
      ),
    )..createSync(recursive: true);
    addTearDown(() async {
      await services.reset();
      if (root.existsSync()) root.deleteSync(recursive: true);
      debugDefaultTargetPlatformOverride = null;
    });
    final gateway = _ShareGateway(root)..createFailure = StateError('private');
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
      find.byKey(const ValueKey('privacy-diagnostic-banner')),
      findsOneWidget,
    );
    expect(find.text('View details'), findsAtLeastNWidgets(1));
    final viewDetails = find.descendant(
      of: find.byKey(const ValueKey('privacy-diagnostic-banner')),
      matching: find.text('View details'),
    );
    await tester.ensureVisible(viewDetails);
    await tester.tap(viewDetails);
    await tester.pumpAndSettle();
    expect(find.text('Failure details'), findsOneWidget);
    expect(
      find.textContaining('portable backup creation'),
      findsAtLeastNWidgets(1),
    );
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('operation state'), findsAtLeastNWidgets(1));
    expect(find.text('Copy diagnostic'), findsOneWidget);
    expect(find.text('private'), findsNothing);
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

  testWidgets(
    'restore preview discloses archive warnings before mode selection',
    (tester) async {
      final gateway = _ShareGateway(Directory.systemTemp)
        ..inspectionWarnings = const [
          BackupWarning(code: 'missing_receipt', count: 2),
        ]
        ..inspectionMissingContentCount = 2;
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

      expect(
        find.textContaining(
          'This backup has 2 missing optional item(s) and 1 integrity warning(s).',
        ),
        findsOneWidget,
      );
      expect(find.text('View reports'), findsOneWidget);
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
  Object? restoreFailure;
  Object? inspectionFailure;
  LocalRestoreMode? selectedRestoreMode;
  bool encrypted = true;
  int inspectionCalls = 0;
  String? inspectionPassword;
  String? inspectPassword;
  List<BackupWarning> inspectionWarnings = const [];
  int inspectionMissingContentCount = 0;
  LocalRestoreResult? successfulRestore;

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
    if (inspectionFailure != null) throw inspectionFailure!;
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
      warnings: inspectionWarnings,
      missingContentCount: inspectionMissingContentCount,
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
    if (restoreFailure != null) throw restoreFailure!;
    if (successfulRestore != null) return successfulRestore!;
    throw StateError('restore mode captured for regression test');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
