import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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

  Future<void> _add() => _edit();

  Future<void> _scanCard() async {
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.camera);
      if (image == null || !mounted) return;
      final result = await const LocalOcrService().recognizeCard(image.path);
      if (!mounted) return;
      await _edit(scanned: result);
    } on FormatException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage(context.l10n.text('cardScanFailed'));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit({PaymentSource? existing, CardScanResult? scanned}) async {
    final finance = _finance;
    if (finance == null) return;
    final name = TextEditingController(text: existing?.name);
    final issuer = TextEditingController(
      text: existing?.issuer ?? scanned?.issuer,
    );
    final lastFour = TextEditingController(
      text: existing?.lastFour ?? scanned?.lastFour,
    );
    final currency = TextEditingController(text: existing?.currency ?? 'USD');
    final note = TextEditingController(text: existing?.note);
    var type = existing?.type ?? scanned?.type ?? PaymentSourceType.account;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            context.l10n.text(
              existing == null ? 'addPaymentSource' : 'editPaymentSource',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('name'),
                  ),
                ),
                const SizedBox(height: ButlerlySpacing.small),
                TextField(
                  controller: issuer,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('issuer'),
                  ),
                ),
                const SizedBox(height: ButlerlySpacing.small),
                TextField(
                  controller: lastFour,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('lastFour'),
                  ),
                ),
                TextField(
                  controller: currency,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('currency'),
                  ),
                ),
                const SizedBox(height: ButlerlySpacing.small),
                TextField(
                  controller: note,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('notesOptional'),
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final safeLastFour = lastFour.text.trim();
                if (safeLastFour.isNotEmpty &&
                    !RegExp(r'^\d{4}$').hasMatch(safeLastFour)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.l10n.text('invalidLastFour')),
                    ),
                  );
                  return;
                }
                final listedSources = await finance.listPaymentSources();
                final duplicates = switch (listedSources) {
                  ApplicationSuccess<List<PaymentSource>>(:final value) =>
                    value
                        .where(
                          (source) =>
                              source.id != existing?.id &&
                              source.status == PaymentSourceStatus.active &&
                              safeLastFour.isNotEmpty &&
                              source.lastFour == safeLastFour &&
                              source.type == type &&
                              (source.issuer ?? '').trim().toLowerCase() ==
                                  issuer.text.trim().toLowerCase(),
                        )
                        .toList(growable: false),
                  ApplicationFailure<List<PaymentSource>>() =>
                    const <PaymentSource>[],
                };
                if (duplicates.isNotEmpty && context.mounted) {
                  final reuse = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: Text(
                        dialogContext.l10n.text('duplicatePaymentSource'),
                      ),
                      content: Text(
                        dialogContext.l10n.text('duplicatePaymentSourceBody'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: Text(dialogContext.l10n.text('useExisting')),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(dialogContext.l10n.text('createAnyway')),
                        ),
                      ],
                    ),
                  );
                  if (reuse == true && context.mounted) {
                    Navigator.pop(context, false);
                  }
                  if (reuse == true || !context.mounted) return;
                }
                final result = await finance.savePaymentSource(
                  PaymentSource(
                    id:
                        existing?.id ??
                        PaymentSourceId(
                          'source-${DateTime.now().microsecondsSinceEpoch}',
                        ),
                    name: name.text,
                    type: type,
                    displayIdentity: name.text,
                    lastFour: safeLastFour.isEmpty ? null : safeLastFour,
                    issuer: issuer.text.trim().isEmpty
                        ? null
                        : issuer.text.trim(),
                    currency: currency.text.trim().toUpperCase(),
                    note: note.text.trim().isEmpty ? null : note.text.trim(),
                    status: existing?.status ?? PaymentSourceStatus.active,
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
    // The dialog route may still be completing its closing animation when
    // showDialog returns. Dispose after that frame so TextField transitions
    // never retain a disposed controller.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      issuer.dispose();
      lastFour.dispose();
      currency.dispose();
      note.dispose();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(context.l10n.text('paymentSources')),
      actions: [
        IconButton(
          onPressed: _add,
          icon: const Icon(Icons.add_card_outlined),
          tooltip: context.l10n.text('addPaymentSource'),
        ),
        IconButton(
          onPressed: _scanCard,
          icon: const Icon(Icons.document_scanner_outlined),
          tooltip: context.l10n.text('scanCard'),
        ),
      ],
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
                        title: Text(
                          value.lastFour == null
                              ? value.name
                              : '${value.name} ••••${value.lastFour}',
                        ),
                        subtitle: Text(
                          [
                            _typeLabel(context, value.type),
                            if (value.issuer != null) value.issuer!,
                            if (value.currency != null) value.currency!,
                            _statusLabel(context, value.status),
                          ].join(' · '),
                        ),
                        onTap: () => _edit(existing: value),
                        trailing: IconButton(
                          tooltip: context.l10n.text(
                            value.status == PaymentSourceStatus.active
                                ? 'archivePaymentSource'
                                : 'reactivatePaymentSource',
                          ),
                          icon: Icon(
                            value.status == PaymentSourceStatus.active
                                ? Icons.archive_outlined
                                : Icons.unarchive_outlined,
                          ),
                          onPressed: () async {
                            if (value.status == PaymentSourceStatus.active) {
                              final result = await _finance!
                                  .archivePaymentSource(value.id.value);
                              if (!context.mounted) return;
                              if (result is ApplicationFailure<PaymentSource>) {
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
                            } else {
                              await _finance!.savePaymentSource(
                                PaymentSource(
                                  id: value.id,
                                  name: value.name,
                                  type: value.type,
                                  status: PaymentSourceStatus.active,
                                  displayIdentity: value.displayIdentity,
                                  lastFour: value.lastFour,
                                  issuer: value.issuer,
                                  currency: value.currency,
                                  note: value.note,
                                ),
                              );
                            }
                            if (context.mounted) _refresh();
                          },
                        ),
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
