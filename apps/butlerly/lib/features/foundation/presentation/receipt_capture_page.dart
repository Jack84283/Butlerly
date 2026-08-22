import 'dart:async';
import 'dart:io';

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ReceiptCapturePage extends StatefulWidget {
  const ReceiptCapturePage({super.key});

  @override
  State<ReceiptCapturePage> createState() => _ReceiptCapturePageState();
}

String _paymentSourceLabel(PaymentSource source) => source.lastFour == null
    ? (source.displayIdentity ?? source.name)
    : '${source.displayIdentity ?? source.name} ••••${source.lastFour}';

class _ReceiptCapturePageState extends State<ReceiptCapturePage> {
  final _picker = ImagePicker();
  final _ocr = const LocalOcrService();
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _currency = TextEditingController(text: 'USD');
  final _merchantRaw = TextEditingController();
  final _notes = TextEditingController();

  XFile? _source;
  PreservedEvidenceSource? _preserved;
  ReceiptOcrResult? _ocrResult;
  DateTime? _date;
  bool _processing = false;
  bool _saving = false;
  bool _committed = false;
  String? _merchantId;
  String? _categoryId;
  String? _paymentSourceId;
  final Set<String> _tagIds = {};
  List<Merchant> _merchants = const [];
  List<Category> _categories = const [];
  List<Tag> _tags = const [];
  List<PaymentSource> _sources = const [];

