import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/import/local_csv_importer.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
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
    final importer = LocalCsvImporter(services<FinanceServices>());
    final preview = await importer.preview(file);
    if (!mounted) return;
    setState(() => _importing = false);
    if (preview.rows.isEmpty || preview.validCount == 0) {
      await _showImportMessage('Import validation', preview.errors.join('\n'));
      return;
    }
    final sources = await services<FinanceServices>().listPaymentSources();
    if (!mounted) return;
    final activeSources = sources is ApplicationSuccess<List<PaymentSource>>
        ? sources.value
              .where((value) => value.status == PaymentSourceStatus.active)
              .toList()
        : const <PaymentSource>[];
    final paymentSourceId = await showDialog<String>(
      context: context,
      builder: (context) =>
          _StatementPreviewDialog(preview: preview, sources: activeSources),
    );
    if (!mounted || paymentSourceId == null) return;
    setState(() => _importing = true);
    final summary = await importer.commitPreview(
      preview,
      sourceId: file.name,
      sourceLanguage: sourceLanguage,
      paymentSourceId: paymentSourceId.isEmpty ? null : paymentSourceId,
    );
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

  Future<void> _showImportMessage(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message.isEmpty ? 'No valid rows were found.' : message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _addNotificationTransaction() async {
    final sources = await services<FinanceServices>().listPaymentSources();
    if (!mounted) return;
    final activeSources = sources is ApplicationSuccess<List<PaymentSource>>
        ? sources.value
              .where((value) => value.status == PaymentSourceStatus.active)
              .toList()
        : const <PaymentSource>[];
    final command = await showDialog<PaymentTransactionCommand>(
      context: context,
      builder: (context) => _SinglePaymentDialog(sources: activeSources),
    );
    if (command == null || !mounted) return;
    setState(() => _importing = true);
    final result = await services<FinanceServices>().createPaymentTransaction(
      command,
    );
    if (!mounted) return;
    setState(() => _importing = false);
    if (result is ApplicationSuccess<TransactionDto>) {
      notifyTransactionChanged();
    }
    await _showImportMessage(
      result is ApplicationSuccess<TransactionDto> ? 'Saved' : 'Could not save',
      result is ApplicationSuccess<TransactionDto>
          ? 'The payment transaction was saved locally.'
          : 'Please check the fields and try again.',
    );
  }

  void _openReceiptFlow(BuildContext context) {
    context.push('/receipts/capture');
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
        _ActionRow(
          icon: Icons.credit_card_outlined,
          title: 'Add payment transaction',
          subtitle:
              'Enter one card transaction when no statement is available.',
          onTap: () => context.push('/transactions/add'),
        ),
        _ActionRow(
          icon: Icons.notifications_none_outlined,
          title: 'Add payment notification',
          subtitle: 'Record one card notification with integration provenance.',
          onTap: _importing ? () {} : _addNotificationTransaction,
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

class _SinglePaymentDialog extends StatefulWidget {
  const _SinglePaymentDialog({required this.sources});

  final List<PaymentSource> sources;

  @override
  State<_SinglePaymentDialog> createState() => _SinglePaymentDialogState();
}

class _SinglePaymentDialogState extends State<_SinglePaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _currency = TextEditingController(text: 'USD');
  String _direction = 'expense';
  String? _sourceId;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _currency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add payment notification'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) => double.tryParse(value ?? '') == null
                  ? 'Enter a valid amount.'
                  : null,
            ),
            TextFormField(
              controller: _currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              validator: (value) => value == null || value.trim().length != 3
                  ? 'Use a 3-letter currency code.'
                  : null,
            ),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Merchant / description',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a description.'
                  : null,
            ),
            DropdownButtonFormField<String>(
              initialValue: _direction,
              decoration: const InputDecoration(labelText: 'Direction'),
              items: const [
                DropdownMenuItem(
                  value: 'expense',
                  child: Text('Debit / expense'),
                ),
                DropdownMenuItem(
                  value: 'income',
                  child: Text('Credit / refund'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _direction = value ?? 'expense'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _sourceId,
              decoration: const InputDecoration(labelText: 'Payment source'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Unassigned')),
                for (final source in widget.sources)
                  DropdownMenuItem(
                    value: source.id.value,
                    child: Text(source.displayIdentity ?? source.name),
                  ),
              ],
              onChanged: (value) => setState(() => _sourceId = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (!_formKey.currentState!.validate()) return;
          final token = DateTime.now().microsecondsSinceEpoch;
          Navigator.pop(
            context,
            PaymentTransactionCommand(
              id: 'notification-$token',
              provenanceId: 'notification-provenance-$token',
              sourceId: 'user-notification',
              originalRepresentation: _description.text.trim(),
              money: Money(
                amount: DecimalValue.parse(_amount.text.trim()),
                currency: CurrencyCode(_currency.text.trim().toUpperCase()),
              ),
              direction: _direction == 'income'
                  ? TransactionDirection.income
                  : TransactionDirection.expense,
              transactionDate: _isoDate(DateTime.now()),
              description: _description.text.trim(),
              paymentSourceId: _sourceId?.isEmpty == true ? null : _sourceId,
              sourceType: TransactionSourceType.integration,
              provenanceSourceType: ProvenanceSourceType.integration,
            ),
          );
        },
        child: const Text('Save'),
      ),
    ],
  );
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

class _StatementPreviewDialog extends StatefulWidget {
  const _StatementPreviewDialog({required this.preview, required this.sources});

  final CsvStatementPreview preview;
  final List<PaymentSource> sources;

  @override
  State<_StatementPreviewDialog> createState() =>
      _StatementPreviewDialogState();
}

class _StatementPreviewDialogState extends State<_StatementPreviewDialog> {
  String? _sourceId;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Review statement import'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.preview.validCount} valid row(s) ready to import.'),
            if (widget.preview.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${widget.preview.errors.length} row(s) need correction.'),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sourceId,
              decoration: const InputDecoration(labelText: 'Payment source'),
              items: [
                const DropdownMenuItem(value: '', child: Text('Unassigned')),
                for (final source in widget.sources)
                  DropdownMenuItem(
                    value: source.id.value,
                    child: Text(source.displayIdentity ?? source.name),
                  ),
              ],
              onChanged: (value) => setState(() => _sourceId = value),
            ),
            const SizedBox(height: 12),
            for (final row in widget.preview.rows.take(8))
              ListTile(
                dense: true,
                title: Text(row.description),
                subtitle: Text('${row.date} · ${row.currency} ${row.amount}'),
                trailing: row.isValid
                    ? const Icon(
                        Icons.check_circle_outline,
                        color: Colors.green,
                      )
                    : const Icon(Icons.error_outline, color: Colors.orange),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _sourceId ?? ''),
        child: const Text('Import valid rows'),
      ),
    ],
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
