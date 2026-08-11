import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
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
        'Payment sources could not load.',
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
          title: const Text('Add payment source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: ButlerlySpacing.small),
              DropdownButtonFormField<PaymentSourceType>(
                initialValue: type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: PaymentSourceType.values
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.name),
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
              child: const Text('Cancel'),
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
              child: const Text('Save locally'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      _refresh();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment source could not be saved.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Payment sources')),
    floatingActionButton: _finance == null
        ? null
        : FloatingActionButton.extended(
            onPressed: _add,
            icon: const Icon(Icons.add),
            label: const Text('Add source'),
          ),
    body: _finance == null
        ? const Center(
            child: Text('Payment sources become available with local storage.'),
          )
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
                    child: const Text('Try again'),
                  ),
                );
              }
              final values = snapshot.requireData;
              if (values.isEmpty) {
                return const Center(child: Text('No payment sources yet.'));
              }
              return ListView(
                children: values
                    .map(
                      (value) => ListTile(
                        title: Text(value.name),
                        subtitle: Text(
                          '${value.type.name} · ${value.status.name}',
                        ),
                        trailing: value.status == PaymentSourceStatus.active
                            ? IconButton(
                                tooltip: 'Archive payment source',
                                icon: const Icon(Icons.archive_outlined),
                                onPressed: () async {
                                  final result = await _finance!
                                      .archivePaymentSource(value.id.value);
                                  if (!context.mounted) return;
                                  if (result
                                      is ApplicationFailure<PaymentSource>) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Payment source could not be archived.',
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
