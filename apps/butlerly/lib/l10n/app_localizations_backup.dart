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
        'Butlerly has paused normal editing until the current restore state is validated. A pre-restore safety copy is available if the current state cannot be kept safely.',
    'recoveryUnavailableBody':
        'Butlerly cannot prove a safe recovery state and no trustworthy safety copy is available. Normal editing remains paused. You can erase local Butlerly data and start again.',
    'recoverButlerly': 'Recover Butlerly',
    'eraseLocalRecoveryData': 'Erase local data and start over',
    'recoveryResetTitle': 'Erase local Butlerly data?',
    'recoveryResetBody':
        'This permanently deletes local Butlerly financial data, evidence, and recovery copies on this device. Use this only when recovery cannot be completed.',
    'recoveryResetConfirm': 'Erase and restart',
    'recoveryStillRequired':
        'Recovery is still required. Normal editing remains disabled and available recovery material has been preserved.',
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
        'Butlerly ha pausado la edición normal hasta validar el estado actual de restauración. Hay una copia de seguridad previa disponible si no es seguro conservar el estado actual.',
    'recoveryUnavailableBody':
        'Butlerly no puede demostrar un estado de recuperación seguro y no hay una copia de seguridad confiable disponible. La edición normal sigue pausada. Puede borrar los datos locales de Butlerly y comenzar de nuevo.',
    'recoverButlerly': 'Recuperar Butlerly',
    'eraseLocalRecoveryData': 'Borrar datos locales y empezar de nuevo',
    'recoveryResetTitle': '¿Borrar los datos locales de Butlerly?',
    'recoveryResetBody':
        'Esto elimina permanentemente los datos financieros locales de Butlerly, la evidencia y las copias de recuperación de este dispositivo. Úselo solo cuando no sea posible completar la recuperación.',
    'recoveryResetConfirm': 'Borrar y reiniciar',
    'recoveryStillRequired':
        'La recuperación sigue siendo necesaria. La edición normal continúa deshabilitada y se ha conservado el material de recuperación disponible.',
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
        'Butlerly 已暂停正常编辑，直到当前恢复状态通过验证。如果无法安全保留当前状态，可以使用恢复前的安全副本。',
    'recoveryUnavailableBody':
        'Butlerly 无法确认一个安全的恢复状态，并且没有可信的安全副本可用。正常编辑仍处于暂停状态。您可以清除本机 Butlerly 数据并重新开始。',
    'recoverButlerly': '恢复 Butlerly',
    'eraseLocalRecoveryData': '清除本地数据并重新开始',
    'recoveryResetTitle': '清除本机 Butlerly 数据？',
    'recoveryResetBody':
        '这将永久删除此设备上的 Butlerly 本地财务数据、凭证和恢复副本。仅在无法完成恢复时使用此操作。',
    'recoveryResetConfirm': '清除并重新开始',
    'recoveryStillRequired': '仍需要执行恢复。正常编辑仍未启用，可用的恢复材料已保留。',
  },
};
