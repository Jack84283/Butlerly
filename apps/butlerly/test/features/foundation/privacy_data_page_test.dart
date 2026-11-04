import 'dart:io';

import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/privacy_data_page.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart'
    show RepositoryException, RepositoryFailureCode;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    Locale locale = const Locale('en'),
    TargetPlatform? platform,
  }) => ProviderScope(
    child: MaterialApp(
      theme: platform == null ? null : ThemeData(platform: platform),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: PrivacyDataPage(shareClient: shareClient),
    ),
  );

  test('Restore failures identify known categories without exposing paths', () {
    expect(
      classifyRestoreFailure(const BackupPasswordOrIntegrityException()),
      RestoreFailureKind.authentication,
    );
    expect(
      classifyRestoreFailure(const BackupPasswordRequiredException()),
      RestoreFailureKind.missingPassword,
    );
    expect(
      classifyRestoreFailure(
        const FormatException('Unsupported Butlerly backup format.'),
      ),
      RestoreFailureKind.unsupportedFormat,
    );
    expect(
      classifyRestoreFailure(
        const FormatException('Backup SQLite snapshot is damaged.'),
      ),
      RestoreFailureKind.damaged,
    );
    expect(
      classifyRestoreFailure(const UnsupportedBackupSchemaException()),
      RestoreFailureKind.unsupportedSchema,
    );
    expect(
      classifyRestoreFailure(
        const FormatException('Incompatible columns for table transactions.'),
      ),
      RestoreFailureKind.mergeConflict,
    );
    expect(
      classifyRestoreFailure(
        const FileSystemException(
          'Restore staging failed',
          '/private/storage/path',
          OSError('No space left on device', 28),
        ),
      ),
      RestoreFailureKind.storage,
    );
    expect(
      classifyRestoreFailure(StateError('Restore recovery required')),
      RestoreFailureKind.recovery,
    );
    expect(
      classifyRestoreFailure(
        const RepositoryException(
          RepositoryFailureCode.migration,
          'upgrade staging schema',
        ),
      ),
      RestoreFailureKind.migration,
    );
    expect(
      classifyRestoreFailure(
        const RepositoryException(
          RepositoryFailureCode.integrity,
          'validate SQLite',
        ),
      ),
      RestoreFailureKind.damaged,
    );
    expect(
      classifyRestoreFailure(StateError('Other unclassified error')),
      RestoreFailureKind.unknown,
    );
  });

  testWidgets('authentication error explains password or encrypted damage', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PrivacyDataPage));
    final dialog = showBackupRestoreFailureDialog(
      context,
      error: const BackupPasswordOrIntegrityException(),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unable to restore backup'), findsOneWidget);
    expect(find.text('Reason'), findsOneWidget);
    expect(find.text('What to do next'), findsOneWidget);
    expect(find.textContaining('cannot tell which occurred'), findsOneWidget);
    expect(find.textContaining('Check the exact backup password'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await dialog;
  });

  testWidgets('corrupt archive errors have localized recovery guidance', (
    tester,
  ) async {
    await tester.pumpWidget(app(locale: const Locale('zh')));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PrivacyDataPage));
    final dialog = showBackupRestoreFailureDialog(
      context,
      error: const FormatException('Backup manifest checksum mismatch.'),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法恢复备份'), findsOneWidget);
    expect(find.text('失败原因'), findsOneWidget);
    expect(find.textContaining('完整性'), findsOneWidget);
    expect(find.textContaining('保留失败文件'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await dialog;
  });

  testWidgets(
    'Privacy and data uses Cupertino symbols for native iOS actions',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(platform: TargetPlatform.iOS));
      await tester.pumpAndSettle();

      expect(find.byIcon(CupertinoIcons.archivebox), findsOneWidget);
      // The additional Merge action may push later actions below the fold.
      // Scroll until each action is built instead of assuming all are visible.
      await tester.scrollUntilVisible(
        find.byIcon(CupertinoIcons.arrow_counterclockwise),
        180,
      );
      expect(
        find.byIcon(CupertinoIcons.arrow_counterclockwise),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byIcon(CupertinoIcons.arrow_down_doc),
        180,
      );
      expect(find.byIcon(CupertinoIcons.arrow_down_doc), findsOneWidget);
      await tester.scrollUntilVisible(find.byIcon(CupertinoIcons.trash), 180);
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
      expect(
        find.byKey(const ValueKey('desktop-privacy-restore-merge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('desktop-privacy-restore-replace')),
        findsOneWidget,
      );
      expect(find.text('Merge backup'), findsOneWidget);
      expect(find.text('Replace from backup'), findsOneWidget);
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
    expect(
      find.byKey(const ValueKey('mobile-privacy-restore-merge')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-privacy-restore-replace')),
      findsOneWidget,
    );
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

  testWidgets('newer database prompts iPhone App Store update steps', (
    tester,
  ) async {
    await tester.pumpWidget(app(platform: TargetPlatform.iOS));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PrivacyDataPage));

    final dialog = showBackupRequiresAppUpdateDialog(
      context,
      backupVersion: 20,
      supportedVersion: 19,
    );
    await tester.pumpAndSettle();
    expect(find.text('Update Butlerly before restoring'), findsOneWidget);
    expect(find.textContaining('schema 20'), findsOneWidget);
    expect(find.textContaining('supports schema 19'), findsOneWidget);
    expect(find.textContaining('App Store'), findsOneWidget);
    expect(
      find.textContaining('Nothing on this device was changed'),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await dialog;
  });

  testWidgets('newer database prompts Android Google Play update steps', (
    tester,
  ) async {
    await tester.pumpWidget(app(platform: TargetPlatform.android));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PrivacyDataPage));
    final dialog = showBackupRequiresAppUpdateDialog(
      context,
      backupVersion: 21,
      supportedVersion: 19,
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Google Play'), findsOneWidget);
    expect(find.textContaining('schema 21'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await dialog;
  });

  testWidgets('newer schema update guidance is translated to Chinese', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(locale: const Locale('zh', 'CN'), platform: TargetPlatform.iOS),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PrivacyDataPage));
    final dialog = showBackupRequiresAppUpdateDialog(
      context,
      backupVersion: 20,
      supportedVersion: 19,
    );
    await tester.pumpAndSettle();
    expect(find.text('请先更新 Butlerly 再恢复备份'), findsOneWidget);
    expect(find.textContaining('App Store'), findsOneWidget);
    expect(find.textContaining('版本 20'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    await dialog;
  });

  testWidgets(
    'Replace describes full data loss and requires explicit consent',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(PrivacyDataPage));
      final confirmation = showBackupRestoreConfirmation(
        context,
        inspection: BackupInspection(
          createdAtUtc: DateTime.utc(2026, 10, 31),
          recordCount: 42,
          evidenceCount: 6,
          changes: const BackupChangeSummary(
            transactionsAdded: 0,
            transactionsChanged: 0,
            masterDataChanged: 0,
            deletedEntities: 0,
          ),
        ),
        mode: LocalRestoreMode.replace,
      );
      await tester.pumpAndSettle();

      expect(find.text('Replace all Butlerly data?'), findsOneWidget);
      expect(
        find.textContaining('ENTIRE local Butlerly database'),
        findsOneWidget,
      );
      expect(find.textContaining('Master data:'), findsOneWidget);
      expect(find.textContaining('Transactions,'), findsOneWidget);
      expect(find.textContaining('Analysis rules,'), findsOneWidget);
      expect(
        find.textContaining('in-app preferences/settings'),
        findsOneWidget,
      );
      expect(find.textContaining('Local attachments,'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(find.textContaining('42 records'), findsOneWidget);

      final button = find.descendant(
        of: find.byKey(const ValueKey('restore-replace-confirm')),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      final acknowledgement = find.byKey(
        const ValueKey('restore-replace-acknowledgement'),
      );
      await tester.ensureVisible(acknowledgement);
      await tester.tap(acknowledgement);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('restore-replace-confirm')));
      await tester.pumpAndSettle();
      expect(await confirmation, isTrue);

      // Every new Replace confirmation must require acknowledgement again.
      final second = showBackupRestoreConfirmation(
        context,
        inspection: BackupInspection(
          createdAtUtc: DateTime.utc(2026, 10, 31),
          recordCount: 42,
          evidenceCount: 6,
          changes: const BackupChangeSummary(
            transactionsAdded: 0,
            transactionsChanged: 0,
            masterDataChanged: 0,
            deletedEntities: 0,
          ),
        ),
        mode: LocalRestoreMode.replace,
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(await second, isFalse);
    },
  );

  testWidgets('Merge confirmation never shows destructive Replace consent', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(PrivacyDataPage));
    final confirmation = showBackupRestoreConfirmation(
      context,
      inspection: BackupInspection(
        createdAtUtc: DateTime.utc(2026, 10, 31),
        recordCount: 2,
        evidenceCount: 1,
        changes: const BackupChangeSummary(
          transactionsAdded: 0,
          transactionsChanged: 0,
          masterDataChanged: 0,
          deletedEntities: 0,
        ),
      ),
      mode: LocalRestoreMode.merge,
    );
    await tester.pumpAndSettle();

    expect(find.text('Merge Butlerly backup?'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('restore-replace-acknowledgement')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('restore-replace-confirm')), findsNothing);
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    expect(await confirmation, isTrue);
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

final class _SharePlatform extends share_platform.SharePlatform {
  share_plus.ShareParams? params;
  bool sawFileDuringShare = false;

  @override
  Future<share_plus.ShareResult> share(share_plus.ShareParams value) async {
    params = value;
    final file = value.files!.single;
    sawFileDuringShare = File(file.path).existsSync();
    return const share_plus.ShareResult(
      'shared',
      share_plus.ShareResultStatus.success,
    );
  }
}

final class _ShareGateway implements LocalDataGateway {
  _ShareGateway(this.root);

  final Directory root;
  String? discardedPath;

  @override
  Future<String> createTemporaryBackup(
    String fileName, {
    required String password,
  }) async {
    final file = File(path.join(root.path, fileName));
    file.writeAsBytesSync(const [1, 2, 3]);
    return file.path;
  }

  @override
  Future<void> discardTemporaryBackup(String filePath) async {
    discardedPath = filePath;
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
