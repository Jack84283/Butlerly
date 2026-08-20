import 'dart:async';
import 'dart:io';

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
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
  DateTime _date = DateTime.now();
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Use this receipt?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520, maxWidth: 520),
          child: Image.file(File(source.path), fit: BoxFit.contain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Retake / Replace'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Use receipt'),
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
        const SnackBar(
          content: Text('Receipt could not be stored locally. Please retry.'),
        ),
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
      setState(() {
        _ocrResult = result;
        _merchantRaw.text = result.merchant ?? '';
        _amount.text = result.amount ?? '';
        if (result.currency != null) _currency.text = result.currency!;
        if (result.date != null) _date = result.date!;
        _merchantId = _match(result.merchant);
        _processing = false;
      });
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
      initialDate: _date,
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
        transactionDate: _iso(_date),
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
            'confirmedDate': _iso(_date),
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Capture receipt')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          if (_source == null) ...[
            const Text(
              'Add a receipt',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _camera,
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Take photo'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _photo,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Choose from Photos'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _file,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Choose image from Files'),
            ),
          ] else ...[
            SizedBox(
              height: 220,
              child: Image.file(File(_source!.path), fit: BoxFit.contain),
            ),
            if (_processing) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Reading receipt on this device…'),
            ],
            if (!_processing) ...[
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _camera,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retake'),
                  ),
                  TextButton.icon(
                    onPressed: _photo,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Replace'),
                  ),
                ],
              ),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _merchantRaw,
                      decoration: const InputDecoration(
                        labelText: 'Merchant / source text',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _merchantId,
                      decoration: const InputDecoration(
                        labelText: 'Normalized merchant',
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
                      onChanged: (value) => setState(() => _merchantId = value),
                    ),
                    TextFormField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Total amount',
                      ),
                      validator: (value) {
                        try {
                          DecimalValue.parse(value?.trim() ?? '');
                          return null;
                        } on DomainValidationException {
                          return 'Enter a valid amount.';
                        }
                      },
                    ),
                    TextFormField(
                      controller: _currency,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(labelText: 'Currency'),
                      validator: (value) {
                        try {
                          CurrencyCode(value?.trim() ?? '');
                          return null;
                        } on DomainValidationException {
                          return 'Enter a valid currency code.';
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Purchase date'),
                      subtitle: Text(_iso(_date)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: _pickDate,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _categoryId,
                      decoration: const InputDecoration(
                        labelText: 'Category / subcategory',
                      ),
                      items: [
                        for (final category in _categories.where(
                          (value) => value.status == CategoryStatus.active,
                        ))
                          DropdownMenuItem(
                            value: category.id.value,
                            child: Text(category.name),
                          ),
                      ],
                      onChanged: (value) => setState(() => _categoryId = value),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentSourceId,
                      decoration: const InputDecoration(
                        labelText: 'Payment source',
                      ),
                      items: [
                        for (final source in _sources.where(
                          (value) => value.status == PaymentSourceStatus.active,
                        ))
                          DropdownMenuItem(
                            value: source.id.value,
                            child: Text(source.displayIdentity ?? source.name),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _paymentSourceId = value),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
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
                    TextFormField(
                      controller: _notes,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Notes'),
                    ),
                    if (_ocrResult != null)
                      ExpansionTile(
                        title: const Text('Extracted source text'),
                        subtitle: const Text(
                          'Original OCR text is preserved without translation.',
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SelectableText(_ocrResult!.rawText),
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Text(
                        _saving ? 'Saving…' : 'Save receipt transaction',
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
