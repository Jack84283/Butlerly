import 'dart:io';

import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/components/butlerly_toast.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/budgets/application/budget_change_notifier.dart';
import 'package:butlerly/core/application/backup_status_service.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart'
    show RepositoryException, RepositoryFailureCode;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart' as share;

/// User-facing failure classes, deliberately independent of exception text.
/// Authentication failure cannot cryptographically distinguish a wrong password
/// from modified ciphertext; never claim that either cause is proven.
@visibleForTesting
enum RestoreFailureKind {
  authentication,
  missingPassword,
  unsupportedFormat,
  damaged,
  unsupportedSchema,
  migration,
  mergeConflict,
  storage,
  fileAccess,
  databaseBusy,
  recovery,
  unknown,
}

@visibleForTesting
RestoreFailureKind classifyRestoreFailure(Object error) {
  if (error is BackupPasswordOrIntegrityException) {
    return RestoreFailureKind.authentication;
  }
  if (error is BackupPasswordRequiredException) {
    return RestoreFailureKind.missingPassword;
  }
  if (error is UnsupportedBackupSchemaException) {
    return RestoreFailureKind.unsupportedSchema;
  }
  if (error is RepositoryException) {
    return switch (error.code) {
      RepositoryFailureCode.migration => RestoreFailureKind.migration,
      RepositoryFailureCode.integrity => RestoreFailureKind.damaged,
      RepositoryFailureCode.storageFull => RestoreFailureKind.storage,
      RepositoryFailureCode.permission => RestoreFailureKind.fileAccess,
      RepositoryFailureCode.busy => RestoreFailureKind.databaseBusy,
      _ => RestoreFailureKind.unknown,
    };
  }
  if (error is FormatException) {
    final message = error.message.toLowerCase();
    if (message.contains('unsupported') && message.contains('format') ||
        message.contains('not an encrypted butlerly backup')) {
      return RestoreFailureKind.unsupportedFormat;
    }
    if (message.contains('cannot merge') ||
        message.contains('incompatible') ||
        message.contains('deletion tracking') ||
        message.contains('conflict') ||
        message.contains('cannot safely merge')) {
      return RestoreFailureKind.mergeConflict;
    }
    if (message.contains('migration') || message.contains('migrated')) {
      return RestoreFailureKind.migration;
    }
    return RestoreFailureKind.damaged;
  }
  if (error is FileSystemException) {
    if (error.osError?.errorCode == 28) {
      return RestoreFailureKind.storage;
    }
    return RestoreFailureKind.fileAccess;
  }
  if (error is StateError) {
    final message = error.message.toString().toLowerCase();
    if (message.contains('recovery') ||
        message.contains('previous restore') ||
        message.contains('previous sqlite sidecar')) {
      return RestoreFailureKind.recovery;
    }
    if (message.contains('active readers')) {
      return RestoreFailureKind.databaseBusy;
    }
  }
  return RestoreFailureKind.unknown;
}

String restoreFailureSuffix(RestoreFailureKind kind) {
  return switch (kind) {
    RestoreFailureKind.authentication => 'Authentication',
    RestoreFailureKind.missingPassword => 'MissingPassword',
    RestoreFailureKind.unsupportedFormat => 'UnsupportedFormat',
    RestoreFailureKind.damaged => 'Damaged',
    RestoreFailureKind.unsupportedSchema => 'UnsupportedSchema',
    RestoreFailureKind.migration => 'Migration',
    RestoreFailureKind.mergeConflict => 'MergeConflict',
    RestoreFailureKind.storage => 'Storage',
    RestoreFailureKind.fileAccess => 'FileAccess',
    RestoreFailureKind.databaseBusy => 'DatabaseBusy',
    RestoreFailureKind.recovery => 'Recovery',
    RestoreFailureKind.unknown => 'Unknown',
  };
}

/// Explain the specific known failure and a safe next step without exposing
/// encrypted paths, passwords, database rows or raw exception stack traces.
@visibleForTesting
Future<void> showBackupRestoreFailureDialog(
  BuildContext context, {
  required Object error,
}) async {
  final kind = classifyRestoreFailure(error);
  final suffix = restoreFailureSuffix(kind);
  await showButlerlyBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      return ButlerlySheet(
        title: Text(l10n.backupText('restoreFailureTitle')),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .55,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.backupText('restoreFailureReasonLabel'),
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                const SizedBox(height: ButlerlySpacing.small),
                Text(l10n.backupText('restoreFailure${suffix}Reason')),
                const SizedBox(height: ButlerlySpacing.standard),
                Text(
                  l10n.backupText('restoreFailureNextStepLabel'),
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                const SizedBox(height: ButlerlySpacing.small),
                Text(l10n.backupText('restoreFailure${suffix}Action')),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(l10n.backupText('upgradeAppDismiss')),
          ),
        ],
      );
    },
  );
}

