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
    'restoreSubtitle': 'Restore a Butlerly backup using Merge or Replace.',
    'backupComplete': 'Encrypted backup created successfully.',
    'backupCompleteWithWarnings':
        'Encrypted backup created with warnings. Open Data Integrity Reports for details.',
    'backupShareUnconfirmed':
        'The encrypted backup was created, but the platform could not confirm whether it was shared or saved.',
    'backupShareFailed':
        'The encrypted backup was created, but the share sheet could not be opened. No saved backup was confirmed.',
    'backupEncryptionFailed':
        'Backup encryption or verification failed. No backup was saved.',
    'backupRecoveryRequired':
        'Backup could not be finalized safely. Recovery is required; the destination file status is unknown. Open Backup recovery to continue.',
    'backupFailed': 'Backup could not be created.',
    'backupFailedWithDetails':
        'Backup could not be created. Failure stage: {stage}. Your financial data was not changed.',
    'backupLocationSelectionFailed': 'Backup location could not be selected.',
    'backupStorageFailed': 'Backup could not be saved to device storage.',
    'restoreFailed': 'Backup could not be restored.',
    'restoreFailedWithDetails':
        'Backup could not be restored. Failure stage: {stage}. No restore was confirmed.',
    'diagnosticAvailable': 'Backup or restore failure details are available.',
    'diagnosticTitle': 'Failure details',
    'viewDiagnostic': 'View details',
    'copyDiagnostic': 'Copy diagnostic',
    'dismissDiagnostic': 'Dismiss',
    'diagnosticCopied': 'Diagnostic copied.',
    'diagnosticPrimaryExplanation':
        'This diagnostic contains safe technical codes only. It does not include passwords, financial records, file paths, or exception text.',
    'diagnosticOperation': 'Operation',
    'diagnosticStage': 'Failure stage',
    'diagnosticErrorCode': 'Error category',
    'diagnosticErrorStorage': 'storage operation',
    'diagnosticErrorDatabase': 'database validation',
    'diagnosticErrorEncryption': 'encryption verification',
    'diagnosticErrorPassword': 'backup password or policy',
    'diagnosticErrorPublicationRecovery': 'publication recovery',
    'diagnosticErrorShare': 'sharing operation',
    'diagnosticErrorFormat': 'archive or data format',
    'diagnosticErrorInvalidArgument': 'invalid operation input',
    'diagnosticErrorRecovery': 'controlled recovery',
    'diagnosticErrorState': 'operation state',
    'diagnosticErrorUnknown': 'protected operation error',
    'diagnosticRestoreMode': 'Restore mode',
    'diagnosticRecoveryRequired': 'Recovery required',
    'diagnosticYes': 'Yes',
    'diagnosticNo': 'No',
    'diagnosticStageDestinationSelection': 'destination selection',
    'diagnosticStageDestinationStorage': 'destination storage',
    'diagnosticStageBackupEvidenceCollection': 'evidence collection',
    'diagnosticStageRestorePreflightSafetyBackupEvidenceCollection':
        'pre-restore safety backup: evidence collection',
    'diagnosticStageTemporaryStorage': 'temporary storage',
    'diagnosticStageTemporaryBackupCreation': 'temporary backup creation',
    'diagnosticStagePortableBackupCreation': 'portable backup creation',
    'diagnosticStageEncryptionVerification': 'encryption verification',
    'diagnosticStageShareSheet': 'share sheet',
    'diagnosticStagePublicationRecovery': 'publication recovery',
    'diagnosticStageRestoreFileSelection': 'restore file selection',
    'diagnosticStageRestorePassword': 'restore password',
    'diagnosticStageArchiveInspection': 'archive inspection',
    'diagnosticStageArchiveDecryption': 'archive decryption',
    'diagnosticStageRestoreActivation': 'restore activation',
    'diagnosticStageRestoreValidation': 'restore validation',
    'diagnosticStageUnknown': 'operation processing',
    'diagnosticExplanationEncryption':
        'The encrypted archive could not be verified. Try again and keep the app open until it finishes.',
    'diagnosticExplanationStorage':
        'Check the selected destination and available device storage, then try again.',
    'diagnosticExplanationShare':
        'The archive may exist only temporarily. Use the share sheet or create a desktop backup to a known destination.',
    'diagnosticExplanationPublicationRecovery':
        'The destination status is unknown. Use Backup recovery to verify it before trying again.',
    'diagnosticExplanationEvidenceCollection':
        'Backup could not collect all referenced evidence. Verify the evidence files and available device storage, then try again.',
    'diagnosticExplanationRestorePreflightEvidenceCollection':
        'Restore could not create its pre-restore safety copy because evidence collection failed. Verify the evidence files before retrying.',
    'diagnosticExplanationRestorePassword':
        'Check the password. If it is correct, the archive may be damaged or incomplete.',
    'diagnosticExplanationRestoreRecovery':
        'Restore entered a controlled recovery state. Follow the recovery screen before continuing.',
    'diagnosticExplanationRestore':
        'Restore did not report a committed result. Do not retry a destructive action until the recovery state is verified.',
    'diagnosticExplanationGeneric':
        'Review the operation details and try again. No private diagnostic payload is shown here.',
    'restoreTitle': 'Restore Butlerly backup?',
    'backupCreatedAt': 'Created {date}',
    'newerData':
        'This device has newer local data. Merge keeps applicable newer local data; Replace discards current data and restores the backup.',
    'noNewerData':
        'The backup is valid. Choose Merge to combine data or Replace to restore the backup as the current data.',
    'restoreMissingContentWarning':
        'This backup has {missing} missing optional item(s) and {warnings} integrity warning(s). Available records will be preserved; review Data Integrity Reports before choosing Replace.',
    'restoreIntegrityWarning':
        'This backup has {warnings} integrity warning(s). Review Data Integrity Reports before choosing Replace.',
    'merge': 'Merge',
    'replace': 'Replace',
    'replaceTitle': 'Replace current Butlerly data?',
    'replaceBody':
        'Current local Butlerly data will be replaced by the backup. This cannot be undone unless you have another backup.',
    'restoreComplete': 'Restore completed.',
    'restoreCompleteWithWarnings':
        'Restore completed with warnings. Open Data Integrity Reports for details.',
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
        'Only supported Butlerly backup files can be restored.',
    'legacyUnencryptedBackupWarning':
        'This older backup is not encrypted. Confirm that you trust its source before restoring. New Butlerly backups are encrypted.',
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
        'A backup replacement was interrupted. The destination file status is unknown. Re-select the original backup location to recover it, or continue with current data without deleting local financial data.',
    'selectBackupLocation': 'Select backup location',
    'keepRecoveryData': 'Keep recovery data',
    'continueWithLocalData': 'Continue with current data',
    'portableRecoveryStillRequired':
        'Recovery could not be completed. The destination and recovery artifacts still require verification.',
  },
  'es': {
    'backup': 'Crear copia de Butlerly',
    'backupSubtitle': 'Crea un archivo de copia local portátil y cifrado.',
    'restoreBackup': 'Restaurar copia',
    'restoreSubtitle':
        'Restaura una copia de Butlerly mediante Combinar o Reemplazar.',
    'backupComplete': 'La copia cifrada se creó correctamente.',
    'backupCompleteWithWarnings':
        'La copia cifrada se creó con advertencias. Abre los informes de integridad de datos para ver los detalles.',
    'backupShareUnconfirmed':
        'La copia cifrada se creó, pero la plataforma no pudo confirmar si se compartió o se guardó.',
    'backupShareFailed':
        'La copia cifrada se creó, pero no se pudo abrir la hoja para compartir. No se confirmó ninguna copia guardada.',
    'backupEncryptionFailed':
        'No se pudo cifrar o verificar la copia. No se guardó ninguna copia.',
    'backupRecoveryRequired':
        'No se pudo finalizar la copia de forma segura. Se requiere recuperación; se desconoce el estado del archivo de destino. Abre Recuperación de copias para continuar.',
    'backupFailed': 'No se pudo crear la copia.',
    'backupFailedWithDetails':
        'No se pudo crear la copia. Etapa del fallo: {stage}. No se modificaron sus datos financieros.',
    'backupLocationSelectionFailed':
        'No se pudo seleccionar la ubicación de la copia.',
    'backupStorageFailed':
        'No se pudo guardar la copia en el almacenamiento del dispositivo.',
    'restoreFailed': 'No se pudo restaurar la copia.',
    'restoreFailedWithDetails':
        'No se pudo restaurar la copia. Etapa del fallo: {stage}. No se confirmó ninguna restauración.',
    'diagnosticAvailable': 'Hay detalles del fallo de la copia o restauración.',
    'diagnosticTitle': 'Detalles del fallo',
    'viewDiagnostic': 'Ver detalles',
    'copyDiagnostic': 'Copiar diagnóstico',
    'dismissDiagnostic': 'Cerrar',
    'diagnosticCopied': 'Diagnóstico copiado.',
    'diagnosticPrimaryExplanation':
        'Este diagnóstico solo contiene códigos técnicos seguros. No incluye contraseñas, datos financieros, rutas de archivos ni texto de excepciones.',
    'diagnosticOperation': 'Operación',
    'diagnosticStage': 'Etapa del fallo',
    'diagnosticErrorCode': 'Categoría del error',
    'diagnosticErrorStorage': 'operación de almacenamiento',
    'diagnosticErrorDatabase': 'validación de la base de datos',
    'diagnosticErrorEncryption': 'verificación de cifrado',
    'diagnosticErrorPassword': 'contraseña o política de copia',
    'diagnosticErrorPublicationRecovery': 'recuperación de publicación',
    'diagnosticErrorShare': 'operación de uso compartido',
    'diagnosticErrorFormat': 'formato de archivo o datos',
    'diagnosticErrorInvalidArgument': 'entrada de operación no válida',
    'diagnosticErrorRecovery': 'recuperación controlada',
    'diagnosticErrorState': 'estado de la operación',
    'diagnosticErrorUnknown': 'error protegido de la operación',
    'diagnosticRestoreMode': 'Modo de restauración',
    'diagnosticRecoveryRequired': 'Recuperación necesaria',
    'diagnosticYes': 'Sí',
    'diagnosticNo': 'No',
    'diagnosticStageDestinationSelection': 'selección del destino',
    'diagnosticStageDestinationStorage': 'almacenamiento del destino',
    'diagnosticStageBackupEvidenceCollection': 'recopilación de evidencia',
    'diagnosticStageRestorePreflightSafetyBackupEvidenceCollection':
        'copia de seguridad previa a la restauración: recopilación de evidencia',
    'diagnosticStageTemporaryStorage': 'almacenamiento temporal',
    'diagnosticStageTemporaryBackupCreation': 'creación de copia temporal',
    'diagnosticStagePortableBackupCreation': 'creación de copia portátil',
    'diagnosticStageEncryptionVerification': 'verificación del cifrado',
    'diagnosticStageShareSheet': 'hoja para compartir',
    'diagnosticStagePublicationRecovery': 'recuperación de publicación',
    'diagnosticStageRestoreFileSelection':
        'selección del archivo de restauración',
    'diagnosticStageRestorePassword': 'contraseña de restauración',
    'diagnosticStageArchiveInspection': 'inspección del archivo',
    'diagnosticStageArchiveDecryption': 'descifrado del archivo',
    'diagnosticStageRestoreActivation': 'activación de la restauración',
    'diagnosticStageRestoreValidation': 'validación de la restauración',
    'diagnosticStageUnknown': 'procesamiento de la operación',
    'diagnosticExplanationEncryption':
        'No se pudo verificar el archivo cifrado. Vuelva a intentarlo y mantenga abierta la aplicación hasta que termine.',
    'diagnosticExplanationStorage':
        'Compruebe el destino seleccionado y el espacio disponible del dispositivo, y vuelva a intentarlo.',
    'diagnosticExplanationShare':
        'El archivo puede existir solo temporalmente. Use la hoja para compartir o cree una copia de escritorio en un destino conocido.',
    'diagnosticExplanationPublicationRecovery':
        'Se desconoce el estado del destino. Use Recuperación de copias para verificarlo antes de volver a intentarlo.',
    'diagnosticExplanationEvidenceCollection':
        'No se pudo recopilar toda la evidencia referenciada. Compruebe los archivos de evidencia y el espacio disponible, y vuelva a intentarlo.',
    'diagnosticExplanationRestorePreflightEvidenceCollection':
        'No se pudo crear la copia de seguridad previa a la restauración porque falló la recopilación de evidencia. Compruebe los archivos antes de volver a intentarlo.',
    'diagnosticExplanationRestorePassword':
        'Compruebe la contraseña. Si es correcta, el archivo puede estar dañado o incompleto.',
    'diagnosticExplanationRestoreRecovery':
        'La restauración entró en un estado de recuperación controlada. Siga la pantalla de recuperación antes de continuar.',
    'diagnosticExplanationRestore':
        'La restauración no confirmó un resultado guardado. No repita una acción destructiva hasta verificar el estado de recuperación.',
    'diagnosticExplanationGeneric':
        'Revise los detalles de la operación y vuelva a intentarlo. No se muestra aquí ninguna información privada del diagnóstico.',
    'restoreTitle': '¿Restaurar la copia de Butlerly?',
    'backupCreatedAt': 'Creada el {date}',
    'newerData':
        'Este dispositivo tiene datos locales más recientes. Combinar conserva los datos locales recientes aplicables; Reemplazar descarta los datos actuales y restaura la copia.',
    'noNewerData':
        'La copia es válida. Elija Combinar para unir los datos o Reemplazar para restaurar la copia como datos actuales.',
    'restoreMissingContentWarning':
        'Esta copia tiene {missing} elemento(s) opcional(es) ausente(s) y {warnings} advertencia(s) de integridad. Los registros disponibles se conservarán; revise los informes de integridad de datos antes de elegir Reemplazar.',
    'restoreIntegrityWarning':
        'Esta copia tiene {warnings} advertencia(s) de integridad. Revise los informes de integridad de datos antes de elegir Reemplazar.',
    'merge': 'Combinar',
    'replace': 'Reemplazar',
    'replaceTitle': '¿Reemplazar los datos actuales de Butlerly?',
    'replaceBody':
        'Los datos locales actuales de Butlerly serán reemplazados por la copia. No se puede deshacer salvo que tenga otra copia.',
    'restoreComplete': 'Restauración completada.',
    'restoreCompleteWithWarnings':
        'La restauración se completó con advertencias. Puede faltar contenido o no se pudieron reconstruir algunos análisis. Abre los informes de integridad de datos para ver los detalles.',
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
        'Solo se pueden restaurar archivos de copia de Butlerly compatibles.',
    'legacyUnencryptedBackupWarning':
        'Esta copia antigua no está cifrada. Compruebe que confía en su origen antes de restaurarla. Las copias nuevas de Butlerly están cifradas.',
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
        'Se interrumpió el reemplazo de una copia y se desconoce el estado del archivo de destino. Selecciona la ubicación original para recuperarlo o continúa con los datos actuales sin borrar los datos financieros locales.',
    'selectBackupLocation': 'Seleccionar ubicación de la copia',
    'keepRecoveryData': 'Conservar los datos de recuperación',
    'continueWithLocalData': 'Continuar con los datos actuales',
    'portableRecoveryStillRequired':
        'No se pudo completar la recuperación. El archivo de destino y los artefactos de recuperación aún deben verificarse.',
  },
  'zh': {
    'backup': '备份 Butlerly',
    'backupSubtitle': '创建一个加密且可跨设备使用的本地备份文件。',
    'restoreBackup': '恢复备份',
    'restoreSubtitle': '通过合并或替换恢复 Butlerly 备份。',
    'backupComplete': '加密备份创建成功。',
    'backupCompleteWithWarnings': '加密备份已创建，但存在警告。请打开数据完整性报告查看详情。',
    'backupShareUnconfirmed': '加密备份已创建，但平台无法确认是否已分享或保存。',
    'backupShareFailed': '加密备份已创建，但无法打开分享面板。未确认有已保存的备份。',
    'backupEncryptionFailed': '备份加密或验证失败。未保存备份。',
    'backupRecoveryRequired': '无法安全完成备份。需要恢复；无法确定目标文件的状态。请打开备份恢复以继续。',
    'backupFailed': '无法创建备份。',
    'backupFailedWithDetails': '无法创建备份。失败阶段：{stage}。您的财务数据未被修改。',
    'backupLocationSelectionFailed': '无法选择备份位置。',
    'backupStorageFailed': '无法将备份保存到设备存储。',
    'restoreFailed': '无法恢复备份。',
    'restoreFailedWithDetails': '无法恢复备份。失败阶段：{stage}。未确认完成任何恢复。',
    'diagnosticAvailable': '备份或恢复失败的详细信息可用。',
    'diagnosticTitle': '失败详情',
    'viewDiagnostic': '查看详情',
    'copyDiagnostic': '复制诊断信息',
    'dismissDiagnostic': '关闭',
    'diagnosticCopied': '诊断信息已复制。',
    'diagnosticPrimaryExplanation': '此诊断仅包含安全的技术代码，不包含密码、财务记录、文件路径或异常文本。',
    'diagnosticOperation': '操作',
    'diagnosticStage': '失败阶段',
    'diagnosticErrorCode': '错误类别',
    'diagnosticErrorStorage': '存储操作',
    'diagnosticErrorDatabase': '数据库验证',
    'diagnosticErrorEncryption': '加密验证',
    'diagnosticErrorPassword': '备份密码或策略',
    'diagnosticErrorPublicationRecovery': '发布恢复',
    'diagnosticErrorShare': '分享操作',
    'diagnosticErrorFormat': '备份或数据格式',
    'diagnosticErrorInvalidArgument': '操作输入无效',
    'diagnosticErrorRecovery': '受控恢复',
    'diagnosticErrorState': '操作状态',
    'diagnosticErrorUnknown': '受保护的操作错误',
    'diagnosticRestoreMode': '恢复模式',
    'diagnosticRecoveryRequired': '需要恢复',
    'diagnosticYes': '是',
    'diagnosticNo': '否',
    'diagnosticStageDestinationSelection': '选择目标位置',
    'diagnosticStageDestinationStorage': '目标存储',
    'diagnosticStageBackupEvidenceCollection': '证据收集',
    'diagnosticStageRestorePreflightSafetyBackupEvidenceCollection':
        '恢复前安全备份：证据收集',
    'diagnosticStageTemporaryStorage': '临时存储',
    'diagnosticStageTemporaryBackupCreation': '创建临时备份',
    'diagnosticStagePortableBackupCreation': '创建便携式备份',
    'diagnosticStageEncryptionVerification': '加密验证',
    'diagnosticStageShareSheet': '分享面板',
    'diagnosticStagePublicationRecovery': '发布恢复',
    'diagnosticStageRestoreFileSelection': '选择恢复文件',
    'diagnosticStageRestorePassword': '恢复密码',
    'diagnosticStageArchiveInspection': '检查备份文件',
    'diagnosticStageArchiveDecryption': '解密备份文件',
    'diagnosticStageRestoreActivation': '激活恢复',
    'diagnosticStageRestoreValidation': '恢复验证',
    'diagnosticStageUnknown': '处理操作',
    'diagnosticExplanationEncryption': '无法验证加密文件。请重试，并在完成前保持应用打开。',
    'diagnosticExplanationStorage': '请检查选择的目标位置和设备可用空间，然后重试。',
    'diagnosticExplanationShare': '备份文件可能只存在于临时位置。请使用分享面板，或在桌面设备上保存到已知位置。',
    'diagnosticExplanationPublicationRecovery': '无法确定目标文件状态。请先打开备份恢复进行验证，再重试。',
    'diagnosticExplanationEvidenceCollection':
        '无法收集所有引用的证据。请检查证据文件和设备可用空间，然后重试。',
    'diagnosticExplanationRestorePreflightEvidenceCollection':
        '由于证据收集失败，无法创建恢复前安全备份。请在重试前检查证据文件。',
    'diagnosticExplanationRestorePassword': '请检查密码。如果密码正确，备份文件可能已损坏或不完整。',
    'diagnosticExplanationRestoreRecovery': '恢复进入了受控恢复状态。请先按照恢复页面操作。',
    'diagnosticExplanationRestore': '恢复没有确认已提交结果。在验证恢复状态前，请勿重复破坏性操作。',
    'diagnosticExplanationGeneric': '请查看操作详情并重试。此处不会显示私密诊断内容。',
    'restoreTitle': '恢复 Butlerly 备份？',
    'backupCreatedAt': '创建时间：{date}',
    'newerData': '此设备包含较新的本地数据。合并会保留符合现有规则的较新本地数据；替换会丢弃当前数据并恢复备份。',
    'noNewerData': '备份有效。请选择合并以整合数据，或选择替换以备份内容作为当前数据。',
    'restoreMissingContentWarning':
        '此备份缺少 {missing} 项可选内容，并包含 {warnings} 条完整性警告。可用记录会被保留；选择替换前请查看数据完整性报告。',
    'restoreIntegrityWarning': '此备份包含 {warnings} 条完整性警告。选择替换前请查看数据完整性报告。',
    'merge': '合并',
    'replace': '替换',
    'replaceTitle': '替换当前 Butlerly 数据？',
    'replaceBody': '当前本地 Butlerly 数据将被备份替换。除非您还有其他备份，否则此操作无法撤销。',
    'restoreComplete': '恢复完成。',
    'restoreCompleteWithWarnings': '恢复已完成，但存在警告。请打开数据完整性报告查看详情。',
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
    'encryptedBackupRequired': '只能恢复受支持的 Butlerly 备份文件。',
    'legacyUnencryptedBackupWarning':
        '此旧版备份未加密。恢复前请确认文件来源可信。新版 Butlerly 备份均经过加密。',
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
    'portableRecoveryBody':
        '备份替换过程中断，无法确定目标文件的状态。请选择原备份位置进行恢复，或继续使用当前数据而不清除本地财务数据。',
    'selectBackupLocation': '选择备份位置',
    'keepRecoveryData': '保留恢复数据',
    'continueWithLocalData': '继续使用当前数据',
    'portableRecoveryStillRequired': '无法完成恢复。目标文件和恢复文件仍需验证。',
  },
};
