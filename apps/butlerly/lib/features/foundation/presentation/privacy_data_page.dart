import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/budgets/application/budget_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:share_plus/share_plus.dart' as share;

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
            final created = l10n.backupText('backupCreatedAt').replaceAll(
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
                      const SizedBox(height: ButlerlySpacing.standard),
                      Text(explanation),
                      if (replace) ...[
                        const SizedBox(height: ButlerlySpacing.small),
                        CheckboxListTile(
                          key: const ValueKey('restore-replace-acknowledgement'),
                          value: acknowledgedReplace,
                          onChanged: (value) => setSheetState(
                            () => acknowledgedReplace = value ?? false,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.backupText('replaceAcknowledgement')),
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

  bool get _usesNativeMobileShare =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

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

  Future<void> _restore(LocalRestoreMode mode) async {
    final selected = await openFile(acceptedTypeGroups: const [_backupType]);
    if (selected == null) return;

    final file = selected.path;
    final manager = services<WorkspaceDataService>();
    String? password;
    try {
      if (!await manager.isEncryptedBackup(file)) {
        if (mounted) {
          _message(context.l10n.backupText('encryptedBackupRequired'));
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
          notifyTransactionChanged();
          notifyBudgetsChanged();
        },
      );
      if (!mounted) return;
      final summary = context.l10n
          .backupText('restoreResult')
          .replaceAll('{restored}', '${result.restoredRows}');
      _message(
        '${context.l10n.backupText('restoreComplete')} $summary'
        '${result.presentationRefreshFailed ? ' ${context.l10n.text('restoreRefreshWarning')}' : ''}',
      );
    } on BackupPasswordOrIntegrityException {
      if (mounted) {
        _message(context.l10n.backupText('passwordOrIntegrityFailed'));
      }
    } on BackupPasswordRequiredException {
      if (mounted) {
        _message(context.l10n.backupText('passwordOrIntegrityFailed'));
      }
    } on NewerBackupSchemaException catch (error) {
      if (mounted) {
        await showBackupRequiresAppUpdateDialog(
          context,
          backupVersion: error.backupVersion,
          supportedVersion: error.supportedVersion,
        );
      }
    } on UnsupportedBackupSchemaException {
      if (mounted) {
        _message(context.l10n.backupText('unsupportedBackupSchema'));
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
      if (mounted) _message(context.l10n.text('eraseComplete'));
    } catch (_) {
      if (mounted) _message(context.l10n.text('eraseFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  Widget _desktopPrivacyPage(BuildContext context) {
    final l10n = context.l10n;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final backup = _DesktopPrivacyCard(
      key: const ValueKey('desktop-privacy-backup'),
      title: l10n.text('backupRecoveryTitle'),
      description: l10n.text('backupRecoveryBody'),
      icon: Icons.storage_outlined,
      children: [
        _DesktopPrivacyAction(
          icon: Icons.backup_outlined,
          label: l10n.backupText('backup'),
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
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: backup),
                    const SizedBox(width: ButlerlySpacing.small),
                    Expanded(child: export),
                  ],
                ),
                const SizedBox(height: ButlerlySpacing.small),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: management),
                    const SizedBox(width: ButlerlySpacing.small),
                    Expanded(child: danger),
                  ],
                ),
              ],
            );
          },
        ),
        if (_busy) const ButlerlyLoadingState(),
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
              title: Text(context.l10n.backupText('backup')),
              subtitle: Text(
                context.l10n.backupText('backupSubtitle'),
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
            if (_busy) const ButlerlyLoadingState(),
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