/// Diagnostic categories for failed backup creation and publication.
@visibleForTesting
enum BackupFailureKind {
  passwordPolicy,
  databaseUnavailable,
  databaseBusy,
  databaseIntegrity,
  storageFull,
  fileAccess,
  evidence,
  evidenceChanged,
  verification,
  publication,
  publicationRecovery,
  shareFailure,
  unknown,
}

@visibleForTesting
BackupFailureKind classifyBackupFailure(Object error) {
  if (error is BackupPasswordTooShortException) {
    return BackupFailureKind.passwordPolicy;
  }
  if (error is BackupCreationException) {
    if (error.recoveryRequired) return BackupFailureKind.publicationRecovery;
    final cause = error.cause;
    if (cause is FileSystemException) {
      if (const {28, 112}.contains(cause.osError?.errorCode)) {
        return BackupFailureKind.storageFull;
      }
      return BackupFailureKind.fileAccess;
    }
    if (cause is RepositoryException) {
      return switch (cause.code) {
        RepositoryFailureCode.busy => BackupFailureKind.databaseBusy,
        RepositoryFailureCode.integrity => BackupFailureKind.databaseIntegrity,
        RepositoryFailureCode.storageFull => BackupFailureKind.storageFull,
        RepositoryFailureCode.permission => BackupFailureKind.fileAccess,
        RepositoryFailureCode.unavailable =>
          BackupFailureKind.databaseUnavailable,
        _ => BackupFailureKind.unknown,
      };
    }
    if (error.stage == BackupCreationStage.sharing) {
      return BackupFailureKind.shareFailure;
    }
    if (error.stage == BackupCreationStage.verification) {
      return BackupFailureKind.verification;
    }
    if (error.stage == BackupCreationStage.publication) {
      return BackupFailureKind.publication;
    }
    if (error.stage == BackupCreationStage.packaging ||
        error.stage == BackupCreationStage.inventory) {
      if (cause is StateError &&
          cause.message.toString().contains('changed during packaging')) {
        return BackupFailureKind.evidenceChanged;
      }
      return BackupFailureKind.evidence;
    }
    if (error.stage == BackupCreationStage.snapshot) {
      return BackupFailureKind.databaseUnavailable;
    }
    return BackupFailureKind.unknown;
  }
  if (error is FileSystemException) {
    return const {28, 112}.contains(error.osError?.errorCode)
        ? BackupFailureKind.storageFull
        : BackupFailureKind.fileAccess;
  }
  if (error is RepositoryException) {
    return switch (error.code) {
      RepositoryFailureCode.busy => BackupFailureKind.databaseBusy,
      RepositoryFailureCode.integrity => BackupFailureKind.databaseIntegrity,
      RepositoryFailureCode.storageFull => BackupFailureKind.storageFull,
      RepositoryFailureCode.permission => BackupFailureKind.fileAccess,
      _ => BackupFailureKind.databaseUnavailable,
    };
  }
  return BackupFailureKind.unknown;
}

String backupFailureSuffix(BackupFailureKind kind) {
  return switch (kind) {
    BackupFailureKind.passwordPolicy => 'PasswordPolicy',
    BackupFailureKind.databaseUnavailable => 'DatabaseUnavailable',
    BackupFailureKind.databaseBusy => 'DatabaseBusy',
    BackupFailureKind.databaseIntegrity => 'DatabaseIntegrity',
    BackupFailureKind.storageFull => 'StorageFull',
    BackupFailureKind.fileAccess => 'FileAccess',
    BackupFailureKind.evidence => 'Evidence',
    BackupFailureKind.evidenceChanged => 'EvidenceChanged',
    BackupFailureKind.verification => 'Verification',
    BackupFailureKind.publication => 'Publication',
    BackupFailureKind.publicationRecovery => 'PublicationRecovery',
    BackupFailureKind.shareFailure => 'ShareFailure',
    BackupFailureKind.unknown => 'Unknown',
  };
}

