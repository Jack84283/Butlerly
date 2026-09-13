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

  String _backupText(String key) {
    final language = Localizations.localeOf(context).languageCode;
    const strings = <String, Map<String, String>>{
      'en': {
        'backup': 'Back up Butlerly',
        'backupSubtitle': 'Create one portable local backup file.',
        'restoreBackup': 'Restore backup',
        'restoreSubtitle': 'Merge or replace data from a Butlerly backup.',
        'backupComplete': 'Backup created successfully.',
        'backupFailed': 'Backup could not be created.',
        'restoreFailed': 'Backup could not be restored.',
        'restoreTitle': 'Restore Butlerly backup?',
        'newerData': 'This device has data changed after this backup was created. Merge keeps those newer local changes. Replace discards the current Butlerly data and restores the backup.',
        'noNewerData': 'The backup is valid. Merge is recommended and preserves any local records that are newer than the backup.',
        'merge': 'Merge',
        'replace': 'Replace',
        'replaceTitle': 'Replace current Butlerly data?',
        'replaceBody': 'Current local Butlerly data will be replaced by the backup. This cannot be undone unless you have another backup.',
        'restoreComplete': 'Restore completed.',
        'backupSummary': '{records} records • {evidence} evidence files',
      },
      'es': {
        'backup': 'Crear copia de Butlerly',
        'backupSubtitle': 'Crea un único archivo de copia local portátil.',
        'restoreBackup': 'Restaurar copia',
        'restoreSubtitle': 'Combina o reemplaza datos desde una copia de Butlerly.',
        'backupComplete': 'La copia se creó correctamente.',
        'backupFailed': 'No se pudo crear la copia.',
        'restoreFailed': 'No se pudo restaurar la copia.',
        'restoreTitle': '¿Restaurar la copia de Butlerly?',
        'newerData': 'Este dispositivo tiene datos modificados después de crear la copia. Combinar conserva esos cambios locales más recientes. Reemplazar descarta los datos actuales de Butlerly y restaura la copia.',
        'noNewerData': 'La copia es válida. Se recomienda combinar para conservar cualquier registro local más reciente que la copia.',
        'merge': 'Combinar',
        'replace': 'Reemplazar',
        'replaceTitle': '¿Reemplazar los datos actuales de Butlerly?',
        'replaceBody': 'Los datos locales actuales de Butlerly serán reemplazados por la copia. No se puede deshacer salvo que tenga otra copia.',
        'restoreComplete': 'Restauración completada.',
        'backupSummary': '{records} registros • {evidence} archivos de evidencia',
      },
      'zh': {
        'backup': '备份 Butlerly',
        'backupSubtitle': '创建一个可跨设备使用的本地备份文件。',
        'restoreBackup': '恢复备份',
        'restoreSubtitle': '从 Butlerly 备份合并或替换数据。',
        'backupComplete': '备份创建成功。',
        'backupFailed': '无法创建备份。',
        'restoreFailed': '无法恢复备份。',
        'restoreTitle': '恢复 Butlerly 备份？',
        'newerData': '此设备包含在该备份创建之后修改的数据。合并会保留这些较新的本地更改；替换会丢弃当前 Butlerly 数据并恢复备份。',
        'noNewerData': '备份有效。建议使用“合并”，它会保留任何比备份更新的本地记录。',
        'merge': '合并',
        'replace': '替换',
        'replaceTitle': '替换当前 Butlerly 数据？',
        'replaceBody': '当前本地 Butlerly 数据将被备份替换。除非您还有其他备份，否则此操作无法撤销。',
        'restoreComplete': '恢复完成。',
        'backupSummary': '{records} 条记录 • {evidence} 个凭证文件',
      },
    };
    return (strings[language] ?? strings['en']!)[key] ?? key;
  }

  Future<void> _backup() async {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final location = await getSaveLocation(
      suggestedName: 'Butlerly Backup $timestamp.butlerlybackup',
      acceptedTypeGroups: const [_backupType],
    );
    if (location == null) return;
    setState(() => _busy = true);
    try {
      await services<LocalBackupManager>().createBackup(File(location.path));
      if (mounted) _message(_backupText('backupComplete'));
    } on Exception {
      if (mounted) _message(_backupText('backupFailed'));
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
      final result = await manager.restore(file, mode: mode);
      await services<FinanceServices>().seedInitialMasterData(buildInitialMasterData());
      ref.invalidate(userPreferenceProvider);
      notifyTransactionChanged();
      if (!mounted) return;
      _message(
        '${_backupText('restoreComplete')} '
        '${result.restoredRows} restored, '
        '${result.keptNewerLocalRows} newer local records kept.',
      );
    } on Exception {
      if (mounted) _message(_backupText('restoreFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<LocalRestoreMode?> _chooseRestoreMode(BackupInspection inspection) =>
      showButlerlyBottomSheet<LocalRestoreMode>(
        context: context,
        builder: (context) {
          final summary = _backupText('backupSummary')
              .replaceAll('{records}', '${inspection.recordCount}')
              .replaceAll('{evidence}', '${inspection.evidenceCount}');
          final created = inspection.createdAtUtc.toLocal();
          return ButlerlySheet(
            title: Text(_backupText('restoreTitle')),
            content: Text(
              '$summary\n${created.toString()}\n\n'
              '${inspection.hasNewerLocalData ? _backupText('newerData') : _backupText('noNewerData')}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.text('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, LocalRestoreMode.replace),
                child: Text(_backupText('replace')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, LocalRestoreMode.merge),
                child: Text(_backupText('merge')),
              ),
            ],
          );
        },
      );

  Future<bool> _confirmReplace() async =>
      (await showButlerlyBottomSheet<bool>(
        context: context,
        builder: (context) => ButlerlySheet(
          title: Text(_backupText('replaceTitle')),
          content: Text(_backupText('replaceBody')),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('cancel')),
            ),
            ButlerlyDestructiveButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_backupText('replace')),
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
          title: Text(_backupText('backup')),
          subtitle: Text(
            _backupText('backupSubtitle'),
            style: _subtitleStyle(context),
          ),
          onTap: _backup,
        ),
        const Divider(),
        ListTile(
          enabled: !_busy,
          leading: const Icon(Icons.restore_outlined),
          title: Text(_backupText('restoreBackup')),
          subtitle: Text(
            _backupText('restoreSubtitle'),
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
