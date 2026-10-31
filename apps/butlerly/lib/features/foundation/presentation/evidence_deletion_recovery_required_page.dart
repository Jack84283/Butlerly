import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/evidence_deletion_recovery_state.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:flutter/material.dart';

/// Recovery-only surface shown when a staged evidence deletion could not be
/// completed safely during startup. The source and journal remain untouched
/// until an integrity-checked retry succeeds.
class EvidenceDeletionRecoveryRequiredPage extends StatefulWidget {
  const EvidenceDeletionRecoveryRequiredPage({
    super.key,
    this.retryRecovery,
    required this.resetRecovery,
  });

  @visibleForTesting
  final Future<void> Function()? retryRecovery;

  /// Explicitly erases all local data when evidence recovery cannot be
  /// completed. This is intentionally destructive and is only offered after
  /// confirmation; uncertain evidence is never silently discarded.
  final Future<void> Function() resetRecovery;

  @override
  State<EvidenceDeletionRecoveryRequiredPage> createState() =>
      _EvidenceDeletionRecoveryRequiredPageState();
}

class _EvidenceDeletionRecoveryRequiredPageState
    extends State<EvidenceDeletionRecoveryRequiredPage> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      final retryRecovery =
          widget.retryRecovery ??
          services<LocalEvidenceStore>().recoverStagedEvidenceDeletions;
      await retryRecovery();
      services<EvidenceDeletionRecoveryState>().clear();
    } catch (error) {
      services<EvidenceDeletionRecoveryState>().markRequired(error);
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
      await widget.resetRecovery();
      services<EvidenceDeletionRecoveryState>().clear();
    } catch (error) {
      services<EvidenceDeletionRecoveryState>().markRequired(error);
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportRecoveryArtifacts() async {
    setState(() => _busy = true);
    try {
      final directory = await services<LocalEvidenceStore>()
          .exportStagedEvidenceRecovery();
      if (!mounted) return;
      await showButlerlyBottomSheet<void>(
        context: context,
        builder: (sheetContext) => ButlerlySheet(
          title: Text(sheetContext.l10n.backupText('recoveryEvidenceExported')),
          content: Text(
            '${sheetContext.l10n.backupText('recoveryEvidenceExportedBody')}\n\n${directory.path}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              child: Text(sheetContext.l10n.text('done')),
            ),
          ],
        ),
      );
    } catch (error) {
      services<EvidenceDeletionRecoveryState>().markRequired(error);
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ButlerlyResponsiveBody(
          contentKey: const ValueKey('evidence-deletion-recovery-content'),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Padding(
                  padding: const EdgeInsets.all(24),
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
                        context.l10n.text('evidenceDeletionRecoveryTitle'),
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.text('evidenceDeletionRecoveryBody'),
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
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
                      FilledButton.icon(
                        onPressed: _busy ? null : _retry,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(
                          context.l10n.text('evidenceDeletionRecoveryRetry'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _exportRecoveryArtifacts,
                        icon: const Icon(Icons.save_alt_outlined),
                        label: Text(
                          context.l10n.backupText('recoveryEvidenceExport'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ButlerlyDestructiveButton(
                        onPressed: _busy ? null : _resetLocalData,
                        icon: const Icon(Icons.delete_forever_outlined),
                        child: Text(
                          context.l10n.backupText('eraseLocalRecoveryData'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.text('evidenceDeletionRecoveryKept'),
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