/// The archive may be safely verified but not yet published. Only the stage
/// and localized advice are shown, never raw exception text or private paths.
@visibleForTesting
Future<void> showBackupCreationFailureDialog(
  BuildContext context, {
  required Object error,
}) async {
  final kind = classifyBackupFailure(error);
  final suffix = backupFailureSuffix(kind);
  final stage = error is BackupCreationException ? error.stage : null;
  final stageKey = switch (stage) {
    BackupCreationStage.snapshot => 'backupStageSnapshot',
    BackupCreationStage.inventory => 'backupStageInventory',
    BackupCreationStage.packaging => 'backupStagePackaging',
    BackupCreationStage.encryption => 'backupStageEncryption',
    BackupCreationStage.verification => 'backupStageVerification',
    BackupCreationStage.publication => 'backupStagePublication',
    BackupCreationStage.sharing => 'backupStageSharing',
    null => null,
  };
  await showButlerlyBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      return ButlerlySheet(
        title: Text(l10n.backupText('backupFailureTitle')),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .55,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (stageKey != null) ...[
                  Text(
                    l10n.backupText('backupFailureStageLabel'),
                    style: Theme.of(sheetContext).textTheme.titleSmall,
                  ),
                  const SizedBox(height: ButlerlySpacing.small),
                  Text(l10n.backupText(stageKey)),
                  const SizedBox(height: ButlerlySpacing.standard),
                ],
                Text(
                  l10n.backupText('restoreFailureReasonLabel'),
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                const SizedBox(height: ButlerlySpacing.small),
                Text(l10n.backupText('backupFailure${suffix}Reason')),
                const SizedBox(height: ButlerlySpacing.standard),
                Text(
                  l10n.backupText('restoreFailureNextStepLabel'),
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                const SizedBox(height: ButlerlySpacing.small),
                Text(l10n.backupText('backupFailure${suffix}Action')),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(l10n.backupText('upgradeAppDismiss')),
          ),
        ],
      );
    },
  );
}

@visibleForTesting
Future<void> showBackupMissingEvidenceDialog(
  BuildContext context, {
  required int missingAttachmentCount,
}) => showButlerlyBottomSheet<void>(
  context: context,
  builder: (sheetContext) {
    final l10n = sheetContext.l10n;
    return ButlerlySheet(
      title: Text(l10n.backupText('backupMissingEvidenceTitle')),
      content: Text(
        l10n
            .backupText('backupMissingEvidenceBody')
            .replaceAll('{count}', '$missingAttachmentCount'),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(l10n.backupText('upgradeAppDismiss')),
        ),
      ],
    );
  },
);

class PrivacyDataPage extends ConsumerStatefulWidget {
  const PrivacyDataPage({this.shareClient, super.key});

  @visibleForTesting
  final share.SharePlus? shareClient;

  @override
  ConsumerState<PrivacyDataPage> createState() => _PrivacyDataPageState();
}

@visibleForTesting
String formatBackupInspectionDate(BuildContext context, DateTime date) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return DateFormat.yMMMd(locale).add_jm().format(date);
}

/// Explains how to install a Butlerly build capable of reading this backup.
///
/// No guessed app-store listing URLs are used. Store-specific instructions are
/// shown for mobile and macOS; sideloaded desktop/test builds are covered too.
@visibleForTesting
Future<void> showBackupRequiresAppUpdateDialog(
  BuildContext context, {
  required int backupVersion,
  required int supportedVersion,
}) async {
  final platform = Theme.of(context).platform;
  final instructionsKey = switch (platform) {
    TargetPlatform.iOS => 'upgradeFromAppleStore',
    TargetPlatform.android => 'upgradeFromGooglePlay',
    TargetPlatform.macOS => 'upgradeFromMacStore',
    _ => 'upgradeFromDesktopDistribution',
  };
  await showButlerlyBottomSheet<void>(
    context: context,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      final message = l10n
          .backupText('upgradeAppRequiredBody')
          .replaceAll('{backupVersion}', '$backupVersion')
          .replaceAll('{supportedVersion}', '$supportedVersion');
      return ButlerlySheet(
        title: Text(l10n.backupText('upgradeAppRequiredTitle')),
        content: Text('$message\\n\\n${l10n.backupText(instructionsKey)}'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(l10n.backupText('upgradeAppDismiss')),
          ),
        ],
      );
    },
  );
}

