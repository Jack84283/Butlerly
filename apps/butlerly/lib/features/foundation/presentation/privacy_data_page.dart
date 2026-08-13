import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/database/initial_master_data.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PrivacyDataPage extends ConsumerStatefulWidget {
  const PrivacyDataPage({super.key});

  @override
  ConsumerState<PrivacyDataPage> createState() => _PrivacyDataPageState();
}

class _PrivacyDataPageState extends ConsumerState<PrivacyDataPage> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final result = await services<LocalDataManager>().exportAll();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.l10n.text('exportComplete')),
          content: Text(
            context.l10n.text('exportCompleteBody', {
              'count': '${result.recordCount}',
              'path': result.directory.path,
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
    } on Exception {
      if (mounted) _message(context.l10n.text('exportFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmErase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('eraseAllTitle')),
        content: Text(context.l10n.text('eraseAllBody')),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('eraseAllConfirm')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await services<LocalDataManager>().eraseAll();
      await services<FinanceServices>().seedInitialMasterData(
        buildInitialMasterData(),
      );
      ref.invalidate(userPreferenceProvider);
      notifyTransactionChanged();
      if (mounted) _message(context.l10n.text('eraseComplete'));
    } on Exception {
      if (mounted) _message(context.l10n.text('eraseFailed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('privacyAndData'))),
    body: ListView(
      padding: const EdgeInsets.all(ButlerlySpacing.standard),
      children: [
        ButlerlyCard(child: Text(context.l10n.text('privacyScopeBody'))),
        ButlerlySectionHeader(title: context.l10n.text('localDataControls')),
        ListTile(
          enabled: !_busy,
          leading: const Icon(Icons.download_outlined),
          title: Text(context.l10n.text('exportToFile')),
          subtitle: Text(context.l10n.text('exportScopeBody')),
          onTap: _export,
        ),
        const Divider(),
        ListTile(
          enabled: !_busy,
          leading: const Icon(Icons.delete_forever_outlined),
          title: Text(context.l10n.text('resetAllData')),
          subtitle: Text(context.l10n.text('eraseScopeBody')),
          textColor: Theme.of(context).colorScheme.error,
          iconColor: Theme.of(context).colorScheme.error,
          onTap: _confirmErase,
        ),
        if (_busy) const Center(child: CircularProgressIndicator()),
      ],
    ),
  );
}
