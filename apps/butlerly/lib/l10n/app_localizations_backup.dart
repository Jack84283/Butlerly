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
    'backupSubtitle': 'Create one encrypted portable local backup file.',
    'restoreBackup': 'Restore backup',
    'restoreSubtitle': 'Merge or replace data from a Butlerly backup.',
    'backupComplete': 'Encrypted backup created successfully.',
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
    'backupPasswordTitle': 'Protect this backup',
    'backupPasswordBody':
        'This backup contains sensitive financial data and receipt or document evidence. Butlerly will encrypt the file with your password. Butlerly cannot recover the backup if you lose this password.',
    'backupPasswordLabel': 'Backup password',
    'backupPasswordConfirmLabel': 'Confirm password',
    'backupPasswordTooShort': 'Use at least 12 characters.',
    'backupPasswordMismatch': 'The passwords do not match.',
    'createEncryptedBackup': 'Create encrypted backup',
    'restorePasswordTitle': 'Unlock backup',
    'restorePasswordBody':
        'Enter the password used when this Butlerly backup was created.',
    'unlockBackup': 'Unlock',
    'passwordOrIntegrityFailed':
        'The password is incorrect or the encrypted backup is damaged.',
    'recoveryRequiredTitle': 'Butlerly recovery is required',
    'recoveryRequiredBody':
        'A restore could not be safely rolled back. Normal editing is paused. Butlerly kept the pre-restore safety copy so it can restore and validate the last known local state.',
    'recoverSafetyBackup': 'Restore safety copy',
    'recoveryStillRequired':
        'Recovery is still required. Your safety copy has been kept; normal editing remains disabled.',
  },
  'es': {
    'backup': 'Crear copia de Butlerly',
    'backupSubtitle': 'Crea un archivo de copia local portátil y cifrado.',
    'restoreBackup': 'Restaurar copia',
    'restoreSubtitle':
        'Combina o reemplaza datos desde una copia de Butlerly.',
    'backupComplete': 'La copia cifrada se creó correctamente.',
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
    'backupPasswordTitle': 'Proteger esta copia',
    'backupPasswordBody':
        'Esta copia contiene datos financieros confidenciales y comprobantes o documentos. Butlerly cifrará el archivo con su contraseña. Butlerly no puede recuperar la copia si pierde esta contraseña.',
    'backupPasswordLabel': 'Contraseña de la copia',
    'backupPasswordConfirmLabel': 'Confirmar contraseña',
    'backupPasswordTooShort': 'Use al menos 12 caracteres.',
    'backupPasswordMismatch': 'Las contraseñas no coinciden.',
    'createEncryptedBackup': 'Crear copia cifrada',
    'restorePasswordTitle': 'Desbloquear copia',
    'restorePasswordBody':
        'Introduzca la contraseña usada al crear esta copia de Butlerly.',
    'unlockBackup': 'Desbloquear',
    'passwordOrIntegrityFailed':
        'La contraseña es incorrecta o la copia cifrada está dañada.',
    'recoveryRequiredTitle': 'Butlerly requiere recuperación',
    'recoveryRequiredBody':
        'No se pudo revertir una restauración de forma segura. La edición normal está pausada. Butlerly conservó la copia de seguridad previa a la restauración para recuperar y validar el último estado local conocido.',
    'recoverSafetyBackup': 'Restaurar copia de seguridad',
    'recoveryStillRequired':
        'La recuperación sigue siendo necesaria. La copia de seguridad se conserva y la edición normal continúa deshabilitada.',
  },
  'zh': {
    'backup': '备份 Butlerly',
    'backupSubtitle': '创建一个加密且可跨设备使用的本地备份文件。',
    'restoreBackup': '恢复备份',
    'restoreSubtitle': '从 Butlerly 备份合并或替换数据。',
    'backupComplete': '加密备份创建成功。',
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
    'backupPasswordTitle': '保护此备份',
    'backupPasswordBody':
        '此备份包含敏感的财务数据以及收据或文档凭证。Butlerly 将使用您的密码加密该文件。如果密码丢失，Butlerly 无法恢复此备份。',
    'backupPasswordLabel': '备份密码',
    'backupPasswordConfirmLabel': '确认密码',
    'backupPasswordTooShort': '请至少使用 12 个字符。',
    'backupPasswordMismatch': '两次输入的密码不一致。',
    'createEncryptedBackup': '创建加密备份',
    'restorePasswordTitle': '解锁备份',
    'restorePasswordBody': '请输入创建此 Butlerly 备份时使用的密码。',
    'unlockBackup': '解锁',
    'passwordOrIntegrityFailed': '密码不正确，或加密备份已损坏。',
    'recoveryRequiredTitle': 'Butlerly 需要恢复',
    'recoveryRequiredBody':
        '一次恢复操作无法安全回滚。正常编辑已暂停。Butlerly 已保留恢复前的安全副本，可用于恢复并验证最后一个已知的本地状态。',
    'recoverSafetyBackup': '恢复安全副本',
    'recoveryStillRequired': '仍需要执行恢复。安全副本已保留，正常编辑仍未重新启用。',
  },
};