/// Requires explicit acknowledgement before replacing the entire local database.
/// Merge retains its separate, non-destructive confirmation.
@visibleForTesting
Future<bool> showBackupRestoreConfirmation(
  BuildContext context, {
  required BackupInspection inspection,
  required LocalRestoreMode mode,
}) async {
  final replace = mode == LocalRestoreMode.replace;
  var acknowledgedReplace = false;
  return (await showButlerlyBottomSheet<bool>(
        context: context,
        builder: (sheetContext) => StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final l10n = sheetContext.l10n;
            final summary = l10n
                .backupText('backupSummary')
                .replaceAll('{records}', '${inspection.recordCount}')
                .replaceAll('{evidence}', '${inspection.evidenceCount}');
            final created = l10n
                .backupText('backupCreatedAt')
                .replaceAll(
                  '{date}',
                  formatBackupInspectionDate(
                    sheetContext,
                    inspection.createdAtUtc.toLocal(),
                  ),
                );
            final explanation = l10n.backupText(
              replace ? 'replaceBody' : 'mergeBody',
            );
            return ButlerlySheet(
              title: Text(
                l10n.backupText(replace ? 'replaceTitle' : 'mergeTitle'),
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * .55,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$summary\n$created'),
                      if (inspection.hasMissingEvidence) ...[
                        const SizedBox(height: ButlerlySpacing.small),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 20),
                            const SizedBox(width: ButlerlySpacing.small),
                            Expanded(
                              child: Text(
                                l10n
                                    .backupText('restoreMissingEvidenceWarning')
                                    .replaceAll(
                                      '{count}',
                                      '${inspection.missingEvidenceCount}',
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: ButlerlySpacing.standard),
                      Text(explanation),
                      if (replace) ...[
                        const SizedBox(height: ButlerlySpacing.small),
                        CheckboxListTile(
                          key: const ValueKey(
                            'restore-replace-acknowledgement',
                          ),
                          value: acknowledgedReplace,
                          onChanged: (value) => setSheetState(
                            () => acknowledgedReplace = value ?? false,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            l10n.backupText('replaceAcknowledgement'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                ButlerlyCancelButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: Text(l10n.text('cancel')),
                ),
                if (replace)
                  ButlerlyDestructiveButton(
                    key: const ValueKey('restore-replace-confirm'),
                    onPressed: acknowledgedReplace
                        ? () => Navigator.pop(sheetContext, true)
                        : null,
                    child: Text(l10n.backupText('replaceAllData')),
                  )
                else
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    child: Text(l10n.backupText('merge')),
                  ),
              ],
            );
          },
        ),
      )) ==
      true;
}

class _PrivacyDataPageState extends ConsumerState<PrivacyDataPage> {
  static const _backupType = XTypeGroup(
    label: 'Butlerly backup',
    extensions: [
      PortableBackupPolicy.extension,
      PortableBackupPolicy.legacyExtension,
    ],
    uniformTypeIdentifiers: [PortableBackupPolicy.uniformTypeIdentifier],
  );

  bool _busy = false;
  final BackupStatusService _backupStatusStore =
      const LocalBackupStatusService();
  BackupStatusRecord? _lastCompletedBackup;

  @override
  void initState() {
    super.initState();
    _loadBackupStatus();
  }

  Future<void> _loadBackupStatus() async {
    if (kIsWeb) return;
    final result = await _backupStatusStore.read();
    if (mounted) setState(() => _lastCompletedBackup = result);
  }

  String _backupStatusDescription(BuildContext context) {
    final status = _lastCompletedBackup;
    if (status == null) return context.l10n.text('backupStatusUnknown');
    final time = DateFormat.yMMMd(
      Localizations.localeOf(context).toLanguageTag(),
    ).add_jm().format(status.completedAtUtc.toLocal());
    final description = context.l10n
        .text('backupStatusRecorded')
        .replaceAll('{date}', time);
    return status.missingAttachments
        ? '$description ${context.l10n.text('backupStatusMissingAttachments')}'
        : description;
  }

  Future<void> _recordCompletedBackup(BackupCreationResult backup) async {
    try {
      await _backupStatusStore.recordCompleted(
        missingAttachments: backup.hasMissingAttachments,
      );
      await _loadBackupStatus();
    } on Exception {
      // Backup creation succeeded even if optional status persistence fails.
      // Keep unknown status rather than presenting a false backup error.
    }
  }

  bool get _usesNativeMobileShare =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  void _successToast(String message) => ButlerlyToast.success(context, message);

  void _infoToast(String message) => ButlerlyToast.info(context, message);

  Future<void> _warnAboutMissingAttachments(BackupCreationResult backup) async {
    if (!mounted || !backup.hasMissingAttachments) return;
    _infoToast(
      context.l10n
          .backupText('backupMissingEvidenceToast')
          .replaceAll('{count}', '${backup.missingAttachmentCount}'),
    );
    await showBackupMissingEvidenceDialog(
      context,
      missingAttachmentCount: backup.missingAttachmentCount,
    );
  }

  void _backupErrorToast(Object error) {
    final l10n = context.l10n;
    final summary = l10n.backupText(
      'backupFailure${backupFailureSuffix(classifyBackupFailure(error))}Reason',
    );
    ButlerlyToast.error(
      context,
      summary,
      detailsLabel: l10n.backupText('toastDetails'),
      closeLabel: l10n.backupText('toastClose'),
      onDetails: () {
        if (mounted) {
          showBackupCreationFailureDialog(context, error: error);
        }
      },
    );
  }

  void _restoreErrorToast(Object error) {
    final l10n = context.l10n;
    final summary = error is NewerBackupSchemaException
        ? l10n
              .backupText('upgradeAppRequiredBody')
              .replaceAll('{backupVersion}', '${error.backupVersion}')
              .replaceAll('{supportedVersion}', '${error.supportedVersion}')
        : l10n.backupText(
            'restoreFailure${restoreFailureSuffix(classifyRestoreFailure(error))}Reason',
          );
    ButlerlyToast.error(
      context,
      summary,
      detailsLabel: l10n.backupText('toastDetails'),
      closeLabel: l10n.backupText('toastClose'),
      onDetails: () {
        if (!mounted) return;
        if (error is NewerBackupSchemaException) {
          showBackupRequiresAppUpdateDialog(
            context,
            backupVersion: error.backupVersion,
            supportedVersion: error.supportedVersion,
          );
        } else {
          showBackupRestoreFailureDialog(context, error: error);
        }
      },
    );
  }

  void _otherErrorToast(String message, String advice) {
    final l10n = context.l10n;
    ButlerlyToast.error(
      context,
      message,
      detailsLabel: l10n.backupText('toastDetails'),
      closeLabel: l10n.backupText('toastClose'),
      onDetails: () {
        if (!mounted) return;
        showButlerlyBottomSheet<void>(
          context: context,
          builder: (sheetContext) => ButlerlySheet(
            title: Text(message),
            content: Text(advice),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(sheetContext.l10n.backupText('toastClose')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _backup() async {
    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      ':',
      '-',
    );
    final fileName =
        'Butlerly Backup $timestamp.${PortableBackupPolicy.extension}';

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
      final backup = await services<WorkspaceDataService>()
          .createPortableBackup(location.path, password: password);
      if (mounted) {
        await _recordCompletedBackup(backup);
        if (!mounted) return;
        if (backup.hasMissingAttachments) {
          await _warnAboutMissingAttachments(backup);
        } else {
          _successToast(context.l10n.backupText('backupSavedVerified'));
        }
      }
    } catch (error) {
      if (mounted) {
        _backupErrorToast(error);
      }
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
    var sharingStarted = false;
    try {
      final temporary = await services<WorkspaceDataService>()
          .createTemporaryBackup(fileName, password: password);
      filePath = temporary.filePath;
      if (!mounted) return;

      final renderBox = context.findRenderObject();
      final shareOrigin = renderBox is RenderBox
          ? renderBox.localToGlobal(Offset.zero) & renderBox.size
          : null;
      sharingStarted = true;
      final result = await (widget.shareClient ?? share.SharePlus.instance)
          .share(
            share.ShareParams(
              files: [
                share.XFile(filePath, mimeType: PortableBackupPolicy.mimeType),
              ],
              title: fileName,
              sharePositionOrigin: shareOrigin,
            ),
          );
      if (mounted && result.status == share.ShareResultStatus.success) {
        await _recordCompletedBackup(temporary.backup);
        if (!mounted) return;
        if (temporary.backup.hasMissingAttachments) {
          await _warnAboutMissingAttachments(temporary.backup);
        } else {
          _successToast(context.l10n.backupText('backupSharedVerified'));
        }
      } else if (mounted &&
          result.status == share.ShareResultStatus.dismissed) {
        _infoToast(context.l10n.backupText('backupShareDismissed'));
      } else if (mounted) {
        _backupErrorToast(
          BackupCreationException(
            stage: BackupCreationStage.sharing,
            cause: StateError('Share operation did not complete.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _backupErrorToast(
          sharingStarted
              ? BackupCreationException(
                  stage: BackupCreationStage.sharing,
                  cause: error,
                )
              : error,
        );
      }
    } finally {
      if (filePath != null) {
        await services<WorkspaceDataService>().discardTemporaryBackup(filePath);
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore(LocalRestoreMode mode) async {
    final selected = await openFile(acceptedTypeGroups: const [_backupType]);
    if (selected == null) return;

    final file = selected.path;
    final manager = services<WorkspaceDataService>();
    String? password;
    try {
      if (!await manager.isEncryptedBackup(file)) {
        if (mounted) {
          _restoreErrorToast(
            const FormatException('Not an encrypted Butlerly backup.'),
          );
        }
        return;
      }
      if (!mounted) return;
      password = await _requestRestorePassword();
      if (password == null || !mounted) return;

      setState(() => _busy = true);
      final inspection = await manager.inspect(file, password: password);
      if (!mounted) return;
      setState(() => _busy = false);
      if (!await _confirmRestore(inspection, mode)) return;
      if (!mounted) return;
      setState(() => _busy = true);
      final result = await manager.restore(
        file,
        mode: mode,
        password: password,
        refreshPresentation: () async {
          ref.invalidate(userPreferenceProvider);
          notifyWorkspaceRestored();
          notifyBudgetsChanged();
        },
      );
      if (!mounted) return;
      final summary =
          (mode == LocalRestoreMode.merge
                  ? context.l10n.backupText('mergeResult')
                  : context.l10n.backupText('restoreResult'))
              .replaceAll('{restored}', '${result.restoredRows}')
              .replaceAll('{kept}', '${result.keptNewerLocalRows}');
      _successToast(
        '${context.l10n.backupText('restoreComplete')} $summary'
        '${result.presentationRefreshFailed ? ' ${context.l10n.text('restoreRefreshWarning')}' : ''}',
      );
    } on NewerBackupSchemaException catch (error) {
      if (mounted) {
        _restoreErrorToast(error);
      }
    } on RestoreRecoveryRequiredException {
      // RestoreRecoveryState immediately replaces normal navigation with the
      // recovery-only surface. Do not add a competing generic dialog here.
    } catch (error) {
      if (mounted) {
        _restoreErrorToast(error);
      }
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
              ButlerlyCancelButton(
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
      // The modal future completes as soon as the route is popped, while its
      // reverse animation can still rebuild the TextField.
      await Future<void>.delayed(const Duration(milliseconds: 300));
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
            ButlerlyCancelButton(
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
      // Keep the controller alive through the sheet's reverse animation.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      password.dispose();
    }
  }

  Future<bool> _confirmRestore(
    BackupInspection inspection,
    LocalRestoreMode mode,
  ) => showBackupRestoreConfirmation(
    context,
    inspection: inspection,
    mode: mode,
  );

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
      if (mounted) {
        _otherErrorToast(
          context.l10n.text('exportFailed'),
          context.l10n.backupText('toastExportFailedDetails'),
        );
      }
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
          ButlerlyCancelButton(
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
      if (mounted) _successToast(context.l10n.text('eraseComplete'));
    } catch (_) {
      if (mounted) {
        _otherErrorToast(
          context.l10n.text('eraseFailed'),
          context.l10n.backupText('toastEraseFailedDetails'),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _desktopPrivacyPage(BuildContext context) {
    final l10n = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final backup = _DesktopPrivacyCard(
      key: const ValueKey('desktop-privacy-backup'),
      title: l10n.text('backupRecoveryTitle'),
      description:
          '${l10n.text('backupRecoveryBody')}\n'
          '${_backupStatusDescription(context)}',
      icon: Icons.storage_outlined,
      children: [
        _DesktopPrivacyAction(
          icon: Icons.backup_outlined,
          label: l10n.text('backUpNowAction'),
          description: l10n.backupText('backupSubtitle'),
          onTap: _busy ? null : _backup,
        ),
        _DesktopPrivacyAction(
          key: const ValueKey('desktop-privacy-restore-merge'),
          icon: Icons.merge_type_outlined,
          label: l10n.backupText('restoreMerge'),
          description: l10n.backupText('mergeSubtitle'),
          onTap: _busy ? null : () => _restore(LocalRestoreMode.merge),
        ),
        _DesktopPrivacyAction(
          key: const ValueKey('desktop-privacy-restore-replace'),
          icon: Icons.restore_outlined,
          label: l10n.backupText('restoreReplace'),
          description: l10n.backupText('restoreSubtitle'),
          onTap: _busy ? null : () => _restore(LocalRestoreMode.replace),
        ),
      ],
    );
    final export = _DesktopPrivacyCard(
      key: const ValueKey('desktop-privacy-export'),
      title: l10n.text('dataExportTitle'),
      description: l10n.text('dataExportBody'),
      icon: Icons.file_download_outlined,
      children: [
        _DesktopPrivacyAction(
          icon: Icons.download_outlined,
          label: l10n.text('exportToFile'),
          description: l10n.text('exportScopeBody'),
          onTap: _busy ? null : _export,
        ),
      ],
    );
    final management = _DesktopPrivacyCard(
      key: const ValueKey('desktop-privacy-management'),
      title: l10n.text('dataManagementTitle'),
      description: l10n.text('dataManagementBody'),
      icon: Icons.settings_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: ButlerlySpacing.standard,
          ),
          child: Text(
            l10n.text('privacyScopeBody'),
            style: _subtitleStyle(context),
          ),
        ),
      ],
    );
    final danger = _DesktopPrivacyCard(
      key: const ValueKey('desktop-privacy-danger'),
      title: l10n.text('dangerZoneTitle'),
      description: l10n.text('dangerZoneBody'),
      icon: Icons.warning_amber_rounded,
      danger: true,
      children: [
        _DesktopPrivacyAction(
          icon: Icons.delete_forever_outlined,
          label: l10n.text('resetAllData'),
          description: l10n.text('eraseScopeBody'),
          danger: true,
          onTap: _busy ? null : _confirmErase,
        ),
      ],
    );
    return ButlerlyPage(
      title: l10n.text('privacyAndData'),
      subtitle: l10n.text('desktopPrivacySubtitle'),
      fullWidth: true,
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () =>
            context.canPop() ? context.pop() : context.go('/settings'),
      ),
      children: [
        Container(
          key: const ValueKey('desktop-privacy-local-banner'),
          padding: const EdgeInsets.all(ButlerlySpacing.standard),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF1E342B) : const Color(0xFFE5F7ED),
            border: Border.all(
              color: dark ? const Color(0xFF2A4438) : const Color(0xFFCBE6D7),
            ),
            borderRadius: BorderRadius.circular(ButlerlyRadius.card),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundColor: dark
                    ? const Color(0xFF2E875C)
                    : const Color(0xFFB6E9CD),
                child: Icon(
                  Icons.shield_outlined,
                  color: context.colors.success,
                ),
              ),
              const SizedBox(width: ButlerlySpacing.standard),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.text('desktopLocalWorkspace'),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      l10n.text('desktopPrivacyBannerBody'),
                      style: _subtitleStyle(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: ButlerlySpacing.standard),
              Icon(Icons.check_circle_rounded, color: context.colors.success),
            ],
          ),
        ),
        const SizedBox(height: ButlerlySpacing.standard),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 650) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  backup,
                  const SizedBox(height: ButlerlySpacing.small),
                  export,
                  const SizedBox(height: ButlerlySpacing.small),
                  management,
                  const SizedBox(height: ButlerlySpacing.small),
                  danger,
                ],
              );
            }
            // Independent columns give each card its natural height.
            // Unlike two horizontal rows, this leaves no empty row-sized gap
            // beneath a shorter card when localized descriptions wrap.
            return Row(
              key: const ValueKey('desktop-privacy-waterfall'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    key: const ValueKey('desktop-privacy-left-column'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      backup,
                      const SizedBox(height: ButlerlySpacing.small),
                      management,
                    ],
                  ),
                ),
                const SizedBox(width: ButlerlySpacing.small),
                Expanded(
                  child: Column(
                    key: const ValueKey('desktop-privacy-right-column'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      export,
                      const SizedBox(height: ButlerlySpacing.small),
                      danger,
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        if (_busy)
          const KeyedSubtree(
            key: ValueKey('privacy-restore-busy'),
            child: ButlerlyLoadingState(),
          ),
        const SizedBox(height: ButlerlySpacing.section),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (effectiveButlerlyLayoutMode(
          context,
          MediaQuery.sizeOf(context).width,
        ) ==
        ButlerlyLayoutMode.wide) {
      return _desktopPrivacyPage(context);
    }
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/settings'),
        ),
        title: Text(context.l10n.text('privacyAndData')),
        actions: const [ButlerlyContextHelpButton(articleId: 'ch-20')],
      ),
      body: ButlerlyResponsiveBody(
        contentKey: const ValueKey('privacy-data-content'),
        child: ListView(
          padding: const EdgeInsets.all(ButlerlySpacing.standard),
          children: [
            ButlerlyCard(child: Text(context.l10n.text('privacyScopeBody'))),
            ButlerlySectionHeader(
              title: context.l10n.text('localDataControls'),
            ),
            ListTile(
              enabled: !_busy,
              leading: Icon(_privacyIcon(context, Icons.backup_outlined)),
              title: Text(context.l10n.text('backUpNowAction')),
              subtitle: Text(
                _backupStatusDescription(context),
                style: _subtitleStyle(context),
              ),
              trailing: Icon(_privacyIcon(context, Icons.chevron_right)),
              onTap: _backup,
            ),
            const Divider(),
            ListTile(
              key: const ValueKey('mobile-privacy-restore-merge'),
              enabled: !_busy,
              leading: Icon(_privacyIcon(context, Icons.merge_type_outlined)),
              title: Text(context.l10n.backupText('restoreMerge')),
              subtitle: Text(
                context.l10n.backupText('mergeSubtitle'),
                style: _subtitleStyle(context),
              ),
              trailing: Icon(_privacyIcon(context, Icons.chevron_right)),
              onTap: () => _restore(LocalRestoreMode.merge),
            ),
            const Divider(),
            ListTile(
              key: const ValueKey('mobile-privacy-restore-replace'),
              enabled: !_busy,
              leading: Icon(_privacyIcon(context, Icons.restore_outlined)),
              title: Text(context.l10n.backupText('restoreReplace')),
              subtitle: Text(
                context.l10n.backupText('restoreSubtitle'),
                style: _subtitleStyle(context),
              ),
              trailing: Icon(_privacyIcon(context, Icons.chevron_right)),
              onTap: () => _restore(LocalRestoreMode.replace),
            ),
            const Divider(),
            ListTile(
              enabled: !_busy,
              leading: Icon(_privacyIcon(context, Icons.download_outlined)),
              title: Text(context.l10n.text('exportToFile')),
              subtitle: Text(
                context.l10n.text('exportScopeBody'),
                style: _subtitleStyle(context),
              ),
              trailing: Icon(_privacyIcon(context, Icons.chevron_right)),
              onTap: _export,
            ),
            const Divider(),
            ListTile(
              enabled: !_busy,
              leading: Icon(
                _privacyIcon(context, Icons.delete_forever_outlined),
              ),
              title: Text(context.l10n.text('resetAllData')),
              subtitle: Text(
                context.l10n.text('eraseScopeBody'),
                style: _subtitleStyle(context),
              ),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: _confirmErase,
            ),
            if (_busy)
              const KeyedSubtree(
                key: ValueKey('privacy-restore-busy'),
                child: ButlerlyLoadingState(),
              ),
          ],
        ),
      ),
    );
  }
}

class _DesktopPrivacyCard extends StatelessWidget {
  const _DesktopPrivacyCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.children,
    this.danger = false,
    super.key,
  });

  final String title;
  final String description;
  final IconData icon;
  final List<Widget> children;
  final bool danger;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    padding: const EdgeInsets.all(ButlerlySpacing.standard),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 24,
              color: danger
                  ? Theme.of(context).colorScheme.error
                  : context.colors.primaryText,
            ),
            const SizedBox(width: ButlerlySpacing.standard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: danger
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                  const SizedBox(height: ButlerlySpacing.xxs),
                  Text(description, style: _subtitleStyle(context)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: ButlerlySpacing.small),
        Divider(height: 1, thickness: 1, color: context.colors.cardDivider),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(height: 1, thickness: 1, color: context.colors.cardDivider),
          children[i],
        ],
      ],
    ),
  );
}

class _DesktopPrivacyAction extends StatelessWidget {
  const _DesktopPrivacyAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ButlerlySpacing.micro,
          vertical: ButlerlySpacing.small,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: danger
                  ? Theme.of(context).colorScheme.error
                  : context.colors.secondaryText,
            ),
            const SizedBox(width: ButlerlySpacing.standard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: danger
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                  const SizedBox(height: ButlerlySpacing.xxs),
                  Text(description, style: _subtitleStyle(context)),
                ],
              ),
            ),
            const SizedBox(width: ButlerlySpacing.compact),
            Icon(
              Icons.chevron_right_rounded,
              color: context.colors.tertiaryText,
              size: 18,
            ),
          ],
        ),
      ),
    ),
  );
}

TextStyle? _subtitleStyle(BuildContext context) => Theme.of(
  context,
).textTheme.bodySmall?.copyWith(color: context.colors.secondaryText);

IconData _privacyIcon(BuildContext context, IconData material) {
  if (kIsWeb || Theme.of(context).platform != TargetPlatform.iOS) {
    return material;
  }
  return switch (material) {
    Icons.backup_outlined => CupertinoIcons.archivebox,
    Icons.restore_outlined => CupertinoIcons.arrow_counterclockwise,
    Icons.download_outlined => CupertinoIcons.arrow_down_doc,
    Icons.delete_forever_outlined => CupertinoIcons.trash,
    Icons.chevron_right => CupertinoIcons.chevron_right,
    _ => material,
  };
}
