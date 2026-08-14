import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class PaymentSourcesPage extends StatefulWidget {
  const PaymentSourcesPage({super.key});

  @override
  State<PaymentSourcesPage> createState() => _PaymentSourcesPageState();
}

class _PaymentSourcesPageState extends State<PaymentSourcesPage> {
  late Future<List<PaymentSource>> _sources;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _sources = _load();
  }

  Future<List<PaymentSource>> _load() async {
    final finance = _finance;
    if (finance == null) return const [];
    final result = await finance.listPaymentSources();
    return switch (result) {
      ApplicationSuccess<List<PaymentSource>>(:final value) => value,
      ApplicationFailure<List<PaymentSource>>() => throw StateError(
        'Payment sources could not be loaded.',
      ),
    };
  }

  void _refresh() {
    final reload = _load();
    setState(() {
      _sources = reload;
    });
  }

  Future<void> _add() async {
    final finance = _finance;
    if (finance == null) return;
    final name = TextEditingController();
    var type = PaymentSourceType.account;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.l10n.text('addPaymentSource')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: context.l10n.text('name'),
                ),
              ),
              const SizedBox(height: ButlerlySpacing.small),
              DropdownButtonFormField<PaymentSourceType>(
                initialValue: type,
                decoration: InputDecoration(
                  labelText: context.l10n.text('type'),
                ),
                items: PaymentSourceType.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_typeLabel(context, value)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setDialogState(() => type = value!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final result = await finance.savePaymentSource(
                  PaymentSource(
                    id: PaymentSourceId(
                      'source-${DateTime.now().microsecondsSinceEpoch}',
                    ),
                    name: name.text,
                    type: type,
                  ),
                );
                if (context.mounted) {
                  Navigator.pop(
                    context,
                    result is ApplicationSuccess<PaymentSource>,
                  );
                }
              },
              child: Text(context.l10n.text('save')),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      _refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('paymentSourceSaveFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.text('paymentSources'))),
    floatingActionButton: _finance == null
        ? null
        : FloatingActionButton.extended(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: Text(context.l10n.text('addSource')),
          ),
    body: _finance == null
        ? Center(child: Text(context.l10n.text('paymentSourcesUnavailable')))
        : FutureBuilder<List<PaymentSource>>(
            future: _sources,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: FilledButton(
                    onPressed: _refresh,
                    child: Text(context.l10n.text('tryAgain')),
                  ),
                );
              }
              final values = snapshot.requireData;
              if (values.isEmpty) {
                return Center(
                  child: Text(context.l10n.text('noPaymentSourcesYet')),
                );
              }
              return ListView(
                children: values
                    .map(
                      (value) => ListTile(
                        title: Text(value.name),
                        subtitle: Text(
                          '${_typeLabel(context, value.type)} · ${_statusLabel(context, value.status)}',
                        ),
                        trailing: value.status == PaymentSourceStatus.active
                            ? IconButton(
                                tooltip: context.l10n.text(
                                  'archivePaymentSource',
                                ),
                                icon: const Icon(Icons.archive_outlined),
                                onPressed: () async {
                                  final result = await _finance!
                                      .archivePaymentSource(value.id.value);
                                  if (!context.mounted) return;
                                  if (result
                                      is ApplicationFailure<PaymentSource>) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          context.l10n.text(
                                            'paymentSourceArchiveFailed',
                                          ),
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  _refresh();
                                },
                              )
                            : null,
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
  );
}

String _typeLabel(BuildContext context, PaymentSourceType value) =>
    context.l10n.text('paymentSourceType${_enumSuffix(value.name)}');

String _statusLabel(BuildContext context, PaymentSourceStatus value) =>
    context.l10n.text('paymentSourceStatus${_enumSuffix(value.name)}');

String _enumSuffix(String value) =>
    '${value[0].toUpperCase()}${value.substring(1)}';
