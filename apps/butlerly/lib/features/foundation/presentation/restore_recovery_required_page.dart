import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/core/application/restore_recovery_status.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recovery-only surface shown when Butlerly cannot yet prove one coherent
/// database/evidence/runtime state.
class RestoreRecoveryRequiredPage extends ConsumerStatefulWidget {
  const RestoreRecoveryRequiredPage({this.copyDiagnostic, super.key});

  @visibleForTesting
  final Future<void> Function(String diagnostic)? copyDiagnostic;

  @override
  ConsumerState<RestoreRecoveryRequiredPage> createState() =>
      _RestoreRecoveryRequiredPageState();
}

class _RestoreRecoveryRequiredPageState
    extends ConsumerState<RestoreRecoveryRequiredPage> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _refreshRuntime() async {
    ref.invalidate(userPreferenceProvider);
    notifyTransactionChanged();
  }

  Future<void> _recover() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await services<WorkspaceDataService>().recoverControlledState(
        refreshPresentation: _refreshRuntime,
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetLocalData() async {
    final confirmed = await showButlerlyConfirmationSheet(
      context: context,
      title: context.l10n.backupText('recoveryResetTitle'),
      message: context.l10n.backupText('recoveryResetBody'),
      cancelLabel: context.l10n.text('cancel'),
      confirmLabel: context.l10n.backupText('recoveryResetConfirm'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await services<WorkspaceDataService>().resetControlledRecovery(
        refreshPresentation: _refreshRuntime,
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _stageLabel(
    BuildContext context,
    RestoreRecoveryDiagnostic diagnostic,
  ) => context.l10n.backupText(switch (diagnostic.stageCode) {
    'restore_activation' => 'diagnosticStageRestoreActivation',
    'restore_validation' => 'diagnosticStageRestoreValidation',
    _ => 'diagnosticStageUnknown',
  });

  String _errorLabel(
    BuildContext context,
    RestoreRecoveryDiagnostic diagnostic,
  ) => context.l10n.backupText(switch (diagnostic.errorCode) {
    'backup_encryption_verification' => 'diagnosticErrorEncryption',
    'backup_password_policy' ||
    'restore_password_or_integrity' ||
    'restore_password_required' => 'diagnosticErrorPassword',
    'backup_publication_recovery_required' =>
      'diagnosticErrorPublicationRecovery',
    'backup_storage' || 'filesystem' => 'diagnosticErrorStorage',
    'database' => 'diagnosticErrorDatabase',
    'format' => 'diagnosticErrorFormat',
    'invalid_argument' => 'diagnosticErrorInvalidArgument',
    'restore_recovery_required' => 'diagnosticErrorRecovery',
    'state' => 'diagnosticErrorState',
    _ => 'diagnosticErrorUnknown',
  });

  String _diagnosticText(RestoreRecoveryDiagnostic diagnostic) =>
      'operation=restore\n'
      'stage_code=${diagnostic.stageCode}\n'
      'error_code=${diagnostic.errorCode}\n'
      'recovery_required=true';

  Future<void> _copyDiagnostic(RestoreRecoveryDiagnostic diagnostic) async {
    final text = _diagnosticText(diagnostic);
    final copy = widget.copyDiagnostic;
    if (copy == null) {
      await Clipboard.setData(ClipboardData(text: text));
    } else {
      await copy(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manager = services<WorkspaceDataService>();
    final hasSafetyCopy = manager.hasRecoverySafetyCopy;
    final recoveryState = services.isRegistered<RestoreRecoveryStatus>()
        ? services<RestoreRecoveryStatus>()
        : null;
    final diagnostic = recoveryState?.diagnostic;

    return Scaffold(
      body: SafeArea(
        child: ButlerlyResponsiveBody(
          contentKey: const ValueKey('restore-recovery-required-content'),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: ButlerlySize.contentGutter,
              vertical: ButlerlySpacing.section,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.health_and_safety_outlined,
                      size: 52,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context.l10n.backupText('recoveryRequiredTitle'),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.backupText(
                        hasSafetyCopy
                            ? 'recoveryRequiredBody'
                            : 'recoveryUnavailableBody',
                      ),
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    if (diagnostic != null) ...[
                      const SizedBox(height: 20),
                      Card(
                        key: const ValueKey('restore-recovery-diagnostic'),
                        child: Padding(
                          padding: const EdgeInsets.all(
                            ButlerlySpacing.standard,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${context.l10n.backupText('diagnosticStage')}: '
                                '${_stageLabel(context, diagnostic)}',
                              ),
                              Text(
                                '${context.l10n.backupText('diagnosticErrorCode')}: '
                                '${_errorLabel(context, diagnostic)}',
                              ),
                              const SizedBox(height: 8),
                              Text(
                                context.l10n.backupText(
                                  'diagnosticExplanationRestoreRecovery',
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _copyDiagnostic(diagnostic),
                                  child: Text(
                                    context.l10n.backupText('copyDiagnostic'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_failed) ...[
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.backupText('recoveryStillRequired'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    if (hasSafetyCopy)
                      FilledButton.icon(
                        onPressed: _busy ? null : _recover,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.restore),
                        label: Text(context.l10n.backupText('recoverButlerly')),
                      ),
                    if (hasSafetyCopy) const SizedBox(height: 12),
                    ButlerlyDestructiveButton(
                      onPressed: _busy ? null : _resetLocalData,
                      icon: const Icon(Icons.delete_forever_outlined),
                      child: Text(
                        context.l10n.backupText('eraseLocalRecoveryData'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
