import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/core/evidence/platform_ocr_recognizer.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/payment_source_display.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart' as files;
import 'package:image_picker/image_picker.dart';

class PaymentSourcesPage extends StatefulWidget {
  const PaymentSourcesPage({
    this.ocrRecognizer,
    this.openCreateOnStart = false,
    super.key,
  });

  final OcrRecognizer? ocrRecognizer;
  final bool openCreateOnStart;

  @override
  State<PaymentSourcesPage> createState() => _PaymentSourcesPageState();
}

class _PaymentSourcesPageState extends State<PaymentSourcesPage> {
  late Future<List<PaymentSource>> _sources;
  bool _desktopEditorOpen = false;
  PaymentSource? _desktopSelected;
  CardScanResult? _desktopScanned;
  int _editorRevision = 0;

  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= 900;

  void _openDesktopEditor({PaymentSource? existing, CardScanResult? scanned}) {
    setState(() {
      _desktopEditorOpen = true;
      _desktopSelected = existing;
      _desktopScanned = scanned;
      _editorRevision++;
    });
  }


  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _sources = _load();
    if (widget.openCreateOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _add();
      });
    }
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
    if (_isDesktop(context)) {
      _openDesktopEditor();
    } else {
      await _edit();
    }
  }

  Future<void> _scanCard() async {
    try {
      final String? path;
      if (_isDesktop(context)) {
        final image = await files.openFile(
          acceptedTypeGroups: [
            files.XTypeGroup(
              label: context.l10n.text('receiptImages'),
              extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
            ),
          ],
        );
        path = image?.path;
      } else {
        final image = await ImagePicker().pickImage(source: ImageSource.camera);
        path = image?.path;
      }
      if (path == null || !mounted) return;
      final recognizer =
          widget.ocrRecognizer ??
          (services.isRegistered<OcrRecognizer>()
              ? services<OcrRecognizer>()
              : platformOcrRecognizer());
      final document = await recognizer.recognize(
        OcrRequest(
          source: OcrSource(path: path, kind: OcrSourceKind.image),
          intent: OcrIntent.paymentCard,
        ),
      );
      if (document.text.trim().isEmpty) {
        throw const FormatException('No readable card details were found.');
      }
      final result = CardTextParser.parse(document.text, document.observations);
      if (!mounted) return;
      if (_isDesktop(context)) {
        _openDesktopEditor(scanned: result);
      } else {
        await _edit(scanned: result);
      }
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
    final detectedNetwork = paymentNetworkFromText(scanned?.issuer);
    final issuer = TextEditingController(
      text:
          existing?.issuer ??
          (detectedNetwork == null ? scanned?.issuer : null),
    );
    final lastFour = TextEditingController(
      text: existing?.lastFour ?? scanned?.lastFour,
    );
    final currency = TextEditingController(text: existing?.currency ?? 'USD');
    final note = TextEditingController(text: existing?.note);
    var type = existing?.type ?? scanned?.type ?? PaymentSourceType.account;
    String? network = existing?.network ?? detectedNetwork;
    final locale = Localizations.localeOf(context);
    final typeLabelsResult = await finance.loadReferenceData.labels(
      type: 'payment_source_type',
      locale: locale.languageCode == 'zh' ? 'zh-Hans' : locale.languageCode,
    );
    if (!mounted) return;
    final typeLabels =
        typeLabelsResult is ApplicationSuccess<Map<String, String>>
        ? typeLabelsResult.value
        : const <String, String>{};
    final saved = await showButlerlyBottomSheet<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ButlerlySheet(
          title: Text(
            context.l10n.text(
              existing == null ? 'addPaymentSource' : 'editPaymentSource',
            ),
          ),
          content: ButlerlyCard(
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
                const SizedBox(height: ButlerlySpacing.small),
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
                ButlerlySelectField<PaymentSourceType>(
                  label: context.l10n.text('type'),
                  value: type,
                  entries: [
                    for (final value in PaymentSourceType.values)
                      DropdownMenuEntry(
                        value: value,
                        label:
                            typeLabels['payment_source_type.${value.name}'] ??
                            _typeLabel(context, value),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        if (value != type) network = null;
                        type = value;
                      });
                    }
                  },
                ),
                if (type == PaymentSourceType.card ||
                    type == PaymentSourceType.debitCard ||
                    type == PaymentSourceType.wallet) ...[
                  const SizedBox(height: ButlerlySpacing.small),
                  ButlerlySelectField<String>(
                    label: context.l10n.text(
                      type == PaymentSourceType.wallet
                          ? 'walletProvider'
                          : 'cardNetwork',
                    ),
                    value: network ?? '',
                    entries: [
                      DropdownMenuEntry(
                        value: '',
                        label: context.l10n.text('notSet'),
                      ),
                      for (final entry
                          in (type == PaymentSourceType.wallet
                                  ? walletPaymentProviderLabels
                                  : cardPaymentNetworkLabels)
                              .entries)
                        DropdownMenuEntry(
                          value: entry.key,
                          label: switch (entry.key) {
                            'alipay' => context.l10n.text('alipayBrand'),
                            'wechatPay' => context.l10n.text('wechatPayBrand'),
                            _ => entry.value,
                          },
                          leadingIcon: ButlerlyPaymentMarkIcon(
                            mark: entry.key,
                            size: 24,
                          ),
                        ),
                    ],
                    onChanged: (value) => setDialogState(
                      () => network = value == '' ? null : value,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            ButlerlyCancelButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.text('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                final safeLastFour = lastFour.text.trim();
                final validLastFour = RegExp(r'^\d{4}$').hasMatch(safeLastFour);
                if ((paymentSourceRequiresLastFour(type) && !validLastFour) ||
                    (safeLastFour.isNotEmpty && !validLastFour)) {
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
                  final reuse = await showButlerlyBottomSheet<bool>(
                    context: context,
                    builder: (dialogContext) => ButlerlySheet(
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
                    network: network,
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      issuer.dispose();
      lastFour.dispose();
      currency.dispose();
      note.dispose();
    });
  }

  Future<void> _openSource(PaymentSource value) async {
    if (_isDesktop(context)) {
      _openDesktopEditor(existing: value);
    } else {
      await _edit(existing: value);
    }
  }


  Widget _desktopWorkspace(List<PaymentSource> values) {
    final headers = [
      context.l10n.text('name'),
      context.l10n.text('type'),
      context.l10n.text('issuer'),
      context.l10n.text('lastFour'),
      context.l10n.text('currency'),
      context.l10n.text('status'),
    ];
    final table = ButlerlyCard(
      key: const ValueKey('payment-sources-outer-card'),
      padding: const EdgeInsets.all(ButlerlySpacing.small),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ButlerlyCardHeader(title: context.l10n.text('paymentSources')),
          const SizedBox(height: ButlerlySpacing.compact),
          ButlerlyCard(
            key: const ValueKey('payment-sources-inner-card'),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(ButlerlySpacing.small),
        child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columns: [
            for (final title in headers) DataColumn(label: Text(title)),
          ],
          rows: [
            for (final source in values)
              DataRow(
                selected: _desktopSelected?.id == source.id &&
                    _desktopEditorOpen,
                onSelectChanged: (_) => _openDesktopEditor(existing: source),
                cells: [
                  DataCell(Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ButlerlyPaymentSourceIcon(source: source),
                      const SizedBox(width: ButlerlySpacing.compact),
                      Text(paymentSourceDisplayLabel(source)),
                    ],
                  )),
                  DataCell(Text(_typeLabel(context, source.type))),
                  DataCell(Text(source.issuer ?? '—')),
                  DataCell(Text(source.lastFour ?? '—')),
                  DataCell(Text(source.currency ?? '—')),
                  DataCell(Text(_statusLabel(context, source.status))),
                ],
              ),
          ],
        ),
          ),
          ),
        ],
      ),
    );
    if (!_desktopEditorOpen) return table;
    return Row(
      key: const ValueKey('desktop-payment-source-workspace'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: table),
        const SizedBox(width: ButlerlySpacing.cardGap),
        Expanded(
          flex: 2,
          child: _DesktopPaymentSourceEditor(
            key: ValueKey('desktop-payment-editor-$_editorRevision'),
            finance: _finance!,
            existing: _desktopSelected,
            scanned: _desktopScanned,
            onCancel: () => setState(() => _desktopEditorOpen = false),
            onSaved: () {
              setState(() => _desktopEditorOpen = false);
              _refresh();
            },
            onError: _showMessage,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ButlerlyPage(
    title: context.l10n.text('paymentSources'),
    fullWidth: _isDesktop(context),
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
    children: [
      if (_finance == null)
        ButlerlyEmptyState(
          icon: Icons.storage_outlined,
          title: context.l10n.text('paymentSourcesUnavailable'),
          message: context.l10n.text('dataPreserved'),
        )
      else
        FutureBuilder<List<PaymentSource>>(
          future: _sources,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ButlerlyLoadingState();
            }
            if (snapshot.hasError) {
              return ButlerlyErrorState(
                title: context.l10n.text('paymentSourcesLoadError'),
                message: context.l10n.text('paymentSourcesLoadError'),
                preserved: context.l10n.text('dataPreserved'),
                actionLabel: context.l10n.text('tryAgain'),
                onAction: _refresh,
              );
            }
            final values = snapshot.requireData;
            if (_isDesktop(context)) {
              return _desktopWorkspace(values);
            }
            if (values.isEmpty) {
              return ButlerlyEmptyState(
                icon: Icons.account_balance_wallet_outlined,
                title: context.l10n.text('noPaymentSourcesYet'),
                message: context.l10n.text('paymentSourcesBody'),
                actionLabel: context.l10n.text('addPaymentSource'),
                onAction: _add,
              );
            }
            return ButlerlyCard(
              padding: EdgeInsets.zero,
              child: ButlerlySeparatedList(
                children: values
                    .map(
                      (value) => ListTile(
                        minVerticalPadding: ButlerlySpacing.small,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: ButlerlySpacing.standard,
                          vertical: ButlerlySpacing.compact,
                        ),
                        leading: ButlerlyPaymentSourceIcon(source: value),
                        title: Text(paymentSourceDisplayLabel(value)),
                        subtitle: Text(
                          [
                            _typeLabel(context, value.type),
                            if (value.issuer != null) value.issuer!,
                            if (value.currency != null) value.currency!,
                            _statusLabel(context, value.status),
                          ].join(' · '),
                        ),
                        onTap: () => _openSource(value),
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
                                  network: value.network,
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
              ),
            );
          },
        ),
    ],
  );
}


class _DesktopPaymentSourceEditor extends StatefulWidget {
  const _DesktopPaymentSourceEditor({
    required this.finance,
    required this.existing,
    required this.scanned,
    required this.onCancel,
    required this.onSaved,
    required this.onError,
    super.key,
  });

  final FinanceServices finance;
  final PaymentSource? existing;
  final CardScanResult? scanned;
  final VoidCallback onCancel;
  final VoidCallback onSaved;
  final ValueChanged<String> onError;

  @override
  State<_DesktopPaymentSourceEditor> createState() =>
      _DesktopPaymentSourceEditorState();
}

class _DesktopPaymentSourceEditorState
    extends State<_DesktopPaymentSourceEditor> {
  late final TextEditingController _name;
  late final TextEditingController _issuer;
  late final TextEditingController _lastFour;
  late final TextEditingController _currency;
  late final TextEditingController _note;
  late PaymentSourceType _type;
  String? _network;
  bool _saving = false;
  bool _active = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final scanned = widget.scanned;
    final detectedNetwork = paymentNetworkFromText(scanned?.issuer);
    _name = TextEditingController(text: existing?.name);
    _issuer = TextEditingController(
      text: existing?.issuer ??
          (detectedNetwork == null ? scanned?.issuer : null),
    );
    _lastFour = TextEditingController(
      text: existing?.lastFour ?? scanned?.lastFour,
    );
    _currency = TextEditingController(text: existing?.currency ?? 'USD');
    _note = TextEditingController(text: existing?.note);
    _type = existing?.type ?? scanned?.type ?? PaymentSourceType.account;
    _network = existing?.network ?? detectedNetwork;
    _active = existing?.status == null ||
        existing!.status == PaymentSourceStatus.active;
  }

  @override
  void dispose() {
    _name.dispose();
    _issuer.dispose();
    _lastFour.dispose();
    _currency.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final safeLastFour = _lastFour.text.trim();
    final validLastFour = RegExp(r'^\d{4}$').hasMatch(safeLastFour);
    if ((paymentSourceRequiresLastFour(_type) && !validLastFour) ||
        (safeLastFour.isNotEmpty && !validLastFour)) {
      widget.onError(context.l10n.text('invalidLastFour'));
      return;
    }
    setState(() => _saving = true);
    try {
      final listed = await widget.finance.listPaymentSources();
      if (!mounted) return;
      final List<PaymentSource> duplicates;
      if (listed is ApplicationSuccess<List<PaymentSource>>) {
        duplicates = listed.value.where((source) {
          return source.id != widget.existing?.id &&
              source.status == PaymentSourceStatus.active &&
              safeLastFour.isNotEmpty &&
              source.lastFour == safeLastFour &&
              source.type == _type &&
              (source.issuer ?? '').trim().toLowerCase() ==
                  _issuer.text.trim().toLowerCase();
        }).toList(growable: false);
      } else {
        duplicates = <PaymentSource>[];
      }
      if (duplicates.isNotEmpty) {
        final createAnyway = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dialogContext.l10n.text('duplicatePaymentSource')),
            content: Text(dialogContext.l10n.text('duplicatePaymentSourceBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(dialogContext.l10n.text('useExisting')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(dialogContext.l10n.text('createAnyway')),
              ),
            ],
          ),
        );
        if (!mounted || createAnyway != true) return;
      }
      final result = await widget.finance.savePaymentSource(
        PaymentSource(
          id: widget.existing?.id ??
              PaymentSourceId(
                'source-${DateTime.now().microsecondsSinceEpoch}',
              ),
          name: _name.text,
          type: _type,
          displayIdentity: _name.text,
          lastFour: safeLastFour.isEmpty ? null : safeLastFour,
          issuer: _issuer.text.trim().isEmpty ? null : _issuer.text.trim(),
          network: _network,
          currency: _currency.text.trim().toUpperCase(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          status: _active ? PaymentSourceStatus.active :
              (widget.existing?.status ?? PaymentSourceStatus.active),
        ),
      );
      if (!mounted) return;
      if (result is ApplicationSuccess<PaymentSource>) {
        if (!_active) {
          final archived = await widget.finance.archivePaymentSource(result.value.id.value);
          if (!mounted) return;
          if (archived is ApplicationFailure<PaymentSource>) {
            widget.onError(context.l10n.text('paymentSourceArchiveFailed'));
            return;
          }
        }
        widget.onSaved();
      } else {
        widget.onError(context.l10n.text('paymentSourceSaveFailed'));
      }
    } catch (_) {
      if (mounted) widget.onError(context.l10n.text('paymentSourceSaveFailed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: ButlerlySpacing.small);
    return ButlerlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.text(
              widget.existing == null ? 'addPaymentSource' : 'editPaymentSource',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: ButlerlySpacing.small),
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: context.l10n.text('name')),
          ),
          gap,
          TextField(
            controller: _issuer,
            decoration: InputDecoration(labelText: context.l10n.text('issuer')),
          ),
          gap,
          TextField(
            controller: _lastFour,
            maxLength: 4,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.l10n.text('lastFour')),
          ),
          gap,
          TextField(
            controller: _currency,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: context.l10n.text('currency')),
          ),
          gap,
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(labelText: context.l10n.text('notesOptional')),
          ),
          gap,
          ButlerlySelectField<PaymentSourceType>(
            label: context.l10n.text('type'),
            value: _type,
            entries: [
              for (final type in PaymentSourceType.values)
                DropdownMenuEntry(
                  value: type,
                  label: _typeLabel(context, type),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  if (_type != value) _network = null;
                  _type = value;
                });
              }
            },
          ),
          if (_type == PaymentSourceType.card ||
              _type == PaymentSourceType.debitCard ||
              _type == PaymentSourceType.wallet) ...[
            gap,
            ButlerlySelectField<String>(
              label: context.l10n.text(
                _type == PaymentSourceType.wallet
                    ? 'walletProvider' : 'cardNetwork',
              ),
              value: _network ?? '',
              entries: [
                DropdownMenuEntry(
                  value: '',
                  label: context.l10n.text('notSet'),
                ),
                for (final entry in (_type == PaymentSourceType.wallet
                        ? walletPaymentProviderLabels
                        : cardPaymentNetworkLabels).entries)
                  DropdownMenuEntry(
                    value: entry.key,
                    label: entry.value,
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _network = value == '' ? null : value),
            ),
          ],
          const SizedBox(height: ButlerlySpacing.small),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.text('paymentSourceStatusActive')),
            value: _active,
            onChanged: (value) => setState(() => _active = value),
          ),
          const SizedBox(height: ButlerlySpacing.small),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ButlerlyCancelButton(
                onPressed: widget.onCancel,
                child: Text(context.l10n.text('cancel')),
              ),
              const SizedBox(width: ButlerlySpacing.compact),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(context.l10n.text('save')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _typeLabel(BuildContext context, PaymentSourceType value) =>
    context.l10n.text('paymentSourceType${_enumSuffix(value.name)}');

String _statusLabel(BuildContext context, PaymentSourceStatus value) =>
    context.l10n.text('paymentSourceStatus${_enumSuffix(value.name)}');

String _enumSuffix(String value) =>
    '${value[0].toUpperCase()}${value.substring(1)}';

