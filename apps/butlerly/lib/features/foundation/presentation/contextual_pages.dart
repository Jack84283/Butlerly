import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/import/local_csv_importer.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class LaunchPage extends StatefulWidget {
  const LaunchPage({super.key});

  @override
  State<LaunchPage> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(
        ButlerlyMotion.responsive(context, const Duration(seconds: 3)),
      );
      if (mounted) context.go('/welcome');
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Semantics(
      label: context.l10n.text('appName'),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: context.colors.brand,
                borderRadius: BorderRadius.circular(ButlerlyRadius.large),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Colors.white,
                size: 44,
              ),
            ),
            const SizedBox(height: ButlerlySpacing.section),
            Text(
              context.l10n.text('appName'),
              style: Theme.of(context).textTheme.displaySmall,
            ),
          ],
        ),
      ),
    ),
  );
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      actions: [
        TextButton(
          onPressed: () => context.go('/'),
          child: Text(context.l10n.text('skip')),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(ButlerlySpacing.section),
        children: [
          Align(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.colors.brand,
                borderRadius: BorderRadius.circular(ButlerlyRadius.large),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: ButlerlySpacing.section),
          Text(
            context.l10n.text('welcomeTitle'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: ButlerlySpacing.compact),
          Text(
            context.l10n.text('welcomeSubtitle'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: ButlerlySpacing.large),
          _WelcomeValue(
            icon: Icons.lock_outline_rounded,
            title: context.l10n.text('privateByDefault'),
            body: context.l10n.text('privateByDefaultBody'),
          ),
          const SizedBox(height: ButlerlySpacing.small),
          _WelcomeValue(
            icon: Icons.cloud_off_outlined,
            title: context.l10n.text('worksOffline'),
            body: context.l10n.text('worksOfflineBody'),
          ),
          const SizedBox(height: ButlerlySpacing.small),
          _WelcomeValue(
            icon: Icons.auto_awesome_outlined,
            title: context.l10n.text('optionalAssistance'),
            body: context.l10n.text('optionalAssistanceBody'),
          ),
          const SizedBox(height: ButlerlySpacing.large),
          FilledButton(
            onPressed: () => context.go('/'),
            child: Text(context.l10n.text('getStarted')),
          ),
        ],
      ),
    ),
  );
}

class _WelcomeValue extends StatelessWidget {
  const _WelcomeValue({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    child: Row(
      children: [
        Container(
          width: ButlerlySize.preferredTarget,
          height: ButlerlySize.preferredTarget,
          decoration: BoxDecoration(
            color: context.colors.brand.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
          ),
          child: Icon(icon, color: context.colors.brandStrong),
        ),
        const SizedBox(width: ButlerlySpacing.standard),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(body, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

class ImportExportPage extends StatefulWidget {
  const ImportExportPage({super.key});

  @override
  State<ImportExportPage> createState() => _ImportExportPageState();
}

class _ImportExportPageState extends State<ImportExportPage> {
  bool _importing = false;

  Future<void> _importCsv() async {
    final sourceLanguage = Localizations.localeOf(context).languageCode;
    const group = XTypeGroup(label: 'CSV', extensions: ['csv']);
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null || !mounted) return;
    setState(() => _importing = true);
    final summary = await LocalCsvImporter(
      services<FinanceServices>(),
    ).import(file, sourceLanguage: sourceLanguage);
    if (!mounted) return;
    setState(() => _importing = false);
    if (summary.imported > 0) notifyTransactionChanged();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('importSummary')),
        content: Text(
          context.l10n.text('importSummaryBody', {
            'imported': '${summary.imported}',
            'duplicates': '${summary.duplicates}',
            'failed': '${summary.failed}',
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
  }

  void _openReceiptFlow(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(
          ButlerlySpacing.section,
          0,
          ButlerlySpacing.section,
          ButlerlySpacing.large,
        ),
        child: ButlerlyEmptyState(
          icon: Icons.receipt_long_outlined,
          title: context.l10n.text('importReceipts'),
          message: context.l10n.text('receiptAttachGuide'),
          actionLabel: context.l10n.text('viewTransactions'),
          onAction: () {
            Navigator.pop(context);
            this.context.go('/transactions');
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('importExport'))),
    body: ListView(
      padding: const EdgeInsets.all(ButlerlySpacing.standard),
      children: [
        ButlerlyOfflineBanner(
          message: context.l10n.text('importOfflineBanner'),
        ),
        if (_importing) const LinearProgressIndicator(),
        ButlerlySectionHeader(title: context.l10n.text('importData')),
        _ActionRow(
          icon: Icons.file_open_outlined,
          title: context.l10n.text('importFromFile'),
          subtitle: context.l10n.text('importFromFileBody'),
          onTap: _importing ? () {} : _importCsv,
        ),
        _ActionRow(
          icon: Icons.image_outlined,
          title: context.l10n.text('importReceipts'),
          subtitle: context.l10n.text('importReceiptsBody'),
          onTap: () => _openReceiptFlow(context),
        ),
        ButlerlySectionHeader(title: context.l10n.text('importExport')),
        _ActionRow(
          icon: Icons.file_download_outlined,
          title: context.l10n.text('exportToFile'),
          subtitle: context.l10n.text('exportToFileBody'),
          onTap: () => context.push('/privacy-data'),
        ),
      ],
    ),
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
    child: ButlerlyCard(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, color: context.colors.interactive),
          const SizedBox(width: ButlerlySpacing.standard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('notifications'))),
    body: ButlerlyEmptyState(
      icon: Icons.notifications_none_rounded,
      title: context.l10n.text('noNotifications'),
      message: context.l10n.text('noNotificationsBody'),
    ),
  );
}

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('insights'))),
    body: ButlerlyEmptyState(
      icon: Icons.insights_outlined,
      title: context.l10n.text('notEnoughInsightData'),
      message: context.l10n.text('notEnoughInsightDataBody'),
      actionLabel: context.l10n.text('addTransaction'),
      onAction: () => context.push('/transactions/add'),
    ),
  );
}

class AssistantUnavailablePage extends StatelessWidget {
  const AssistantUnavailablePage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('assistant'))),
    body: ButlerlyEmptyState(
      icon: Icons.auto_awesome_outlined,
      title: context.l10n.text('assistantUnavailable'),
      message: context.l10n.text('assistantUnavailableBody'),
      actionLabel: context.l10n.text('searchRecords'),
      onAction: () => context.go('/search'),
    ),
  );
}

class ReceiptDetailPage extends StatelessWidget {
  const ReceiptDetailPage({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('receiptDetail'))),
    body: ListView(
      padding: const EdgeInsets.all(ButlerlySpacing.standard),
      children: [
        Text(
          context.l10n.text('sourceData'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: ButlerlySpacing.small),
        ButlerlySourcePreview(
          title: name,
          subtitle: context.l10n.text('receiptPreview'),
        ),
        const ButlerlySectionHeader(title: 'Extracted text'),
        ButlerlyCard(
          child: Text(context.l10n.text('extractedTextUnavailable')),
        ),
      ],
    ),
  );
}
