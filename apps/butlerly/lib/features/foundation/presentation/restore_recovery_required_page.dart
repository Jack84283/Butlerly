import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recovery-only surface shown when Butlerly cannot yet prove one coherent
/// database/evidence/runtime state.
class RestoreRecoveryRequiredPage extends ConsumerStatefulWidget {
  const RestoreRecoveryRequiredPage({super.key});

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.backupText('recoveryResetTitle')),
        content: Text(context.l10n.backupText('recoveryResetBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.backupText('recoveryResetConfirm')),
          ),
        ],
      ),
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

  @override
  Widget build(BuildContext context) {
    final manager = services<WorkspaceDataService>();
    final hasSafetyCopy = manager.hasRecoverySafetyCopy;

    return Scaffold(
      body: SafeArea(
        child: ButlerlyResponsiveBody(
          contentKey: const ValueKey('restore-recovery-required-content'),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ButlerlySize.phoneGutter,
                  vertical: ButlerlySpacing.section,
                ),
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
                    TextButton.icon(
                      onPressed: _busy ? null : _resetLocalData,
                      icon: const Icon(Icons.delete_forever_outlined),
                      label: Text(
                        context.l10n.backupText('eraseLocalRecoveryData'),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
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
