import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/core/data/local_backup_manager.dart';
import 'package:butlerly/core/database/initial_master_data.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recovery-only surface shown when Butlerly cannot prove that an interrupted
/// restore was rolled back to one coherent local state.
///
/// Normal navigation is intentionally unavailable until the retained safety
/// snapshot is restored and validated.
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

  Future<void> _recover() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await services<LocalBackupManager>().recoverControlledState(
        postActivationRefresh: () async {
          await services<FinanceServices>().seedInitialMasterData(
            buildInitialMasterData(),
          );
          ref.invalidate(userPreferenceProvider);
          notifyTransactionChanged();
        },
      );
    } on Exception {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
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
                  context.l10n.backupText('recoveryRequiredTitle'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.backupText('recoveryRequiredBody'),
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
                  onPressed: _busy ? null : _recover,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restore),
                  label: Text(
                    context.l10n.backupText('recoverSafetyBackup'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
