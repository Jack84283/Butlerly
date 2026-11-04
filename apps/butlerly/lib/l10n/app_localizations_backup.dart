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
    'restoreMerge': 'Merge backup',
    'restoreReplace': 'Replace from backup',
    'mergeSubtitle':
        'Import missing records while keeping existing local records.',
    'mergeTitle': 'Merge Butlerly backup?',
    'mergeBody':
        'Records already on this device are kept. Missing records and available attachments from the backup are added. If identities or attachment paths cannot be merged safely, no changes are applied. Test with a separate backup of your current data.',
    'restoreSubtitle': 'Replace local data from an encrypted Butlerly backup.',
    'backupComplete': 'Encrypted backup created successfully.',
    'backupFailed': 'Backup could not be created.',
    'restoreFailed': 'Backup could not be restored.',
    'restoreFailureTitle': 'Unable to restore backup',
    'restoreFailureReasonLabel': 'Reason',
    'restoreFailureNextStepLabel': 'What to do next',
    'restoreFailureAuthenticationReason':
        'The backup could not be authenticated. An incorrect password and damaged encrypted data produce the same security check failure, so Butlerly cannot tell which occurred.',
    'restoreFailureAuthenticationAction':
        'Check the exact backup password, including capitalization. If it still fails, use another intact copy of the backup. Keep the original file.',
    'restoreFailureMissingPasswordReason':
        'No password was provided to unlock the encrypted backup.',
    'restoreFailureMissingPasswordAction':
        'Enter the password used when the backup was created and retry.',
    'restoreFailureUnsupportedFormatReason':
        'The selected file is not a supported encrypted raw Butlerly backup, or it uses an older archive format that this version cannot read.',
    'restoreFailureUnsupportedFormatAction':
        'Choose an encrypted raw backup created by a compatible Butlerly version. Do not rename or modify the original archive.',
    'restoreFailureDamagedReason':
        'The backup contents did not pass an archive checksum, data-integrity, or SQLite validation check. The extracted data cannot be trusted for restore.',
    'restoreFailureDamagedAction':
        'Try another intact backup. Keep the failed file for diagnosis; do not manually repair it or overwrite your current data.',
    'restoreFailureUnsupportedSchemaReason':
        'The backup has an invalid or unsupported SQLite schema. Butlerly cannot safely interpret its database structure.',
    'restoreFailureUnsupportedSchemaAction':
        'Use a compatible Butlerly build or a backup from a supported schema. Keep both the original backup and your current data.',
    'restoreFailureMigrationReason':
        'The backup uses an older database schema, but upgrading its temporary staging copy failed. The original archive was not modified.',
    'restoreFailureMigrationAction':
        'Do not retry with valuable data until the migration is fixed. Keep the archive and report the failure with the app version.',
    'restoreFailureMergeConflictReason':
        'Merge found incompatible tables, deletion tracking, records, or attachment identities. It stopped rather than silently overwriting local data.',
    'restoreFailureMergeConflictAction':
        'Keep both datasets and their backups. Resolve the incompatibility before retrying Merge; Replace is a separate destructive action.',
    'restoreFailureStorageReason':
        'The device does not have enough free storage to prepare a safe restore.',
    'restoreFailureStorageAction':
        'Free storage space without deleting Butlerly data or backups, then retry. Restore needs temporary space in addition to the backup file.',
    'restoreFailureFileAccessReason':
        'Butlerly could not read the selected file or access a required local staging location.',
    'restoreFailureFileAccessAction':
        'Check file availability and storage permissions. Copy the backup to an accessible local folder and retry without changing the original.',
    'restoreFailureDatabaseBusyReason':
        'The local SQLite database still has active readers, so the restore could not start safely.',
    'restoreFailureDatabaseBusyAction':
        'Close other Butlerly windows or operations and retry when the database is idle. Do not force-close during an active restore.',
    'restoreFailureRecoveryReason':
        'An earlier restore left a recovery state that must be resolved before another restore can proceed safely.',
    'restoreFailureRecoveryAction':
        'Preserve the existing recovery files and follow the in-app recovery instructions. Do not erase current data or rollback files.',
    'restoreFailureUnknownReason':
        'An unexpected error interrupted the restore. The available error information does not identify a reliable specific cause.',
    'restoreFailureUnknownAction':
        'Keep your current data and the original backup. Restart Butlerly and retry only after checking storage and app version; report repeated failures.',
    'upgradeAppRequiredTitle': 'Update Butlerly before restoring',
    'upgradeAppRequiredBody':
        'This backup requires database schema {backupVersion}, but your installed Butlerly supports schema {supportedVersion}. Nothing on this device was changed. Update Butlerly, then retry the same backup.',
    'upgradeFromAppleStore':
        'On iPhone or iPad, open the App Store and search for Butlerly. Choose Update if a newer official version is available. If you installed a test build, update it from its original source instead.',
    'upgradeFromGooglePlay':
        'On Android, open Google Play and search for Butlerly. Choose Update if a newer official version is available. If you installed a test build, update it from its original source instead.',
    'upgradeFromMacStore':
        'On Mac, check the Mac App Store for a Butlerly update if that is where you installed it. For a development or directly installed copy, install a newer compatible Butlerly build from its original source.',
    'upgradeFromDesktopDistribution':
        'Install a newer compatible Butlerly build from the same trusted source you used originally, then try Restore again.',
    'upgradeAppDismiss': 'OK',
    'unsupportedBackupSchema':
        'This backup uses a SQLite schema that this Butlerly version cannot restore. Your data has not been changed.',
    'restoreTitle': 'Restore Butlerly backup?',
    'backupCreatedAt': 'Created {date}',
    'newerData':
        'This device has newer local data. Replacing discards current Butlerly data and restores the backup exactly.',
    'noNewerData':
        'The backup is valid. Review the summary, then confirm replacement to restore it exactly.',
    'merge': 'Merge',
    'replace': 'Replace',
    'replaceTitle': 'Replace all Butlerly data?',
    'replaceBody':
        'This will replace the ENTIRE local Butlerly database with the backup, including:\n'
        '• Master data: categories, subcategories, merchants, payment sources, tags and translations\n'
        '• Transactions, payment settlements, imports and reconciliations\n'
        '• Analysis rules, findings, results and saved analysis data\n'
        '• Budgets, financial profiles and in-app preferences/settings\n'
        '• Local attachments, including receipts and statements (only files available in the backup)\n\n'
        'Any local data or attachments not present in this backup will be lost from Butlerly. This cannot be undone without a separate backup of your current data. Device/OS permissions and settings outside Butlerly are not restored.',
    'replaceAcknowledgement':
        'I understand that all current Butlerly database data and attachments will be replaced.',
    'replaceAllData': 'Replace all data',
    'restoreComplete': 'Restore completed.',
    'restoreResult': '{restored} restored',
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
    'encryptedBackupRequired':
        'Only encrypted Butlerly backups can be restored from this screen.',
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
    'recoveryEvidenceExport': 'Export preserved evidence',
    'recoveryEvidenceChooseLocation': 'Choose recovery folder',
    'recoveryEvidenceExported': 'Evidence recovery copy created',
    'recoveryEvidenceExportedBody':
        'The unresolved staged evidence was copied without changing the original recovery files. You can use this copy before choosing a destructive reset.',
    'portableRecoveryTitle': 'Backup recovery required',
    'portableRecoveryBody':
        'A backup replacement was interrupted. Butlerly preserved the previous valid backup, but needs access to the original backup location to finish recovery.',
    'selectBackupLocation': 'Select backup location',
    'keepRecoveryData': 'Keep recovery data',
    'portableRecoveryStillRequired':
        'Recovery could not be completed. The preserved recovery data was kept.',
  },
  'es': {
    'backup': 'Crear copia de Butlerly',
    'backupSubtitle': 'Crea un archivo de copia local portátil y cifrado.',
    'restoreBackup': 'Restaurar copia',
    'restoreMerge': 'Combinar copia de seguridad',
    'restoreReplace': 'Reemplazar desde una copia',
    'mergeSubtitle':
        'Importa registros faltantes y conserva los datos locales existentes.',
    'mergeTitle': '¿Combinar la copia de Butlerly?',
    'mergeBody':
        'Se conservarán los registros existentes en este dispositivo. Se añadirán los registros faltantes y los archivos disponibles de la copia. Si hay conflictos que no se pueden resolver con seguridad, no se aplicarán cambios. Cree otra copia de sus datos actuales antes de probar.',
    'restoreSubtitle':
        'Reemplaza los datos locales desde una copia cifrada de Butlerly.',
    'backupComplete': 'La copia cifrada se creó correctamente.',
    'backupFailed': 'No se pudo crear la copia.',
    'restoreFailed': 'No se pudo restaurar la copia.',
    'restoreFailureTitle': 'No se puede restaurar la copia',
    'restoreFailureReasonLabel': 'Motivo',
    'restoreFailureNextStepLabel': 'Qué hacer ahora',
    'restoreFailureAuthenticationReason':
        'No se pudo autenticar la copia. Una contraseña incorrecta y los datos cifrados dañados producen el mismo error de seguridad; Butlerly no puede distinguirlos.',
    'restoreFailureAuthenticationAction':
        'Comprueba la contraseña exacta de la copia, incluidas las mayúsculas. Si sigue fallando, prueba otra copia íntegra. Conserva el archivo original.',
    'restoreFailureMissingPasswordReason':
        'No se proporcionó la contraseña necesaria para desbloquear la copia cifrada.',
    'restoreFailureMissingPasswordAction':
        'Introduce la contraseña utilizada al crear la copia y vuelve a intentarlo.',
    'restoreFailureUnsupportedFormatReason':
        'El archivo seleccionado no es una copia cifrada compatible de Butlerly o utiliza un formato antiguo que esta versión no admite.',
    'restoreFailureUnsupportedFormatAction':
        'Selecciona una copia cifrada compatible creada por Butlerly. No cambies el nombre ni modifiques el archivo original.',
    'restoreFailureDamagedReason':
        'El contenido de la copia no superó una comprobación de integridad del archivo, de los datos o de SQLite. No es seguro restaurarlo.',
    'restoreFailureDamagedAction':
        'Prueba otra copia íntegra. Conserva el archivo fallido para analizarlo; no lo repares manualmente ni sobrescribas tus datos actuales.',
    'restoreFailureUnsupportedSchemaReason':
        'La copia contiene un esquema SQLite inválido o no compatible. Butlerly no puede interpretar su estructura de forma segura.',
    'restoreFailureUnsupportedSchemaAction':
        'Usa una versión compatible de Butlerly o una copia con un esquema admitido. Conserva la copia original y los datos actuales.',
    'restoreFailureMigrationReason':
        'La copia usa un esquema anterior, pero falló la actualización de la copia temporal. No se modificó el archivo original.',
    'restoreFailureMigrationAction':
        'No reintentes con datos valiosos hasta que se corrija la migración. Conserva la copia e informa del fallo y la versión de la app.',
    'restoreFailureMergeConflictReason':
        'La combinación encontró tablas, registros o archivos adjuntos incompatibles. Se detuvo para no sobrescribir silenciosamente los datos locales.',
    'restoreFailureMergeConflictAction':
        'Conserva ambos conjuntos de datos y sus copias. Resuelve la incompatibilidad antes de combinar; Reemplazar es otra operación destructiva.',
    'restoreFailureStorageReason':
        'El dispositivo no tiene espacio libre suficiente para preparar la restauración de forma segura.',
    'restoreFailureStorageAction':
        'Libera espacio sin borrar datos ni copias de Butlerly y vuelve a intentar. La restauración necesita espacio temporal adicional.',
    'restoreFailureFileAccessReason':
        'Butlerly no pudo leer el archivo seleccionado o acceder a una ubicación temporal necesaria.',
    'restoreFailureFileAccessAction':
        'Comprueba el archivo y los permisos de almacenamiento. Copia la copia de seguridad a una carpeta local accesible y reintenta.',
    'restoreFailureDatabaseBusyReason':
        'La base SQLite local sigue en uso y la restauración no pudo iniciarse de forma segura.',
    'restoreFailureDatabaseBusyAction':
        'Cierra otras ventanas u operaciones de Butlerly y vuelve a intentar cuando la base esté libre. No fuerces el cierre durante una restauración.',
    'restoreFailureRecoveryReason':
        'Una restauración anterior dejó un estado de recuperación que debe resolverse antes de continuar.',
    'restoreFailureRecoveryAction':
        'Conserva los archivos de recuperación y sigue las instrucciones de la app. No borres los datos ni las copias de reversión.',
    'restoreFailureUnknownReason':
        'Un error inesperado interrumpió la restauración. La información disponible no permite identificar una causa concreta.',
    'restoreFailureUnknownAction':
        'Conserva los datos actuales y la copia original. Reinicia Butlerly, revisa el almacenamiento y la versión, e informa si se repite.',
    'upgradeAppRequiredTitle': 'Actualiza Butlerly antes de restaurar',
    'upgradeAppRequiredBody':
        'Esta copia necesita el esquema de base de datos {backupVersion}, pero tu versión instalada de Butlerly admite hasta {supportedVersion}. Los datos de este dispositivo no se han modificado. Actualiza Butlerly e inténtalo de nuevo con la misma copia.',
    'upgradeFromAppleStore':
        'En iPhone o iPad, abre App Store y busca Butlerly. Pulsa Actualizar si hay una versión oficial más reciente. Si instalaste una versión de prueba, actualízala desde su origen original.',
    'upgradeFromGooglePlay':
        'En Android, abre Google Play y busca Butlerly. Pulsa Actualizar si hay una versión oficial más reciente. Si instalaste una versión de prueba, actualízala desde su origen original.',
    'upgradeFromMacStore':
        'En Mac, busca una actualización en Mac App Store si instalaste Butlerly allí. Para una versión de desarrollo o instalación directa, instala una versión compatible desde su origen original.',
    'upgradeFromDesktopDistribution':
        'Instala una versión compatible más reciente de Butlerly desde la misma fuente de confianza que usaste originalmente y vuelve a intentar la restauración.',
    'upgradeAppDismiss': 'Entendido',
    'unsupportedBackupSchema':
        'Esta copia usa un esquema SQLite que esta versión de Butlerly no puede restaurar. Sus datos no se han modificado.',
    'restoreTitle': '¿Restaurar la copia de Butlerly?',
    'backupCreatedAt': 'Creada el {date}',
    'newerData':
        'Este dispositivo tiene datos locales más recientes. Reemplazar descarta los datos actuales de Butlerly y restaura la copia exactamente.',
    'noNewerData':
        'La copia es válida. Revise el resumen y confirme el reemplazo para restaurarla exactamente.',
    'merge': 'Combinar',
    'replace': 'Reemplazar',
    'replaceTitle': '¿Reemplazar todos los datos de Butlerly?',
    'replaceBody':
        'Esto reemplazará TODA la base de datos local de Butlerly y sus tablas con la copia, incluidos:\n'
        '• Datos maestros: categorías, subcategorías, comercios, fuentes de pago, etiquetas y traducciones\n'
        '• Transacciones, liquidaciones, importaciones y conciliaciones\n'
        '• Reglas de análisis, hallazgos, resultados y análisis guardados\n'
        '• Presupuestos, perfiles financieros y preferencias de la aplicación\n'
        '• Archivos adjuntos, como recibos y extractos (solo los disponibles en la copia)\n\n'
        'Los datos y archivos locales ausentes de la copia se perderán de Butlerly. Esto no se puede deshacer sin otra copia de los datos actuales. No se restauran los permisos ni los ajustes del sistema operativo.',
    'replaceAcknowledgement':
        'Entiendo que se reemplazarán todos los datos y archivos adjuntos actuales de Butlerly.',
    'replaceAllData': 'Reemplazar todos los datos',
    'restoreComplete': 'Restauración completada.',
    'restoreResult': '{restored} restaurados',
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
    'encryptedBackupRequired':
        'Desde esta pantalla solo se pueden restaurar copias cifradas de Butlerly.',
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
    'recoveryEvidenceExport': 'Exportar la evidencia conservada',
    'recoveryEvidenceChooseLocation': 'Elegir carpeta de recuperación',
    'recoveryEvidenceExported':
        'Se creó una copia de recuperación de evidencia',
    'recoveryEvidenceExportedBody':
        'La evidencia pendiente se copió sin cambiar los archivos originales de recuperación. Puede usar esta copia antes de elegir un reinicio destructivo.',
    'portableRecoveryTitle': 'Se requiere recuperar la copia',
    'portableRecoveryBody':
        'Se interrumpió el reemplazo de una copia. Butlerly conservó la copia válida anterior, pero necesita acceso a la ubicación original para completar la recuperación.',
    'selectBackupLocation': 'Seleccionar ubicación de la copia',
    'keepRecoveryData': 'Conservar los datos de recuperación',
    'portableRecoveryStillRequired':
        'No se pudo completar la recuperación. Los datos de recuperación conservados permanecen disponibles.',
  },
  'zh': {
    'backup': '备份 Butlerly',
    'backupSubtitle': '创建一个加密且可跨设备使用的本地备份文件。',
    'restoreBackup': '恢复备份',
    'restoreMerge': '合并备份',
    'restoreReplace': '从备份替换',
    'mergeSubtitle': '导入缺失记录，同时保留本机已有记录。',
    'mergeTitle': '合并 Butlerly 备份？',
    'mergeBody':
        '本机已有的记录将保留，并导入备份中的缺失记录及可用附件。如存在无法安全合并的记录或附件路径冲突，则不会应用更改。测试前请另外备份当前数据。',
    'restoreSubtitle': '从加密的 Butlerly 备份替换本地数据。',
    'backupComplete': '加密备份创建成功。',
    'backupFailed': '无法创建备份。',
    'restoreFailed': '无法恢复备份。',
    'restoreFailureTitle': '无法恢复备份',
    'restoreFailureReasonLabel': '失败原因',
    'restoreFailureNextStepLabel': '下一步建议',
    'restoreFailureAuthenticationReason':
        '备份加密验证未通过。密码错误与加密文件损坏都会导致相同的验证失败，Butlerly 无法准确区分两者。',
    'restoreFailureAuthenticationAction':
        '核对创建备份时使用的密码，注意大小写。如仍失败，请尝试另一份完整的备份副本，并保留原始文件。',
    'restoreFailureMissingPasswordReason': '未提供解锁加密备份所需的密码。',
    'restoreFailureMissingPasswordAction': '请输入创建备份时使用的密码，然后重试。',
    'restoreFailureUnsupportedFormatReason':
        '所选文件不是当前支持的 Butlerly 加密原始备份，或使用了此版本无法读取的旧备份格式。',
    'restoreFailureUnsupportedFormatAction':
        '请选择兼容的 Butlerly 版本创建的加密原始备份。请勿重命名或修改原始备份文件。',
    'restoreFailureDamagedReason': '备份内容未通过归档校验和、数据完整性或 SQLite 数据库检查，无法安全用于恢复。',
    'restoreFailureDamagedAction': '请尝试另一份完整备份。保留失败文件用于排查，不要手动修复或覆盖当前数据。',
    'restoreFailureUnsupportedSchemaReason':
        '备份的 SQLite 数据库结构无效或不受支持，Butlerly 无法安全识别。',
    'restoreFailureUnsupportedSchemaAction':
        '请使用兼容的 Butlerly 版本或受支持结构的备份。保留原始备份与当前数据。',
    'restoreFailureMigrationReason': '备份使用较旧的数据库结构，但临时副本的结构迁移失败。原始备份文件未被修改。',
    'restoreFailureMigrationAction': '在修复迁移问题前，请勿对重要数据反复尝试。保留备份，并连同应用版本报告此问题。',
    'restoreFailureMergeConflictReason':
        '合并发现表结构、删除标记、记录或附件标识不兼容。为了防止覆盖本地数据，操作已停止。',
    'restoreFailureMergeConflictAction': '请保留双方数据及备份，解决冲突后再尝试合并。替换是独立的破坏性操作。',
    'restoreFailureStorageReason': '设备剩余存储空间不足，无法安全准备恢复操作。',
    'restoreFailureStorageAction': '请释放存储空间，但不要删除 Butlerly 数据或备份。恢复过程需要额外临时空间。',
    'restoreFailureFileAccessReason': 'Butlerly 无法读取所选文件，或无法访问所需的本地临时目录。',
    'restoreFailureFileAccessAction':
        '请检查文件是否可访问以及存储权限。将备份复制到可访问的本地目录后重试，勿修改原文件。',
    'restoreFailureDatabaseBusyReason': '本地 SQLite 数据库仍有活动读取连接，因此无法安全开始恢复。',
    'restoreFailureDatabaseBusyAction':
        '关闭其他 Butlerly 窗口或操作，待数据库空闲后重试。恢复进行中请勿强制退出。',
    'restoreFailureRecoveryReason': '先前恢复操作留下了需要处理的恢复状态，不能直接继续恢复。',
    'restoreFailureRecoveryAction': '请保留已有恢复文件，按照应用内恢复指引处理。不要删除当前数据或回滚文件。',
    'restoreFailureUnknownReason': '恢复过程中发生意外错误，现有信息不足以确定具体原因。',
    'restoreFailureUnknownAction':
        '请保留当前数据与原始备份。重启 Butlerly，确认存储空间和应用版本；如问题重复出现，请报告。',
    'upgradeAppRequiredTitle': '请先更新 Butlerly 再恢复备份',
    'upgradeAppRequiredBody':
        '此备份需要数据库结构版本 {backupVersion}，而当前安装的 Butlerly 仅支持到版本 {supportedVersion}。本机数据未被修改。请更新 Butlerly 后使用同一备份重试。',
    'upgradeFromAppleStore':
        '在 iPhone 或 iPad 上打开 App Store，搜索 Butlerly。如有较新的官方版本，点击“更新”。若使用的是测试版，请从原安装渠道更新。',
    'upgradeFromGooglePlay':
        '在 Android 设备上打开 Google Play，搜索 Butlerly。如有较新的官方版本，点击“更新”。若使用的是测试版，请从原安装渠道更新。',
    'upgradeFromMacStore':
        '在 Mac 上，如果 Butlerly 是通过 Mac App Store 安装的，请在其中检查更新；如果是开发版或直接安装的版本，请从原可信渠道安装支持该数据库结构的更新版本。',
    'upgradeFromDesktopDistribution':
        '请从原可信安装渠道获取支持该数据库结构的较新 Butlerly 版本，安装后重新尝试恢复。',
    'upgradeAppDismiss': '知道了',
    'unsupportedBackupSchema':
        '此备份使用当前 Butlerly 版本无法恢复的 SQLite 数据库结构。您的本机数据未被修改。',
    'restoreTitle': '恢复 Butlerly 备份？',
    'backupCreatedAt': '创建时间：{date}',
    'newerData': '此设备包含较新的本地数据。替换会丢弃当前 Butlerly 数据并准确恢复备份。',
    'noNewerData': '备份有效。请查看摘要，然后确认替换以准确恢复备份。',
    'merge': '合并',
    'replace': '替换',
    'replaceTitle': '替换全部 Butlerly 数据？',
    'replaceBody':
        '此操作将使用备份替换 Butlerly 的整个本地数据库及所有表，包括：\n'
        '• 基础数据：类别、子类别、商户、付款来源、标签和翻译\n'
        '• 交易、付款结算、导入及对账记录\n'
        '• 分析规则、发现、结果和已保存的分析数据\n'
        '• 预算、财务档案和应用内偏好设置\n'
        '• 本地附件（如收据和对账单，仅恢复备份中实际包含的文件）\n\n'
        '本机不在此备份中的数据及附件将从 Butlerly 中丢失。除非另有当前数据的备份，否则无法撤销。设备或操作系统级权限及设置不会恢复。',
    'replaceAcknowledgement': '我了解：当前 Butlerly 的全部数据库数据和附件将被替换。',
    'replaceAllData': '替换全部数据',
    'restoreComplete': '恢复完成。',
    'restoreResult': '已恢复 {restored} 条',
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
    'encryptedBackupRequired': '此页面只能恢复加密的 Butlerly 备份。',
    'recoveryRequiredTitle': 'Butlerly 需要恢复',
    'recoveryRequiredBody':
        'Butlerly 已暂停正常编辑，直到当前恢复状态通过验证。如果无法安全保留当前状态，可以使用恢复前的安全副本。',
    'recoveryUnavailableBody':
        'Butlerly 无法确认一个安全的恢复状态，并且没有可信的安全副本可用。正常编辑仍处于暂停状态。您可以清除本机 Butlerly 数据并重新开始。',
    'recoverButlerly': '恢复 Butlerly',
    'eraseLocalRecoveryData': '清除本地数据并重新开始',
    'recoveryResetTitle': '清除本机 Butlerly 数据？',
    'recoveryResetBody': '这将永久删除此设备上的 Butlerly 本地财务数据、凭证和恢复副本。仅在无法完成恢复时使用此操作。',
    'recoveryResetConfirm': '清除并重新开始',
    'recoveryStillRequired': '仍需要执行恢复。正常编辑仍未启用，可用的恢复材料已保留。',
    'recoveryEvidenceExport': '导出已保留的凭证',
    'recoveryEvidenceChooseLocation': '选择恢复文件夹',
    'recoveryEvidenceExported': '已创建凭证恢复副本',
    'recoveryEvidenceExportedBody': '未解决的暂存凭证已复制，原始恢复文件未被更改。您可以在选择清除数据前使用此副本。',
    'portableRecoveryTitle': '需要恢复备份',
    'portableRecoveryBody': '备份替换过程中断。Butlerly 已保留之前的有效备份，但需要访问原备份位置才能完成恢复。',
    'selectBackupLocation': '选择备份位置',
    'keepRecoveryData': '保留恢复数据',
    'portableRecoveryStillRequired': '无法完成恢复。已保留恢复数据。',
  },
};
