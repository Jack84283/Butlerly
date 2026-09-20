import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart' as share;

class PrivacyDataPage extends ConsumerStatefulWidget {
  const PrivacyDataPage({super.key});

  @override
  ConsumerState<PrivacyDataPage> createState() => _PrivacyDataPageState();
}

class _PrivacyDataPageState extends ConsumerState<PrivacyDataPage> {
  static const _backupType = XTypeGroup(
    label: 'Butlerly backup',
    extensions: [PortableBackupPolicy.extension],
    uniformTypeIdentifiers: [PortableBackupPolicy.uniformTypeIdentifier],
  );

  bool _busy = false;

  bool get _usesNativeMobileShare =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> _backup() async {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final fileName = 'Butlerly Backup $timestamp.butlerlybackup';

    if (_usesNativeMobileShare) {
      final password = await _createBackupPassword();
      if (password == null || !mounted) return;
      await _createAndShareMobileBackup(fileName, password);
      return;
    }

    final location = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const [_backupType],
    );
    if (location == null || !mounted) return;

    final password = await _createBackupPassword();
    if (password == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await services<WorkspaceDataService>().createPortableBackup(
        location.path,
        password: password,
      );
      if (mounted) _message(context.l10n.backupText('backupComplete'));
    } on BackupPasswordTooShortException {
      if (mounted) _message(context.l10n.backupText('backupPasswordTooShort'));
    } catch (_) {
      if (mounted) _message(context.l10n.backupText('backupFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAndShareMobileBackup(
    String fileName,
    String password,
  ) async {
    setState(() => _busy = true);
    String? filePath;
    try {
      filePath = await services<WorkspaceDataService>().createTemporaryBackup(
        fileName,
        password: password,
      );
      if (!mounted) return;

      final renderBox = context.findRenderObject();
      final shareOrigin = renderBox is RenderBox
          ? renderBox.localToGlobal(Offset.zero) & renderBox.size
          : null;
      final result = await share.SharePlus.instance.share(
        share.ShareParams(
          files: [
            share.XFile(filePath, mimeType: PortableBackupPolicy.mimeType),
          ],
          title: fileName,
          sharePositionOrigin: shareOrigin,
        ),
      );
      if (mounted && result.status == share.ShareResultStatus.success) {
        _message(context.l10n.backupText('backupComplete'));
      }
    } on BackupPasswordTooShortException {
      if (mounted) _message(context.l10n.backupText('backupPasswordTooShort'));
    } catch (_) {
      if (mounted) _message(context.l10n.backupText('backupFailed'));
    } finally {
      if (filePath != null) {
        await services<WorkspaceDataService>().discardTemporaryBackup(filePath);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final selected = await openFile(acceptedTypeGroups: const [_backupType]);
    if (selected == null) return;

    final file = selected.path;
    final manager = services<WorkspaceDataService>();
    String? password;
    try {
      if (await manager.isEncryptedBackup(file)) {
        if (!mounted) return;
        password = await _requestRestorePassword();
        if (password == null || !mounted) return;
      }

      setState(() => _busy = true);
      final inspection = await manager.inspect(file, password: password);
      if (!mounted) return;
      setState(() => _busy = false);
      final mode = await _chooseRestoreMode(inspection);
      if (mode == null) return;
      if (mode == LocalRestoreMode.replace && !await _confirmReplace()) return;
      if (!mounted) return;
      setState(() => _busy = true);
      final result = await manager.restore(
        file,
        mode: mode,
        password: password,
        refreshPresentation: () async {
          ref.invalidate(userPreferenceProvider);
          notifyTransactionChanged();
        },
      );
      if (!mounted) return;
      final summary = context.l10n
          .backupText('restoreResult')
          .replaceAll('{restored}', '${result.restoredRows}')
          .replaceAll('{kept}', '${result.keptNewerLocalRows}');
      _message('${context.l10n.backupText('restoreComplete')} $summary');
    } on BackupPasswordOrIntegrityException {
      if (mounted) {
        _message(context.l10n.backupText('passwordOrIntegrityFailed'));
      }
    } on BackupPasswordRequiredException {
      if (mounted) {
        _message(context.l10n.backupText('passwordOrIntegrityFailed'));
      }
    } on RestoreRecoveryRequiredException {
      // RestoreRecoveryState immediately replaces normal navigation with the
      // recovery-only surface. Do not add a competing generic snackbar here.
    } catch (_) {
      if (mounted) _message(context.l10n.backupText('restoreFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _createBackupPassword() async {
    final password = TextEditingController();
    final confirmation = TextEditingController();
    String? error;
    try {
      return await showButlerlyBottomSheet<String>(
        context: context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) => ButlerlySheet(
            title: Text(context.l10n.backupText('backupPasswordTitle')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(context.l10n.backupText('backupPasswordBody')),
                const SizedBox(height: ButlerlySpacing.standard),
                TextField(
                  controller: password,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.l10n.backupText('backupPasswordLabel'),
                  ),
                ),
                const SizedBox(height: ButlerlySpacing.compact),
                TextField(
                  controller: confirmation,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: context.l10n.backupText(
                      'backupPasswordConfirmLabel',
                    ),
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(context.l10n.text('cancel')),
              ),
              FilledButton(
                onPressed: () {
                  if (password.text.length <
                      PortableBackupPolicy.minimumPasswordLength) {
                    setSheetState(
                      () => error = context.l10n.backupText(
                        'backupPasswordTooShort',
                      ),
                    );
                    return;
                  }
                  if (password.text != confirmation.text) {
                    setSheetState(
                      () => error = context.l10n.backupText(
                        'backupPasswordMismatch',
                      ),
                    );
                    return;
                  }
                  Navigator.pop(sheetContext, password.text);
                },
                child: Text(context.l10n.backupText('createEncryptedBackup')),
              ),
            ],
          ),
        ),
      );
    } finally {
      password.dispose();
      confirmation.dispose();
    }
  }

  Future<String?> _requestRestorePassword() async {
    final password = TextEditingController();
    try {
      return await showButlerlyBottomSheet<String>(
        context: context,
        builder: (sheetContext) => ButlerlySheet(
          title: Text(context.l10n.backupText('restorePasswordTitle')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n.backupText('restorePasswordBody')),
              const SizedBox(height: ButlerlySpacing.standard),
              TextField(
                controller: password,
                autofocus: true,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: context.l10n.backupText('backupPasswordLabel'),
                ),
                onSubmitted: (value) {
                  if (value.isNotEmpty) Navigator.pop(sheetContext, value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(context.l10n.text('cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (password.text.isNotEmpty) {
                  Navigator.pop(sheetContext, password.text);
                }
              },
              child: Text(context.l10n.backupText('unlockBackup')),
            ),
          ],
        ),
      );
    } finally {
      password.dispose();
    }
  }

  String _changeDetails(BackupInspection inspection) {
    if (!inspection.hasNewerLocalData) return '';
    final changes = inspection.changes;
    final lines = <String>[];
    if (changes.transactionsAdded > 0) {
      lines.add(
        '• ${changes.transactionsAdded} '
        '${context.l10n.backupText('addedTransactions')}',
      );
    }
    if (changes.transactionsChanged > 0) {
      lines.add(
        '• ${changes.transactionsChanged} '
        '${context.l10n.backupText('changedTransactions')}',
      );
    }
    if (changes.masterDataChanged > 0) {
      lines.add(
        '• ${changes.masterDataChanged} '
        '${context.l10n.backupText('changedMasterData')}',
      );
    }
    if (changes.deletedEntities > 0) {
      lines.add(
        '• ${changes.deletedEntities} '
        '${context.l10n.backupText('deletedItems')}',
      );
    }
    return lines.join('\n');
  }

  Future<LocalRestoreMode?> _chooseRestoreMode(BackupInspection inspection) =>
      showButlerlyBottomSheet<LocalRestoreMode>(
        context: context,
        builder: (context) {
          final summary = context.l10n
              .backupText('backupSummary')
              .replaceAll('{records}', '${inspection.recordCount}')
              .replaceAll('{evidence}', '${inspection.evidenceCount}');
          final created = inspection.createdAtUtc.toLocal();
          final details = _changeDetails(inspection);
          final body = inspection.hasNewerLocalData
              ? '${context.l10n.backupText('newerData')}\n\n$details'
              : context.l10n.backupText('noNewerData');
          return ButlerlySheet(
            title: Text(context.l10n.backupText('restoreTitle')),
            content: Text('$summary\n${created.toString()}\n\n$body'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.text('cancel')),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, LocalRestoreMode.replace),
                child: Text(context.l10n.backupText('replace')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, LocalRestoreMode.merge),
                child: Text(context.l10n.backupText('merge')),
              ),
            ],
          );
        },
      );

  Future<bool> _confirmReplace() async =>
      (await showButlerlyBottomSheet<bool>(
        context: context,
        builder: (context) => ButlerlySheet(
          title: Text(context.l10n.backupText('replaceTitle')),
          content: Text(context.l10n.backupText('replaceBody')),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('cancel')),
            ),
            ButlerlyDestructiveButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.l10n.backupText('replace')),
            ),
          ],
        ),
      )) ==
      true;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final result = await services<WorkspaceDataService>().exportAll();
      if (!mounted) return;
      final displayPath = defaultTargetPlatform == TargetPlatform.iOS
          ? 'Files → On My iPhone → Butlerly → ${path.basename(result.directoryPath)}'
          : result.directoryPath;
      await showButlerlyBottomSheet<void>(
        context: context,
        builder: (context) => ButlerlySheet(
          title: Text(context.l10n.text('exportComplete')),
          content: Text(
            context.l10n.text('exportCompleteBody', {
              'count': '${result.recordCount}',
              'path': displayPath,
            }),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.text('done')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) _message(context.l10n.text('exportFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmErase() async {
    final confirmed = await showButlerlyBottomSheet<bool>(
      context: context,
      builder: (context) => ButlerlySheet(
        title: Text(context.l10n.text('eraseAllTitle')),
        content: Text(context.l10n.text('eraseAllBody')),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          ButlerlyDestructiveButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('eraseAllConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await services<WorkspaceDataService>().eraseAll(
        refreshPresentation: () async {
          ref.invalidate(userPreferenceProvider);
          notifyTransactionChanged();
        },
      );
      if (mounted) _message(context.l10n.text('eraseComplete'));
    } catch (_) {
      if (mounted) _message(context.l10n.text('eraseFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('privacyAndData'))),
    body: ButlerlyResponsiveBody(
      contentKey: const ValueKey('privacy-data-content'),
      child: ListView(
        padding: const EdgeInsets.all(ButlerlySpacing.standard),
        children: [
          ButlerlyCard(child: Text(context.l10n.text('privacyScopeBody'))),
          ButlerlySectionHeader(title: context.l10n.text('localDataControls')),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.backup_outlined),
            title: Text(context.l10n.backupText('backup')),
            subtitle: Text(
              context.l10n.backupText('backupSubtitle'),
              style: _subtitleStyle(context),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _backup,
          ),
          const Divider(),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.restore_outlined),
            title: Text(context.l10n.backupText('restoreBackup')),
            subtitle: Text(
              context.l10n.backupText('restoreSubtitle'),
              style: _subtitleStyle(context),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _restore,
          ),
          const Divider(),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.download_outlined),
            title: Text(context.l10n.text('exportToFile')),
            subtitle: Text(
              context.l10n.text('exportScopeBody'),
              style: _subtitleStyle(context),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _export,
          ),
          const Divider(),
          ListTile(
            enabled: !_busy,
            leading: const Icon(Icons.delete_forever_outlined),
            title: Text(context.l10n.text('resetAllData')),
            subtitle: Text(
              context.l10n.text('eraseScopeBody'),
              style: _subtitleStyle(context),
            ),
            textColor: Theme.of(context).colorScheme.error,
            iconColor: Theme.of(context).colorScheme.error,
            onTap: _confirmErase,
          ),
          if (_busy) const ButlerlyLoadingState(),
        ],
      ),
    ),
  );
}

TextStyle? _subtitleStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: context.colors.secondaryText);