  FinanceServices get finance => services<FinanceServices>();
  LocalEvidenceStore get evidenceStore => services<LocalEvidenceStore>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    if (!_committed && _preserved != null) {
      unawaited(evidenceStore.discardPreserved(_preserved!));
    }
    _amount.dispose();
    _currency.dispose();
    _merchantRaw.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      finance.listMerchants(),
      finance.listCategories(),
      finance.listTags(),
      finance.listPaymentSources(),
      finance.loadUserPreference(),
    ]);
    if (!mounted) return;
    setState(() {
      if (values[0] case ApplicationSuccess<List<Merchant>>(
        value: final value,
      )) {
        _merchants = value;
      }
      if (values[1] case ApplicationSuccess<List<Category>>(
        value: final value,
      )) {
        _categories = value;
      }
      if (values[2] case ApplicationSuccess<List<Tag>>(value: final value)) {
        _tags = value;
      }
      if (values[3] case ApplicationSuccess<List<PaymentSource>>(
        value: final value,
      )) {
        _sources = value;
      }
      if (values[4] case ApplicationSuccess<UserPreference?>(
        value: final value?,
      )) {
        _currency.text = value.baseCurrency.value;
      }
    });
  }

  Future<void> _camera() async {
    final source = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
      requestFullMetadata: false,
    );
    if (source != null) await _process(source);
  }

  Future<void> _photo() async {
    final source = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
      requestFullMetadata: false,
    );
    if (source != null) await _process(source);
  }

  Future<void> _file() async {
    const group = files.XTypeGroup(
      label: 'Receipt images',
      extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
    );
    final source = await files.openFile(acceptedTypeGroups: const [group]);
    if (source != null) {
      await _process(XFile(source.path, name: source.name));
    }
  }

  Future<void> _process(XFile source) async {
    final confirmed = await showButlerlyBottomSheet<bool>(
      context: context,
      builder: (dialogContext) => ButlerlySheet(
        title: Text(context.l10n.text('receiptUseTitle')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520, maxWidth: 520),
          child: Image.file(File(source.path), fit: BoxFit.contain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.l10n.text('receiptRetakeReplace')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.l10n.text('receiptUse')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    PreservedEvidenceSource preserved;
    File? stableFile;
    try {
      preserved = await evidenceStore.preserve(source);
      stableFile = await evidenceStore.fileForPreserved(preserved);
      if (stableFile == null || !await stableFile.exists()) {
        throw const FileSystemException('Preserved receipt is unavailable.');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('receiptStoreFailed'))),
      );
      return;
    }

    final previous = _preserved;
    if (previous != null) await evidenceStore.discardPreserved(previous);
    if (!mounted) {
      await evidenceStore.discardPreserved(preserved);
      return;
    }

    final stableSource = XFile(
      stableFile.path,
      name: preserved.originalName,
      mimeType: preserved.mediaType,
    );
    setState(() {
      _preserved = preserved;
      _source = stableSource;
      _processing = true;
      _ocrResult = null;
    });

    try {
      final result = await _ocr.recognize(stableSource.path);
      if (!mounted) return;
      final paymentSourceId = await _resolvePaymentSource(result.cardLast4);
      if (!mounted) return;
      setState(() {
        _ocrResult = result;
        _merchantRaw.text = result.merchant ?? '';
        _amount.text = result.amount ?? '';
        if (result.currency != null) _currency.text = result.currency!;
        _date = result.date;
        _merchantId = _match(result.merchant);
        _paymentSourceId = paymentSourceId;
        _processing = false;
      });
      final match = await _findExistingPaymentMatch();
      if (match != null && mounted) {
        final attach = await _confirmExistingMatch(match);
        if (attach == true) {
          await _attachReceiptToExisting(match);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Receipt was saved locally, but its text could not be read. You can retry or enter the fields manually.',
          ),
        ),
      );
    }
  }

  Future<String?> _resolvePaymentSource(String? lastFour) async {
    if (lastFour == null) return null;
    final matches = _sources
        .where(
          (source) =>
              source.status == PaymentSourceStatus.active &&
              source.lastFour == lastFour,
        )
        .toList(growable: false);
    if (matches.length <= 1) {
      return matches.isEmpty ? null : matches.single.id.value;
    }
    if (!mounted) return null;
    return showButlerlyBottomSheet<String>(
      context: context,
      builder: (dialogContext) => ButlerlySheet(
        title: Text(dialogContext.l10n.text('multiplePaymentSourcesMatch')),
        content: Text(dialogContext.l10n.text('selectPaymentSource')),
        actions: [
          for (final source in matches)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, source.id.value),
              child: Text(_paymentSourceLabel(source)),
            ),
        ],
      ),
    );
  }

  Future<TransactionDto?> _findExistingPaymentMatch() async {
    final amount = _amount.text.trim();
    if (amount.isEmpty) return null;
    final result = await finance.findReceiptPaymentMatch(
      ReceiptPaymentMatchCommand(
        amount: Money(
          amount: DecimalValue.parse(amount),
          currency: CurrencyCode(_currency.text.trim()),
        ),
        currency: _currency.text.trim(),
        transactionDate: _date == null ? null : _iso(_date!),
        merchant: _merchantRaw.text.trim(),
        paymentSourceId: _paymentSourceId,
      ),
    );
    return result is ApplicationSuccess<TransactionDto?> ? result.value : null;
  }

  Future<bool?> _confirmExistingMatch(TransactionDto transaction) {
    final source = _sources
        .where((value) => value.id.value == transaction.paymentSourceId)
        .firstOrNull;
    final sourceLabel = source == null ? null : _paymentSourceLabel(source);
    return showButlerlyBottomSheet<bool>(
      context: context,
      builder: (dialogContext) => ButlerlySheet(
        title: Text(dialogContext.l10n.text('existingTransactionFound')),
        content: Text(
          [
            transaction.rawCounterparty ?? transaction.description ?? '',
            '${transaction.currency} ${transaction.amount} · ${transaction.transactionDate}',
            ?sourceLabel,
          ].join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.text('notThisTransaction')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.text('attachReceipt')),
          ),
        ],
      ),
    );
  }

  Future<void> _attachReceiptToExisting(TransactionDto transaction) async {
    final preserved = _preserved;
    final ocr = _ocrResult;
    if (preserved == null) return;
    setState(() => _saving = true);
    final evidence = await evidenceStore.attachPreservedAndReturn(
      transactionId: transaction.id,
      source: preserved,
    );
    if (evidence == null) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (ocr != null) {
      await finance.saveExtraction(
        Extraction(
          id: ExtractionId('extraction-${evidence.id.value}'),
          evidenceId: evidence.id,
          values: {
            ...ocr.toExtractionValues(),
            'confirmedAmount': _amount.text.trim(),
            'confirmedCurrency': _currency.text.trim(),
            if (_date != null) 'confirmedDate': _iso(_date!),
          },
          provenance: Provenance(
            id: ProvenanceId('extraction-provenance-${evidence.id.value}'),
            sourceType: ProvenanceSourceType.evidenceExtraction,
            capturedAt: DateTime.now().toUtc(),
            originalRepresentation: ocr.rawText,
          ),
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }
    _committed = true;
    notifyTransactionChanged();
    if (mounted) Navigator.pop(context, true);
  }

  String? _match(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final normalized = raw.trim().toLowerCase();
    for (final merchant in _merchants) {
      if (merchant.status != MerchantStatus.active) continue;
      if (merchant.name.toLowerCase() == normalized ||
          merchant.rawName?.toLowerCase() == normalized) {
        return merchant.id.value;
      }
    }
    return null;
  }

  String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) {
      setState(() => _date = value);
    }
  }

  Future<void> _save() async {
    final source = _source;
    final preserved = _preserved;
    if (source == null ||
        preserved == null ||
        _date == null ||
        !_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);
    final token = DateTime.now().microsecondsSinceEpoch;
    final result = await finance.createReceiptTransaction(
      ReceiptTransactionCommand(
        id: 'transaction-$token',
        provenanceId: 'receipt-transaction-$token',
        money: Money(
          amount: DecimalValue.parse(_amount.text.trim()),
          currency: CurrencyCode(_currency.text.trim()),
        ),
        transactionDate: _iso(_date!),
        originalRepresentation: source.name,
        rawCounterparty: _merchantRaw.text.trim().isEmpty
            ? null
            : _merchantRaw.text.trim(),
        description: _merchantRaw.text.trim().isEmpty
            ? 'Receipt purchase'
            : _merchantRaw.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        merchantId: _merchantId,
        categoryId: _categoryId,
        paymentSourceId: _paymentSourceId,
        tagIds: _tagIds.toList(growable: false),
      ),
    );

    if (result is! ApplicationSuccess<TransactionDto>) {
      if (mounted) setState(() => _saving = false);
      return;
    }

    final evidence = await evidenceStore.attachPreservedAndReturn(
      transactionId: result.value.id,
      source: preserved,
    );
    if (evidence == null) {
      await finance.deleteTransactionPermanently(result.value.id);
      if (mounted) setState(() => _saving = false);
      return;
    }

    final ocr = _ocrResult;
    if (ocr != null) {
      await finance.saveExtraction(
        Extraction(
          id: ExtractionId('extraction-$token'),
          evidenceId: evidence.id,
          values: {
            ...ocr.toExtractionValues(),
            'confirmedAmount': _amount.text.trim(),
            'confirmedCurrency': _currency.text.trim(),
            if (_date != null) 'confirmedDate': _iso(_date!),
          },
          provenance: Provenance(
            id: ProvenanceId('extraction-provenance-$token'),
            sourceType: ProvenanceSourceType.evidenceExtraction,
            capturedAt: DateTime.now().toUtc(),
            originalRepresentation: ocr.rawText,
          ),
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }

    _committed = true;
    notifyTransactionChanged();
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final activeCategories = _categories
        .where((value) => value.status == CategoryStatus.active)
        .toList(growable: false);
    final selectedCategory = _categoryId == null
        ? null
        : activeCategories
              .where((value) => value.id.value == _categoryId)
              .firstOrNull;
    final selectedParentId =
        selectedCategory?.parentId?.value ??
        (selectedCategory?.parentId == null && selectedCategory != null
            ? selectedCategory.id.value
            : null);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('captureReceipt'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(ButlerlySpacing.standard),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            if (_source == null) ...[
              Text(
                context.l10n.text('addReceipt'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: ButlerlySpacing.small),
              FilledButton.icon(
                onPressed: _camera,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(context.l10n.text('takePhoto')),
              ),
              const SizedBox(height: ButlerlySpacing.compact),
              OutlinedButton.icon(
                onPressed: _photo,
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(context.l10n.text('choosePhotos')),
              ),
              const SizedBox(height: ButlerlySpacing.compact),
              OutlinedButton.icon(
                onPressed: _file,
                icon: const Icon(Icons.folder_open_outlined),
                label: Text(context.l10n.text('chooseFiles')),
              ),
            ] else ...[
              SizedBox(
                height: ButlerlySize.sourcePreviewHeight * 3,
                child: Image.file(File(_source!.path), fit: BoxFit.contain),
              ),
              if (_processing) ...[
                const SizedBox(height: ButlerlySpacing.small),
                const LinearProgressIndicator(),
                const SizedBox(height: ButlerlySpacing.compact),
                Text(context.l10n.text('readingReceipt')),
              ],
              if (!_processing) ...[
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _camera,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.l10n.text('retake')),
                    ),
                    TextButton.icon(
                      onPressed: _photo,
                      icon: const Icon(Icons.swap_horiz),
                      label: Text(context.l10n.text('replace')),
                    ),
                  ],
                ),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _merchantRaw,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('merchant'),
                        ),
                      ),
                      const SizedBox(height: ButlerlySpacing.standard),
                      DropdownButtonFormField<String>(
                        initialValue: _merchantId,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('merchant'),
                        ),
                        items: [
                          for (final merchant in _merchants.where(
                            (value) => value.status == MerchantStatus.active,
                          ))
                            DropdownMenuItem(
                              value: merchant.id.value,
                              child: Text(merchant.name),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _merchantId = value),
                      ),
                      const SizedBox(height: ButlerlySpacing.standard),
                      TextFormField(
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: context.l10n.text('amount'),
                        ),
                        validator: (value) {
                          try {
                            DecimalValue.parse(value?.trim() ?? '');
                            return null;
                          } on DomainValidationException {
                            return context.l10n.text('invalidAmount');
                          }
                        },
                      ),
                      const SizedBox(height: ButlerlySpacing.standard),
                      TextFormField(
                        controller: _currency,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('currency'),
                        ),
                        validator: (value) {
                          try {
                            CurrencyCode(value?.trim() ?? '');
                            return null;
                          } on DomainValidationException {
                            return context.l10n.text('invalidCurrency');
                          }
                        },
                      ),
                      const SizedBox(height: ButlerlySpacing.standard),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.l10n.text('purchaseDate')),
                        subtitle: Text(_date == null ? '—' : _iso(_date!)),
                        trailing: const Icon(Icons.calendar_today_outlined),
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: ButlerlySpacing.standard),
                      DropdownButtonFormField<String>(
                        initialValue: selectedParentId,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('category'),
                        ),
                        items: [
                          for (final category in activeCategories.where(
                            (value) => value.parentId == null,
                          ))
                            DropdownMenuItem(
                              value: category.id.value,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _categoryId = value;
                        }),
                      ),
                      const SizedBox(height: ButlerlySpacing.standard),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory?.parentId == null
                            ? null
                            : _categoryId,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('subcategory'),
                        ),
                        items: [
                          for (final category in activeCategories.where(
                            (value) =>
                                value.parentId?.value == selectedParentId,
                          ))
                            DropdownMenuItem(
                              value: category.id.value,
                              child: Text(category.name),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _categoryId = value ?? selectedParentId;
                        }),
                      ),
                      const SizedBox(height: ButlerlySpacing.standard),
                      DropdownButtonFormField<String>(
                        initialValue: _paymentSourceId,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('paymentSource'),
                        ),
                        items: [
                          for (final source in _sources.where(
                            (value) =>
                                value.status == PaymentSourceStatus.active,
                          ))
                            DropdownMenuItem(
                              value: source.id.value,
                              child: Text(
                                source.lastFour == null
                                    ? (source.displayIdentity ?? source.name)
                                    : '${source.displayIdentity ?? source.name} ••••${source.lastFour}',
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _paymentSourceId = value),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: ButlerlySpacing.compact,
                          runSpacing: ButlerlySpacing.micro,
                          children: [
                            for (final tag in _tags.where(
                              (value) => value.status == TagStatus.active,
                            ))
                              FilterChip(
                                label: Text(tag.name),
                                selected: _tagIds.contains(tag.id.value),
                                onSelected: (selected) => setState(() {
                                  if (selected) {
                                    _tagIds.add(tag.id.value);
                                  } else {
                                    _tagIds.remove(tag.id.value);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: ButlerlySpacing.standard),
                      TextFormField(
                        controller: _notes,
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('notes'),
                        ),
                      ),
                      if (_ocrResult != null)
                        ExpansionTile(
                          title: Text(context.l10n.text('extractedSourceText')),
                          subtitle: Text(
                            context.l10n.text('originalOcrPreserved'),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(
                                ButlerlySpacing.small,
                              ),
                              child: SelectableText(_ocrResult!.rawText),
                            ),
                          ],
                        ),
                      const SizedBox(height: ButlerlySpacing.section),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: Text(
                          _saving
                              ? context.l10n.text('saving')
                              : context.l10n.text('saveReceiptTransaction'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
