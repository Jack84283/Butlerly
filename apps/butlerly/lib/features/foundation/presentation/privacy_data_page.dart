import 'dart:io';

import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/initial_master_data.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PrivacyDataPage extends ConsumerStatefulWidget {
  const PrivacyDataPage({super.key});

  @override
  ConsumerState<PrivacyDataPage> createState() => _PrivacyDataPageState();
}

class _PrivacyDataPageState extends ConsumerState<PrivacyDataPage> {
  static const _backupType = XTypeGroup(
    label: 'Butlerly backup',
    extensions: ['butlerlybackup'],
  );

  bool _busy = false;

  Future<void> _backup() async {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final location = await getSaveLocation(
      suggestedName: 'Butlerly Backup $timestamp.butlerlybackup',
      acceptedTypeGroups: const [_backupType],
    );
    if (location == null) return;
    setState(() => _busy = true);
    try {
      await services<LocalBackupManager>().createBackup(File(location.path));
      if (mounted) _message(context.l10n.backupText('backupComplete'));
    } on Exception {
      if (mounted) _message(context.l10n.backupText('backupFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final selected = await openFile(acceptedTypeGroups: const [_backupType]);
    if (selected == null) return;
    setState(() => _busy = true);
    try {
      final file = File(selected.path);
      final manager = services<LocalBackupManager>();
      final inspection = await manager.inspect(file);
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
        postActivationRefresh: () async {
          await services<FinanceServices>().seedInitialMasterData(
            buildInitialMasterData(),
          );
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
    } on Exception {
      if (mounted) _message(context.l10n.backupText('restoreFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
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
      final result = await services<LocalDataManager>().exportAll();
      if (!mounted) return;
      await showButlerlyBottomSheet<void>(
        context: context,
        builder: (context) => ButlerlySheet(
          title: Text(context.l10n.text('exportComplete')),
          content: Text(
            context.l10n.text('exportCompleteBody', {
              'count': '${result.recordCount}',
              'path': result.directory.path,
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
    } on Exception {
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
      await services<LocalDataManager>().eraseAll();
      await services<FinanceServices>().seedInitialMasterData(
        buildInitialMasterData(),
      );
      ref.invalidate(userPreferenceProvider);
      notifyTransactionChanged();
      if (mounted) _message(context.l10n.text('eraseComplete'));
    } on Exception {
      if (mounted) _message(context.l10n.text('eraseFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('privacyAndData'))),
    body: ListView(
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
  );
}

TextStyle? _subtitleStyle(BuildContext context) => Theme.of(
  context,
).textTheme.bodySmall?.copyWith(color: context.colors.secondaryText);
