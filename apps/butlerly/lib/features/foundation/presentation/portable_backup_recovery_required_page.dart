import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Recovery surface shown when a portable backup destination must be
/// re-authorized before Butlerly can safely finish or roll back publication.
class PortableBackupRecoveryRequiredPage extends ConsumerStatefulWidget {
  const PortableBackupRecoveryRequiredPage({super.key, this.selectLocation});

  final Future<XFile?> Function()? selectLocation;

  @override
  ConsumerState<PortableBackupRecoveryRequiredPage> createState() =>
      _PortableBackupRecoveryRequiredPageState();
}

class _PortableBackupRecoveryRequiredPageState
    extends ConsumerState<PortableBackupRecoveryRequiredPage> {
  static const _backupType = XTypeGroup(
    label: 'Butlerly backup',
    extensions: [PortableBackupPolicy.extension],
    uniformTypeIdentifiers: [PortableBackupPolicy.uniformTypeIdentifier],
  );

  bool _busy = false;
  bool _failed = false;

  Future<void> _selectLocation() async {
    final selected =
        await (widget.selectLocation?.call() ??
            openFile(acceptedTypeGroups: const [_backupType]));
    if (selected == null || !mounted) return;

    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await services<WorkspaceDataService>().recoverPortableBackupPublication(
        selected.path,
      );
    } catch (_) {
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
          contentKey: const ValueKey('portable-backup-recovery-content'),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ButlerlySize.contentGutter,
                  vertical: ButlerlySpacing.section,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.folder_open_outlined,
                      size: 52,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      context.l10n.backupText('portableRecoveryTitle'),
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.backupText('portableRecoveryBody'),
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    if (_failed) ...[
                      const SizedBox(height: 12),
                      Text(
                        context.l10n.backupText(
                          'portableRecoveryStillRequired',
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _busy ? null : _selectLocation,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.folder_open),
                      label: Text(
                        context.l10n.backupText('selectBackupLocation'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _failed = false),
                      child: Text(context.l10n.backupText('keepRecoveryData')),
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
