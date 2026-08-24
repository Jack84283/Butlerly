import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/import/local_csv_importer.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
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
    try {
      final sourceLanguage = Localizations.localeOf(context).languageCode;
      const group = XTypeGroup(
        label: 'CSV',
        extensions: ['csv'],
        mimeTypes: ['text/csv'],
        uniformTypeIdentifiers: ['public.comma-separated-values-text'],
      );
      final file = await openFile(acceptedTypeGroups: const [group]);
      if (file == null || !mounted) return;
      setState(() => _importing = true);
      final importer = LocalCsvImporter(services<FinanceServices>());
      final preview = await importer.preview(file);
      if (!mounted) return;
      setState(() => _importing = false);
      if (preview.rows.isEmpty || preview.validCount == 0) {
        await _showImportMessage(
          'Import validation',
          preview.errors.join('\n'),
        );
        return;
      }
      final sources = await services<FinanceServices>().listPaymentSources();
      if (!mounted) return;
      final activeSources = sources is ApplicationSuccess<List<PaymentSource>>
          ? sources.value
                .where((value) => value.status == PaymentSourceStatus.active)
                .toList()
          : const <PaymentSource>[];
      final paymentSourceId = await showButlerlyBottomSheet<String>(
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
      await showButlerlyBottomSheet<void>(
        context: context,
        builder: (context) => ButlerlySheet(
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _importing = false);
      await _showImportMessage(
        context.l10n.text('importFromFile'),
        context.l10n.text('importFailed'),
      );
    }
  }

  Future<void> _showImportMessage(String title, String message) async {
    await showButlerlyBottomSheet<void>(
      context: context,
      builder: (context) => ButlerlySheet(
        title: Text(title),
        content: Text(
          message.isEmpty ? context.l10n.text('noResults') : message,
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

  Future<void> _addNotificationTransaction() async {
    final sources = await services<FinanceServices>().listPaymentSources();
    if (!mounted) return;
    final activeSources = sources is ApplicationSuccess<List<PaymentSource>>
        ? sources.value
              .where((value) => value.status == PaymentSourceStatus.active)
              .toList()
        : const <PaymentSource>[];
    final command = await showButlerlyBottomSheet<PaymentTransactionCommand>(
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
      result is ApplicationSuccess<TransactionDto>
          ? context.l10n.text('save')
          : context.l10n.text('paymentSourceSaveFailed'),
      result is ApplicationSuccess<TransactionDto>
          ? context.l10n.text('notificationSaved')
          : context.l10n.text('notificationSaveFailed'),
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
          title: context.l10n.text('addPaymentTransaction'),
          subtitle: context.l10n.text('addPaymentTransactionBody'),
          onTap: () => context.push('/transactions/add'),
        ),
        _ActionRow(
          icon: Icons.notifications_none_outlined,
          title: context.l10n.text('addPaymentNotification'),
          subtitle: context.l10n.text('addPaymentNotificationBody'),
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
  Widget build(BuildContext context) => ButlerlySheet(
    title: Text(context.l10n.text('addPaymentNotification')),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _amount,
              decoration: InputDecoration(
                labelText: context.l10n.text('amount'),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) => double.tryParse(value ?? '') == null
                  ? context.l10n.text('invalidAmount')
                  : null,
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            TextFormField(
              controller: _currency,
              decoration: InputDecoration(
                labelText: context.l10n.text('currency'),
              ),
              validator: (value) => value == null || value.trim().length != 3
                  ? context.l10n.text('currencyThreeLetters')
                  : null,
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            TextFormField(
              controller: _description,
              decoration: InputDecoration(
                labelText: context.l10n.text('merchantDescription'),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a description.'
                  : null,
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: DropdownButtonFormField<String>(
                  initialValue: _direction,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('direction'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'expense',
                      child: Text(context.l10n.text('debitExpense')),
                    ),
                    DropdownMenuItem(
                      value: 'income',
                      child: Text(context.l10n.text('creditRefund')),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _direction = value ?? 'expense'),
                ),
              ),
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: DropdownButtonFormField<String>(
                  initialValue: _sourceId,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('paymentSource'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(context.l10n.text('unassigned')),
                    ),
                    for (final source in widget.sources)
                      DropdownMenuItem(
                        value: source.id.value,
                        child: Text(_paymentSourceLabel(source)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _sourceId = value),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.text('cancel')),
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
        child: Text(context.l10n.text('save')),
      ),
    ],
  );
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _paymentSourceLabel(PaymentSource source) => source.lastFour == null
    ? (source.displayIdentity ?? source.name)
    : '${source.displayIdentity ?? source.name} ••••${source.lastFour}';

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
  Widget build(BuildContext context) => ButlerlySheet(
    title: Text(context.l10n.text('reviewStatementImport')),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.text('validRowsReady', {
                'count': '${widget.preview.validCount}',
              }),
            ),
            if (widget.preview.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                context.l10n.text('rowsNeedCorrection', {
                  'count': '${widget.preview.errors.length}',
                }),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _sourceId,
              decoration: InputDecoration(
                labelText: context.l10n.text('paymentSource'),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(context.l10n.text('unassigned')),
                ),
                for (final source in widget.sources)
                  DropdownMenuItem(
                    value: source.id.value,
                    child: Text(_paymentSourceLabel(source)),
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
                    ? Icon(
                        Icons.check_circle_outline,
                        color: context.colors.success,
                      )
                    : Icon(Icons.error_outline, color: context.colors.warning),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.text('cancel')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _sourceId ?? ''),
        child: Text(context.l10n.text('importValidRows')),
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
        ButlerlySectionHeader(title: context.l10n.text('extractedSourceText')),
        ButlerlyCard(
          child: Text(context.l10n.text('extractedTextUnavailable')),
        ),
      ],
    ),
  );
}
