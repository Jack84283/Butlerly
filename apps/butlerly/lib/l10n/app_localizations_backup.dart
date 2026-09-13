import 'package:butlerly/l10n/app_localizations.dart';

/// Backup/restore copy kept in the localization layer rather than presentation.
///
/// This extension follows the same locale and fallback semantics as
/// [AppLocalizations] while the backup vocabulary remains feature-scoped.
extension BackupAppLocalizations on AppLocalizations {
  String backupText(String key) {
    final language = locale.languageCode;
    return (_backupStrings[language] ?? _backupStrings['en']!)[key] ??
        _backupStrings['en']![key] ??
        key;
  }
}

/// Mirrors [AppLocalizations.missingKeysFor] so feature-scoped backup copy is
/// covered by the same localization-completeness contract in CI.
Set<String> missingBackupLocalizationKeysFor(String languageCode) =>
    _backupStrings['en']!.keys.toSet().difference(
      (_backupStrings[languageCode] ?? const <String, String>{}).keys.toSet(),
    );

Set<String> get backupLocalizationKeys => _backupStrings['en']!.keys.toSet();

const _backupStrings = <String, Map<String, String>>{
  'en': {
    'backup': 'Back up Butlerly',
    'backupSubtitle': 'Create one portable local backup file.',
    'restoreBackup': 'Restore backup',
    'restoreSubtitle': 'Merge or replace data from a Butlerly backup.',
    'backupComplete': 'Backup created successfully.',
    'backupFailed': 'Backup could not be created.',
    'restoreFailed': 'Backup could not be restored.',
    'restoreTitle': 'Restore Butlerly backup?',
    'newerData':
        'This device has newer local data. Merge keeps those changes. Replace discards current Butlerly data and restores the backup.',
    'noNewerData':
        'The backup is valid. Merge is recommended and preserves any local records that are newer than the backup.',
    'merge': 'Merge',
    'replace': 'Replace',
    'replaceTitle': 'Replace current Butlerly data?',
    'replaceBody':
        'Current local Butlerly data will be replaced by the backup. This cannot be undone unless you have another backup.',
    'restoreComplete': 'Restore completed.',
    'restoreResult': '{restored} restored • {kept} newer local records kept',
    'backupSummary': '{records} records • {evidence} evidence files',
    'addedTransactions': 'transactions added after the backup',
    'changedTransactions': 'transactions changed after the backup',
    'changedMasterData': 'records changed after the backup',
    'deletedItems': 'items deleted after the backup',
  },
  'es': {
    'backup': 'Crear copia de Butlerly',
    'backupSubtitle': 'Crea un único archivo de copia local portátil.',
    'restoreBackup': 'Restaurar copia',
    'restoreSubtitle':
        'Combina o reemplaza datos desde una copia de Butlerly.',
    'backupComplete': 'La copia se creó correctamente.',
    'backupFailed': 'No se pudo crear la copia.',
    'restoreFailed': 'No se pudo restaurar la copia.',
    'restoreTitle': '¿Restaurar la copia de Butlerly?',
    'newerData':
        'Este dispositivo tiene datos locales más recientes. Combinar conserva esos cambios. Reemplazar descarta los datos actuales de Butlerly y restaura la copia.',
    'noNewerData':
        'La copia es válida. Se recomienda combinar para conservar cualquier registro local más reciente que la copia.',
    'merge': 'Combinar',
    'replace': 'Reemplazar',
    'replaceTitle': '¿Reemplazar los datos actuales de Butlerly?',
    'replaceBody':
        'Los datos locales actuales de Butlerly serán reemplazados por la copia. No se puede deshacer salvo que tenga otra copia.',
    'restoreComplete': 'Restauración completada.',
    'restoreResult':
        '{restored} restaurados • {kept} registros locales más recientes conservados',
    'backupSummary': '{records} registros • {evidence} archivos de evidencia',
    'addedTransactions': 'transacciones añadidas después de la copia',
    'changedTransactions': 'transacciones modificadas después de la copia',
    'changedMasterData': 'registros modificados después de la copia',
    'deletedItems': 'elementos eliminados después de la copia',
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
    'newerData': '此设备包含较新的本地数据。合并会保留这些更改；替换会丢弃当前 Butlerly 数据并恢复备份。',
    'noNewerData': '备份有效。建议使用“合并”，它会保留任何比备份更新的本地记录。',
    'merge': '合并',
    'replace': '替换',
    'replaceTitle': '替换当前 Butlerly 数据？',
    'replaceBody': '当前本地 Butlerly 数据将被备份替换。除非您还有其他备份，否则此操作无法撤销。',
    'restoreComplete': '恢复完成。',
    'restoreResult': '已恢复 {restored} 条 • 保留 {kept} 条较新的本地记录',
    'backupSummary': '{records} 条记录 • {evidence} 个凭证文件',
    'addedTransactions': '笔交易是在备份之后新增的',
    'changedTransactions': '笔交易是在备份之后修改的',
    'changedMasterData': '条记录是在备份之后修改的',
    'deletedItems': '项数据是在备份之后删除的',
  },
};
