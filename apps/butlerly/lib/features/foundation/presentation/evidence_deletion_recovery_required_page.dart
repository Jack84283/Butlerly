import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/evidence_deletion_recovery_state.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Recovery-only surface shown when a staged evidence deletion could not be
/// completed safely during startup. The source and journal remain untouched
/// until an integrity-checked retry succeeds.
class EvidenceDeletionRecoveryRequiredPage extends StatefulWidget {
  const EvidenceDeletionRecoveryRequiredPage({super.key, this.retryRecovery});

  @visibleForTesting
  final Future<void> Function()? retryRecovery;

  @override
  State<EvidenceDeletionRecoveryRequiredPage> createState() =>
      _EvidenceDeletionRecoveryRequiredPageState();
}

class _EvidenceDeletionRecoveryRequiredPageState
    extends State<EvidenceDeletionRecoveryRequiredPage> {
  bool _busy = false;

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
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _busy ? null : _retry,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        context.l10n.text('evidenceDeletionRecoveryRetry'),
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
    );
  }
}
