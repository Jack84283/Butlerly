import 'dart:async';
import 'dart:io';

import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/core/evidence/local_evidence_store.dart';
import 'package:butlerly/core/evidence/local_ocr_service.dart';
import 'package:butlerly/core/evidence/platform_ocr_recognizer.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_responsive_body.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_controls.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/reconciliation_labels.dart';
import 'package:butlerly/features/foundation/presentation/transaction_change_notifier.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart' as files;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

final class ReceiptCaptureInitialData {
  const ReceiptCaptureInitialData({
    required this.preference,
    required this.snapshot,
  });

  final UserPreference? preference;
  final TransactionMasterDataSnapshot snapshot;
}

final class _ReceiptSaveSnapshot {
  const _ReceiptSaveSnapshot({
    required this.amount,
    required this.currency,
    required this.merchantRaw,
    required this.date,
    required this.paymentSourceId,
    required this.merchantId,
    required this.categoryId,
    required this.subcategoryId,
    required this.tagIds,
    required this.notes,
  });

  final String amount;
  final String currency;
  final String merchantRaw;
  final DateTime date;
  final String? paymentSourceId;
  final String? merchantId;
  final String? categoryId;
  final String? subcategoryId;
  final List<String> tagIds;
  final String notes;
}

class ReceiptCapturePage extends StatefulWidget {
  const ReceiptCapturePage({
    this.finance,
    this.evidenceStore,
    this.ocr,
    this.ocrRecognizer,
    this.pickImage,
    this.openFile,
    this.preserveEvidence,
    this.fileForPreserved,
    this.discardPreserved,
    this.attachPreserved,
    this.preparePendingReceipt,
    this.markPendingReceiptCommitted,
    this.rebindPendingReceipt,
    this.completePendingReceipt,
    this.listPendingReceiptCaptures,
    this.cancelPendingReceiptCapture,
    this.loadInitialData,
    super.key,
  });

  final FinanceServices? finance;
  final LocalEvidenceStore? evidenceStore;
  final Future<ReceiptOcrResult> Function(String path)? ocr;
  final OcrRecognizer? ocrRecognizer;
  final Future<XFile?> Function(ImageSource source)? pickImage;
  final Future<files.XFile?> Function(files.XTypeGroup group)? openFile;
  final Future<PreservedEvidenceSource> Function(XFile source)?
  preserveEvidence;
  final Future<File?> Function(PreservedEvidenceSource source)?
  fileForPreserved;
  final Future<void> Function(PreservedEvidenceSource source)? discardPreserved;
  final Future<EvidenceItem?> Function(
    String transactionId,
    PreservedEvidenceSource source,
  )?
  attachPreserved;
  final Future<void> Function(
    String transactionId,
    PreservedEvidenceSource source,
  )?
  preparePendingReceipt;
  final Future<bool> Function(String captureId, String transactionId)?
  markPendingReceiptCommitted;
  final Future<void> Function(String captureId, String transactionId)?
  rebindPendingReceipt;
  final Future<bool> Function(String transactionId)? completePendingReceipt;
  final Future<List<PendingReceiptCapture>> Function()?
  listPendingReceiptCaptures;
  final Future<bool> Function(String captureId)? cancelPendingReceiptCapture;
  final Future<ReceiptCaptureInitialData> Function()? loadInitialData;

  @override
  State<ReceiptCapturePage> createState() => _ReceiptCapturePageState();
}

String _paymentSourceLabel(PaymentSource source) => source.lastFour == null
    ? (source.displayIdentity ?? source.name)
    : '${source.displayIdentity ?? source.name} ••••${source.lastFour}';

class _ReceiptCapturePageState extends State<ReceiptCapturePage> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _currency = TextEditingController(text: 'USD');
  final _merchantRaw = TextEditingController();
  final _notes = TextEditingController();

  XFile? _source;
  PreservedEvidenceSource? _preserved;
  ReceiptOcrResult? _ocrResult;
  DateTime? _date;
  bool _dateNeedsReview = false;
  bool _processing = false;
  bool _captureInFlight = false;
  bool _saving = false;
  String? _pendingReceiptCaptureId;
  String? _pendingReceiptTargetTransactionId;
  EvidenceItem? _plannedPendingEvidence;
  String? _merchantId;
  String? _categoryId;
  String? _subcategoryId;
  String? _paymentSourceId;
  final Set<String> _tagIds = {};
  bool _classificationOverridden = false;
  int _classificationRequest = 0;
  List<Merchant> _merchants = const [];
  List<Category> _categories = const [];
  List<Tag> _tags = const [];
  List<PaymentSource> _sources = const [];
  TransactionMasterDataSnapshot? _masterDataSnapshot;
  List<PendingReceiptCapture> _pendingReceiptRecoveries = const [];
  List<PendingGenericCapture> _pendingGenericRecoveries = const [];
  List<PendingCaptureJournalIssue> _pendingRecoveryIssues = const [];
  TransactionMasterData get _masterData =>
      _masterDataSnapshot?.presentation ?? const TransactionMasterData();

  FinanceServices get finance => widget.finance ?? services<FinanceServices>();
  LocalEvidenceStore get evidenceStore =>
      widget.evidenceStore ?? services<LocalEvidenceStore>();

  @override
  void initState() {
    super.initState();
    _merchantRaw.addListener(_handleDescriptionChanged);
    _load();
  }

  @override
  void dispose() {
    // A source with no committed transaction remains recoverable after route
    // disposal. Only the explicit recovery discard or a completed save may
    // retire its journal and pending binary.
    _amount.dispose();
    _currency.dispose();
    _merchantRaw.removeListener(_handleDescriptionChanged);
    _merchantRaw.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _handleDescriptionChanged() {
    if (_classificationOverridden) return;
    unawaited(_refreshClassification());
  }

  Future<void> _refreshClassification() async {
    final request = ++_classificationRequest;
    final result = await finance.proposeTransactionClassification(
      merchantId: _merchantId == null ? null : MerchantId(_merchantId!),
      description: _merchantRaw.text.trim(),
    );
    if (!mounted ||
        request != _classificationRequest ||
        _classificationOverridden) {
      return;
    }
    if (result case ApplicationSuccess<ClassificationProposal>(
      value: final proposal,
    )) {
      setState(() {
        if (_merchantId == null && proposal.merchantId != null) {
          _merchantId = proposal.merchantId!.value;
        }
        _categoryId = proposal.categoryId?.value;
        _subcategoryId = proposal.subcategoryId?.value;
      });
    }
  }

  Future<void> _selectMerchant(String? value) async {
    setState(() => _merchantId = value);
    if (!_classificationOverridden) await _refreshClassification();
  }

  Future<void> _load() async {
    if (widget.loadInitialData != null) {
      final initial = await widget.loadInitialData!();
      if (!mounted) return;
      _applyInitialData(initial);
      await _loadPendingReceiptRecovery();
      return;
    }
    final preferenceResult = await finance.loadUserPreference();
    final preference = preferenceResult is ApplicationSuccess<UserPreference?>
        ? preferenceResult.value
        : null;
    final snapshot = await TransactionMasterDataProvider(
      finance,
    ).load(languageCode: preference?.locale ?? 'en');
    if (!mounted) return;
    _applyInitialData(
      ReceiptCaptureInitialData(preference: preference, snapshot: snapshot),
    );
    await _loadPendingReceiptRecovery();
  }

  Future<void> _loadPendingReceiptRecovery() async {
    if (widget.loadInitialData != null &&
        widget.listPendingReceiptCaptures == null) {
      return;
    }
    try {
      final pending = widget.listPendingReceiptCaptures == null
          ? await evidenceStore.listPendingReceiptCaptures()
          : await widget.listPendingReceiptCaptures!();
      final generic = widget.listPendingReceiptCaptures != null
          ? const <PendingGenericCapture>[]
          : await evidenceStore.listPendingGenericCaptures(
              captureKind: 'receipt',
            );
      final issues = widget.listPendingReceiptCaptures != null
          ? const <PendingCaptureJournalIssue>[]
          : await evidenceStore.listPendingCaptureJournalIssues();
      if (!mounted) return;
      setState(() {
        _pendingReceiptRecoveries = pending;
        _pendingGenericRecoveries = generic;
        _pendingRecoveryIssues = issues;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _pendingRecoveryIssues = const [
            PendingCaptureJournalIssue(
              fileName: 'pending-capture-scan',
              messageKey: 'captureRecoveryJournalIssue',
            ),
          ],
        );
      }
    }
  }

  void _applyInitialData(ReceiptCaptureInitialData initial) {
    setState(() {
      _masterDataSnapshot = initial.snapshot;
      _merchants = initial.snapshot.merchants;
      _categories = initial.snapshot.categories;
      _tags = initial.snapshot.tags;
      _sources = initial.snapshot.paymentSources;
      if (initial.preference != null) {
        _currency.text = initial.preference!.baseCurrency.value;
      }
    });
  }

  Future<void> _camera() async {
    if (_saving || _captureInFlight) return;
    _captureInFlight = true;
    try {
      final source = widget.pickImage != null
          ? await widget.pickImage!(ImageSource.camera)
          : await ImagePicker().pickImage(
              source: ImageSource.camera,
              imageQuality: 95,
              requestFullMetadata: false,
            );
      if (source != null) await _process(source);
    } catch (_) {
      _showSaveMessage('receiptCaptureFailed');
    } finally {
      _captureInFlight = false;
    }
  }

  Future<void> _photo() async {
    if (_saving || _captureInFlight) return;
    _captureInFlight = true;
    try {
      final source = widget.pickImage != null
          ? await widget.pickImage!(ImageSource.gallery)
          : await ImagePicker().pickImage(
              source: ImageSource.gallery,
              imageQuality: 100,
              requestFullMetadata: false,
            );
      if (source != null) await _process(source);
    } catch (_) {
      _showSaveMessage('receiptCaptureFailed');
    } finally {
      _captureInFlight = false;
    }
  }

  Future<void> _file() async {
    if (_saving || _captureInFlight) return;
    _captureInFlight = true;
    try {
      final group = files.XTypeGroup(
        label: context.l10n.text('receiptImages'),
        extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
      );
      final source = widget.openFile != null
          ? await widget.openFile!(group)
          : await files.openFile(acceptedTypeGroups: [group]);
      if (source != null) {
        await _process(XFile(source.path, name: source.name));
      }
    } catch (_) {
      _showSaveMessage('receiptCaptureFailed');
    } finally {
      _captureInFlight = false;
    }
  }

  Future<void> _process(XFile source) async {
    if (_saving || _processing) return;
    final l10n = context.l10n;
    setState(() => _processing = true);
    // Preserve the selected source before opening confirmation. A process
    // stop or route interruption while the sheet is open must not discard the
    // only app-owned recovery copy.
    PreservedEvidenceSource preserved;
    try {
      preserved = widget.preserveEvidence == null
          ? await evidenceStore.preserve(source, captureKind: 'receipt')
          : await widget.preserveEvidence!(source);
    } catch (_) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.text('receiptStoreFailed'))));
      await _loadPendingReceiptRecovery();
      return;
    }
    if (!mounted) return;

    bool? confirmed;
    try {
      confirmed = await showButlerlyBottomSheet<bool>(
        context: context,
        builder: (dialogContext) => ButlerlySheet(
          title: Text(l10n.text('receiptUseTitle')),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520, maxWidth: 520),
            child: Image.file(File(source.path), fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.text('receiptRetakeReplace')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.text('receiptUse')),
            ),
          ],
        ),
      );
    } catch (_) {
      // Keep the generic recovery record when confirmation itself fails. The
      // source is not explicitly cancelled and remains available to retry.
      if (mounted) {
        setState(() => _processing = false);
        _showSaveMessage('receiptStoreFailed');
        await _loadPendingReceiptRecovery();
      }
      return;
    }
    if (confirmed != true) {
      // A visible negative confirmation is the one point at which it is safe
      // to retire the generic recovery copy. If the route disappeared, retain
      // it because disposal is not explicit cancellation.
      if (!mounted) return;
      try {
        await _discard(preserved);
      } catch (_) {
        _showSaveMessage('receiptRecoveryWarning');
        await _loadPendingReceiptRecovery();
        if (mounted) setState(() => _processing = false);
        return;
      }
      if (mounted) setState(() => _processing = false);
      return;
    }
    if (!mounted) return;

    File? stableFile;
    String? captureId;
    final previous = _preserved;
    final previousCaptureId = _pendingReceiptCaptureId;
    try {
      final captured = preserved;
      captureId = 'transaction-${DateTime.now().microsecondsSinceEpoch}';
      final planned = await _preparePendingReceipt(captureId, captured);
      stableFile = widget.fileForPreserved == null
          ? await evidenceStore.fileForPreserved(captured)
          : await widget.fileForPreserved!(captured);
      if (stableFile == null || !await stableFile.exists()) {
        throw const FileSystemException('Preserved receipt is unavailable.');
      }
      if (previousCaptureId != null) {
        if (!await _cancelPendingReceipt(previousCaptureId)) {
          throw StateError('Previous receipt capture could not be replaced.');
        }
        // Test and embedded callers may own a private journal whose cancel
        // callback does not remove its preserved file. The production store
        // removes both the typed journal and its generic source together.
        if (previous != null && widget.preparePendingReceipt != null) {
          await _discard(previous);
        }
      }
      _preserved = captured;
      _pendingReceiptCaptureId = captureId;
      _pendingReceiptTargetTransactionId = null;
      _plannedPendingEvidence = planned;
    } catch (_) {
      // The generic pre-capture manifest is the only durable recovery record
      // until the typed receipt journal is prepared. Keep it when any later
      // preparation or source lookup step fails; navigation is not explicit
      // cancellation.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('receiptStoreFailed'))),
      );
      if (mounted) setState(() => _processing = false);
      await _loadPendingReceiptRecovery();
      return;
    }
    final captured = preserved;
    final capturedFile = stableFile;
    if (!mounted) {
      // The specific receipt journal now owns the preserved source. The
      // transaction may not exist yet, so startup must retain this source and
      // offer recovery instead of treating route disposal as cancellation.
      return;
    }

    await _reviewPreservedReceipt(captured, capturedFile);
  }

  Future<void> _reviewPreservedReceipt(
    PreservedEvidenceSource captured,
    File capturedFile,
  ) async {
    final stableSource = XFile(
      capturedFile.path,
      name: captured.originalName,
      mimeType: captured.mediaType,
    );
    setState(() {
      _preserved = captured;
      _source = stableSource;
      _ocrResult = null;
      _dateNeedsReview = false;
    });

    try {
      final result = await _recognizeReceipt(stableSource.path);
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
      await _refreshClassification();
    } catch (_) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('receiptTextReadFailed'))),
      );
    }
  }

  Future<void> _resumePendingReceipt(PendingReceiptCapture pending) async {
    if (_saving || _processing) return;
    final file = widget.fileForPreserved == null
        ? await evidenceStore.fileForPreserved(pending.source)
        : await widget.fileForPreserved!(pending.source);
    if (file == null || !await file.exists()) {
      _showSaveMessage('receiptRecoverySourceUnavailable');
      return;
    }
    setState(() {
      _pendingReceiptRecoveries = _pendingReceiptRecoveries
          .where((value) => value.captureId != pending.captureId)
          .toList(growable: false);
      _pendingReceiptCaptureId = pending.captureId;
      _pendingReceiptTargetTransactionId =
          pending.transactionId == pending.captureId
          ? null
          : pending.transactionId;
      _plannedPendingEvidence = pending.plannedEvidence;
      _preserved = pending.source;
      _processing = true;
    });
    await _reviewPreservedReceipt(pending.source, file);
  }

  Future<void> _discardPendingReceiptRecovery(
    PendingReceiptCapture pending,
  ) async {
    try {
      final cancelled = widget.cancelPendingReceiptCapture == null
          ? await evidenceStore.cancelPendingReceiptCapture(pending.captureId)
          : await widget.cancelPendingReceiptCapture!(pending.captureId);
      if (cancelled && mounted) {
        _showSaveMessage('receiptRecoveryDiscarded');
        await _loadPendingReceiptRecovery();
      }
    } catch (_) {
      _showSaveMessage('receiptStoreFailed');
    }
  }

  Future<void> _resumePendingGenericReceipt(
    PendingGenericCapture pending,
  ) async {
    if (_saving || _processing) return;
    final file = widget.fileForPreserved == null
        ? await evidenceStore.fileForPreserved(pending.source)
        : await widget.fileForPreserved!(pending.source);
    if (file == null || !await file.exists()) {
      _showSaveMessage('receiptRecoverySourceUnavailable');
      return;
    }
    final captureId = 'transaction-${DateTime.now().microsecondsSinceEpoch}';
    EvidenceItem? planned;
    try {
      planned = await _preparePendingReceipt(captureId, pending.source);
    } catch (_) {
      _showSaveMessage('receiptStoreFailed');
      return;
    }
    setState(() {
      _pendingGenericRecoveries = _pendingGenericRecoveries
          .where(
            (value) =>
                value.source.localFileName != pending.source.localFileName,
          )
          .toList(growable: false);
      _pendingReceiptCaptureId = captureId;
      _pendingReceiptTargetTransactionId = null;
      _plannedPendingEvidence = planned;
      _preserved = pending.source;
      _processing = true;
    });
    await _reviewPreservedReceipt(pending.source, file);
  }

  Future<void> _discardPendingGenericReceipt(
    PendingGenericCapture pending,
  ) async {
    try {
      final discarded = await evidenceStore.discardPendingGenericCapture(
        pending.source,
      );
      if (discarded && mounted) {
        _showSaveMessage('receiptRecoveryDiscarded');
        await _loadPendingReceiptRecovery();
      } else if (mounted) {
        _showSaveMessage('receiptRecoveryWarning');
        await _loadPendingReceiptRecovery();
      }
    } catch (_) {
      _showSaveMessage('receiptStoreFailed');
    }
  }

  Future<void> _repairPendingRecoveryIssue(String fileName) async {
    try {
      final resolution = await evidenceStore.resolvePendingCaptureJournalIssue(
        fileName,
        captureKind: 'receipt',
      );
      if (!mounted) return;
      _showSaveMessage(switch (resolution) {
        PendingCaptureJournalResolution.repaired => 'captureRecoveryRepaired',
        PendingCaptureJournalResolution.dismissed => 'captureRecoveryDismissed',
        PendingCaptureJournalResolution.unavailable =>
          'captureRecoveryRepairUnavailable',
      });
      await _loadPendingReceiptRecovery();
    } catch (_) {
      _showSaveMessage('captureRecoveryRepairUnavailable');
    }
  }

  Future<void> _dismissPendingRecoveryIssue(String fileName) async {
    final l10n = context.l10n;
    final confirmed = await showButlerlyConfirmationSheet(
      context: context,
      title: l10n.text('captureRecoveryDismissTitle'),
      message: l10n.text('captureRecoveryDismissBody'),
      cancelLabel: l10n.text('cancel'),
      confirmLabel: l10n.text('captureRecoveryDismiss'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      final resolution = await evidenceStore.dismissPendingCaptureJournalIssue(
        fileName,
      );
      if (!mounted) return;
      _showSaveMessage(switch (resolution) {
        PendingCaptureJournalResolution.dismissed => 'captureRecoveryDismissed',
        _ => 'captureRecoveryRepairUnavailable',
      });
      await _loadPendingReceiptRecovery();
    } catch (_) {
      if (mounted) _showSaveMessage('captureRecoveryRepairUnavailable');
    }
  }

  Future<ReceiptOcrResult> _recognizeReceipt(String path) async {
    if (widget.ocr != null) return widget.ocr!(path);
    final recognizer =
        widget.ocrRecognizer ??
        (services.isRegistered<OcrRecognizer>()
            ? services<OcrRecognizer>()
            : platformOcrRecognizer());
    final document = await recognizer.recognize(
      OcrRequest(
        source: OcrSource(path: path, kind: OcrSourceKind.image),
        intent: OcrIntent.receipt,
      ),
    );
    if (document.text.trim().isEmpty) {
      throw const FormatException('No readable receipt text was found.');
    }
    return ReceiptExtractor.extract(document.text, document.observations);
  }

  Future<void> _discard(PreservedEvidenceSource source) =>
      widget.discardPreserved == null
      ? evidenceStore.discardPreserved(source)
      : widget.discardPreserved!(source);

  Future<EvidenceItem?> _attachWithinMutation(
    String transactionId,
    PreservedEvidenceSource source, {
    EvidenceItem? planned,
  }) => widget.attachPreserved == null
      ? evidenceStore.attachPreservedAndReturnWithinMutation(
          transactionId: transactionId,
          source: source,
          planned: planned,
        )
      : widget.attachPreserved!(transactionId, source);

  Future<EvidenceItem?> _preparePendingReceipt(
    String transactionId,
    PreservedEvidenceSource source,
  ) async {
    if (widget.preparePendingReceipt != null) {
      await widget.preparePendingReceipt!(transactionId, source);
      return null;
    }
    return evidenceStore.preparePendingReceiptCapture(
      transactionId: transactionId,
      source: source,
    );
  }

  Future<bool> _completePendingReceipt(String transactionId) =>
      widget.completePendingReceipt == null
      ? evidenceStore.completePendingReceiptCaptureWithinMutation(transactionId)
      : widget.completePendingReceipt!(transactionId);

  Future<bool> _cancelPendingReceipt(String captureId) {
    final cancel = widget.cancelPendingReceiptCapture;
    if (cancel != null) return cancel(captureId);
    // Embedded callers that provide their own preparation callback also own
    // the corresponding journal lifecycle. There is no safe generic cancel
    // operation for that private journal, so leave it to the owner rather
    // than completing it or touching the application's store.
    if (widget.preparePendingReceipt != null) return Future.value(true);
    return evidenceStore.cancelPendingReceiptCaptureWithinMutation(captureId);
  }

  Future<bool> _markPendingReceiptCommitted(
    String captureId,
    String transactionId,
  ) {
    if (widget.markPendingReceiptCommitted != null) {
      return widget.markPendingReceiptCommitted!(captureId, transactionId);
    }
    // Embedded callers that provide their own preparation callback own the
    // corresponding journal lifecycle as well.
    if (widget.preparePendingReceipt != null) return Future.value(true);
    return evidenceStore
        .markPendingReceiptCaptureTransactionCommittedWithinMutation(
          captureId: captureId,
          transactionId: transactionId,
        );
  }

  Future<void> _rebindPendingReceipt(
    String captureId,
    String transactionId,
  ) async {
    if (widget.rebindPendingReceipt != null) {
      await widget.rebindPendingReceipt!(captureId, transactionId);
      return;
    }
    await evidenceStore.rebindPendingReceiptCaptureWithinMutation(
      captureId: captureId,
      transactionId: transactionId,
    );
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

  Future<List<ReconciliationMatchCandidate>> _findExistingPaymentMatches(
    _ReceiptSaveSnapshot snapshot,
  ) async {
    if (snapshot.amount.isEmpty) return const [];
    final result = await finance.findReceiptPaymentMatch.callAll(
      ReceiptPaymentMatchCommand(
        amount: Money(
          amount: DecimalValue.parse(snapshot.amount),
          currency: CurrencyCode(snapshot.currency),
        ),
        currency: snapshot.currency,
        transactionDate: _iso(snapshot.date),
        merchant: snapshot.merchantRaw,
        paymentSourceId: snapshot.paymentSourceId,
      ),
    );
    return result is ApplicationSuccess<List<ReconciliationMatchCandidate>>
        ? result.value
        : const [];
  }

  Future<ReconciliationMatchCandidate?> _selectExistingMatch(
    List<ReconciliationMatchCandidate> candidates,
  ) {
    return showButlerlyBottomSheet<ReconciliationMatchCandidate>(
      context: context,
      builder: (dialogContext) => ButlerlySheet(
        title: Text(dialogContext.l10n.text('existingTransactionFound')),
        content: Text(dialogContext.l10n.text('existingTransactionFound')),
        actions: [
          for (final candidate in candidates)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, candidate),
              child: Text(
                '${candidate.transaction.currency} ${localizedTransactionAmount(context, candidate.transaction.amount)} · ${candidate.transaction.transactionDate}\n${candidate.transaction.description ?? candidate.transaction.rawCounterparty ?? ''}\n${localizedReconciliationReasons(context, candidate.assessment.reasons)}',
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.l10n.text('notThisTransaction')),
          ),
        ],
      ),
    );
  }

  void _showSaveMessage(String key) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.text(key))));
  }

  Extraction? _buildExtraction(
    EvidenceItem evidence,
    ReceiptOcrResult? ocr,
    String token,
    _ReceiptSaveSnapshot snapshot,
  ) {
    if (ocr == null) return null;
    return Extraction(
      id: ExtractionId('extraction-$token'),
      evidenceId: evidence.id,
      values: {
        ...ocr.toExtractionValues(),
        'confirmedAmount': snapshot.amount,
        'confirmedCurrency': snapshot.currency,
        'confirmedDate': _iso(snapshot.date),
      },
      provenance: Provenance(
        id: ProvenanceId('extraction-provenance-$token'),
        sourceType: ProvenanceSourceType.evidenceExtraction,
        capturedAt: DateTime.now().toUtc(),
        originalRepresentation: ocr.rawText,
      ),
      createdAt: DateTime.now().toUtc(),
    );
  }

  Future<void> _persistExtractionBestEffort(
    FinanceServices financeForSave,
    Extraction extraction,
  ) async {
    try {
      await financeForSave.saveExtraction(extraction);
    } catch (_) {
      // Transaction + receipt evidence are already durable. Extraction metadata
      // is derived and must never make the canonical save appear to fail.
    }
  }

  void _finishCommittedSave({
    required EvidenceItem evidence,
    required ReceiptOcrResult? ocr,
    required String extractionToken,
    required _ReceiptSaveSnapshot snapshot,
  }) {
    notifyTransactionChanged();
    try {
      final extraction = _buildExtraction(
        evidence,
        ocr,
        extractionToken,
        snapshot,
      );
      if (extraction != null) {
        final financeForSave = finance;
        unawaited(_persistExtractionBestEffort(financeForSave, extraction));
      }
    } catch (_) {
      // Derived extraction must not invalidate an already committed receipt.
    }
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context, true);
  }

  Future<bool> _rollbackCreatedTransaction(String transactionId) async {
    try {
      final result = await evidenceStore
          .deleteTransactionPermanentlyWithinMutation(transactionId);
      if (result is ApplicationSuccess<void>) return true;
      if (result is ApplicationFailure<void> &&
          result.failure.code == ApplicationFailureCode.notFound) {
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _attachReceiptToExisting(
    TransactionDto transaction, {
    required _ReceiptSaveSnapshot snapshot,
  }) async {
    final preserved = _preserved;
    final ocr = _ocrResult;
    if (preserved == null) {
      _showSaveMessage('receiptStoreFailed');
      return;
    }
    final captureId = _pendingReceiptCaptureId;
    if (captureId == null) {
      _showSaveMessage('receiptStoreFailed');
      return;
    }
    setState(() => _saving = true);
    EvidenceItem? evidence;
    try {
      await evidenceStore.runFinancialEvidenceMutation(() async {
        await _rebindPendingReceipt(captureId, transaction.id);
        if (!await _markPendingReceiptCommitted(captureId, transaction.id)) {
          throw StateError('Receipt capture journal is unavailable.');
        }
        evidence = await _attachWithinMutation(
          transaction.id,
          preserved,
          planned: _plannedPendingEvidence,
        );
      });
    } catch (_) {
      evidence = null;
    }
    final committedEvidence = evidence;
    if (committedEvidence == null) {
      if (mounted) {
        setState(() => _saving = false);
        _showSaveMessage('evidenceAttachFailed');
      }
      return;
    }
    if (await _completePendingReceipt(captureId)) {
      _pendingReceiptCaptureId = null;
      _pendingReceiptTargetTransactionId = null;
      _plannedPendingEvidence = null;
    }
    _finishCommittedSave(
      evidence: committedEvidence,
      ocr: ocr,
      extractionToken: committedEvidence.id.value,
      snapshot: snapshot,
    );
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
    if (_saving) return;
    final value = await showButlerlyDatePicker(
      context: context,
      title: context.l10n.text('date'),
      cancelLabel: context.l10n.text('cancel'),
      doneLabel: context.l10n.text('done'),
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (value != null && mounted) {
      setState(() {
        _date = value;
        _dateNeedsReview = false;
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final source = _source;
    final preserved = _preserved;
    if (source == null || preserved == null) {
      _showSaveMessage('receiptStoreFailed');
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_date == null) {
      setState(() => _dateNeedsReview = true);
      _showSaveMessage('dateNeedsReview');
      await _pickDate();
      if (!mounted || _date == null) return;
    }

    final snapshot = _ReceiptSaveSnapshot(
      amount: _amount.text.trim(),
      currency: _currency.text.trim().toUpperCase(),
      merchantRaw: _merchantRaw.text.trim(),
      date: _date!,
      paymentSourceId: _paymentSourceId,
      merchantId: _merchantId,
      categoryId: _categoryId,
      subcategoryId: _subcategoryId,
      tagIds: List.unmodifiable(_tagIds),
      notes: _notes.text.trim(),
    );

    setState(() => _saving = true);

    try {
      final pendingTargetId = _pendingReceiptTargetTransactionId;
      if (pendingTargetId != null) {
        final target = await finance.getTransaction.call(pendingTargetId);
        if (target is ApplicationSuccess<TransactionDto>) {
          await _attachReceiptToExisting(target.value, snapshot: snapshot);
        } else if (mounted) {
          setState(() => _saving = false);
          _showSaveMessage('dataPreserved');
        }
        return;
      }
      // Check strict duplicates immediately before creating anything so the
      // final decision uses the values the user actually approved.
      final proposed = TransactionDto(
        id: '__receipt-proposed__',
        amount: snapshot.amount,
        currency: snapshot.currency,
        direction: TransactionDirection.expense.name,
        status: TransactionStatus.active.name,
        reviewState: TransactionReviewState.clear.name,
        transactionDate: _iso(snapshot.date),
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        description: snapshot.merchantRaw.isEmpty
            ? 'Receipt purchase'
            : snapshot.merchantRaw,
        rawCounterparty: snapshot.merchantRaw.isEmpty
            ? null
            : snapshot.merchantRaw,
        paymentSourceId: snapshot.paymentSourceId,
        merchantId: snapshot.merchantId,
        categoryId: snapshot.categoryId,
        tagIds: snapshot.tagIds,
      );
      final duplicate = await finance.duplicateTransactionChecker.call(
        DuplicateTransactionCheckCommand(
          transactionDate: proposed.transactionDate!,
          amount: proposed.amount,
          currency: proposed.currency,
          direction: TransactionDirection.expense,
          paymentSourceId: snapshot.paymentSourceId,
          merchantId: snapshot.merchantId,
        ),
      );
      final approvedDuplicateIds = <String>{};
      if (!mounted) return;
      if (duplicate is! ApplicationSuccess<DuplicateTransactionCheckResult>) {
        setState(() => _saving = false);
        _showSaveMessage('duplicateCheckUnavailable');
        return;
      }
      if (duplicate case ApplicationSuccess<DuplicateTransactionCheckResult>(
        value: final check,
      ) when check.requiresConfirmation) {
        final decision =
            await showButlerlyBottomSheet<ButlerlyDuplicateConfirmationResult>(
              context: context,
              builder: (dialogContext) =>
                  ButlerlyDuplicateTransactionConfirmation(
                    proposed: proposed,
                    candidates: check.candidates,
                    paymentSourceLabels: {
                      for (final source in _sources)
                        source.id.value: _paymentSourceLabel(source),
                    },
                    onDecision: (value) => Navigator.pop(dialogContext, value),
                  ),
            );
        if (!mounted) return;
        if (decision == null ||
            decision.decision == ButlerlyDuplicateDecision.cancel) {
          setState(() => _saving = false);
          return;
        }
        if (decision.decision == ButlerlyDuplicateDecision.useExisting) {
          final selectedId = decision.selectedTransactionId;
          final selected = check.candidates
              .where((candidate) => candidate.transaction.id == selectedId)
              .firstOrNull;
          if (selected != null) {
            await _attachReceiptToExisting(
              selected.transaction,
              snapshot: snapshot,
            );
          } else if (mounted) {
            setState(() => _saving = false);
            _showSaveMessage('dataPreserved');
          }
          return;
        }
        approvedDuplicateIds.addAll(
          check.candidates.map((candidate) => candidate.transaction.id),
        );
      }

      // Reconciliation is deliberately separate from strict duplicate identity.
      final matches = await _findExistingPaymentMatches(snapshot);
      if (matches.isNotEmpty && mounted) {
        final selected = await _selectExistingMatch(matches);
        if (selected != null) {
          await _attachReceiptToExisting(
            selected.transaction,
            snapshot: snapshot,
          );
          return;
        }
      }

      final token = DateTime.now().microsecondsSinceEpoch;
      final transactionId = _pendingReceiptCaptureId ?? 'transaction-$token';
      final outcome = await evidenceStore.runFinancialEvidenceMutation(
        () async {
          final latestDuplicate = await finance.duplicateTransactionChecker
              .call(
                DuplicateTransactionCheckCommand(
                  transactionDate: proposed.transactionDate!,
                  amount: proposed.amount,
                  currency: proposed.currency,
                  direction: TransactionDirection.expense,
                  paymentSourceId: snapshot.paymentSourceId,
                  merchantId: snapshot.merchantId,
                ),
              );
          if (latestDuplicate
              is! ApplicationSuccess<DuplicateTransactionCheckResult>) {
            return (
              result: null,
              evidence: null,
              rolledBack: true,
              duplicateConflict: false,
              duplicateUnavailable: true,
            );
          }
          if (latestDuplicate
              case ApplicationSuccess<DuplicateTransactionCheckResult>(
                value: final check,
              )
              when check.requiresConfirmation &&
                  check.candidates.any(
                    (candidate) => !approvedDuplicateIds.contains(
                      candidate.transaction.id,
                    ),
                  )) {
            return (
              result: null,
              evidence: null,
              rolledBack: true,
              duplicateConflict: true,
              duplicateUnavailable: false,
            );
          }
          final result = await finance.createReceiptTransaction(
            ReceiptTransactionCommand(
              id: transactionId,
              provenanceId: 'receipt-transaction-$token',
              money: Money(
                amount: DecimalValue.parse(snapshot.amount),
                currency: CurrencyCode(snapshot.currency),
              ),
              transactionDate: _iso(snapshot.date),
              originalRepresentation: source.name,
              rawCounterparty: snapshot.merchantRaw.isEmpty
                  ? null
                  : snapshot.merchantRaw,
              description: snapshot.merchantRaw.isEmpty
                  ? 'Receipt purchase'
                  : snapshot.merchantRaw,
              notes: snapshot.notes.isEmpty ? null : snapshot.notes,
              merchantId: snapshot.merchantId,
              categoryId: snapshot.categoryId,
              subcategoryId: snapshot.subcategoryId,
              paymentSourceId: snapshot.paymentSourceId,
              tagIds: snapshot.tagIds,
            ),
          );
          if (result is! ApplicationSuccess<TransactionDto>) {
            return (
              result: result,
              evidence: null,
              rolledBack: true,
              duplicateConflict: false,
              duplicateUnavailable: false,
            );
          }
          if (!await _markPendingReceiptCommitted(
            transactionId,
            result.value.id,
          )) {
            throw StateError('Receipt capture journal is unavailable.');
          }
          final attached = await _attachWithinMutation(
            result.value.id,
            preserved,
            planned: _plannedPendingEvidence,
          );
          if (attached != null) {
            if (await _completePendingReceipt(transactionId)) {
              _pendingReceiptCaptureId = null;
              _plannedPendingEvidence = null;
            }
            return (
              result: result,
              evidence: attached,
              rolledBack: true,
              duplicateConflict: false,
              duplicateUnavailable: false,
            );
          }
          final rolledBack = await _rollbackCreatedTransaction(result.value.id);
          // Keep the capture journal even after a confirmed automatic
          // rollback. The source is still recoverable user data; only the
          // explicit recovery discard path may retire it.
          return (
            result: result,
            evidence: null,
            rolledBack: rolledBack,
            duplicateConflict: false,
            duplicateUnavailable: false,
          );
        },
      );
      final result = outcome.result;
      if (outcome.duplicateUnavailable) {
        if (mounted) {
          setState(() => _saving = false);
          _showSaveMessage('duplicateCheckUnavailable');
        }
        return;
      }
      if (outcome.duplicateConflict) {
        if (mounted) {
          setState(() => _saving = false);
          _showSaveMessage('duplicateReviewRequired');
        }
        return;
      }
      if (result is! ApplicationSuccess<TransactionDto>) {
        if (mounted) {
          setState(() => _saving = false);
          _showSaveMessage('dataPreserved');
        }
        return;
      }
      if (outcome.evidence == null) {
        if (!outcome.rolledBack) {
          // The durable receipt intent remains in the pending area. Keep its
          // source binary when rollback cannot complete so startup recovery
          // can attach it to the already-created transaction.
          notifyTransactionChanged();
          if (mounted) Navigator.pop(context, true);
        }
        if (mounted) {
          setState(() => _saving = false);
          _showSaveMessage('evidenceAttachFailed');
        }
        return;
      }
      _finishCommittedSave(
        evidence: outcome.evidence!,
        ocr: _ocrResult,
        extractionToken: token.toString(),
        snapshot: snapshot,
      );
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSaveMessage('dataPreserved');
      return;
    }

    // The create-and-attach path returns from the consistency boundary above.
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

    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final fieldGap = desktop ? ButlerlySpacing.micro : ButlerlySpacing.standard;

    final receiptForm = Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _merchantRaw,
            readOnly: _saving,
            decoration: InputDecoration(
              labelText: context.l10n.text('description'),
            ),
          ),
          SizedBox(height: fieldGap),
          ButlerlyMerchantSelector(
            merchants: _merchants,
            value: _merchantId,
            label: context.l10n.text('merchant'),
            clearLabel: context.l10n.text('clear'),
            onChanged: (value) => _selectMerchant(value),
          ),
          SizedBox(height: fieldGap),
          TextFormField(
            controller: _amount,
            readOnly: _saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: context.l10n.text('amount')),
            validator: (value) {
              try {
                DecimalValue.parse(value?.trim() ?? '');
                return null;
              } on DomainValidationException {
                return context.l10n.text('invalidAmount');
              }
            },
          ),
          SizedBox(height: fieldGap),
          TextFormField(
            controller: _currency,
            readOnly: _saving,
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
          SizedBox(height: fieldGap),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.text('purchaseDate')),
            subtitle: Text(_date == null ? '—' : _iso(_date!)),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: _saving ? null : _pickDate,
          ),
          if (_dateNeedsReview)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                context.l10n.text('dateNeedsReview'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          SizedBox(height: fieldGap),
          ButlerlyCategorySelector(
            label: context.l10n.text('category'),
            clearLabel: context.l10n.text('clear'),
            categories: activeCategories,
            masterData: _masterData,
            value: selectedParentId,
            onChanged: (value) {
              if (_saving) return;
              setState(() {
                _classificationOverridden = true;
                _categoryId = value;
                _subcategoryId = null;
              });
            },
          ),
          SizedBox(height: fieldGap),
          ButlerlySubcategorySelector(
            label: context.l10n.text('subcategory'),
            clearLabel: context.l10n.text('clear'),
            categories: activeCategories,
            masterData: _masterData,
            parentId: selectedParentId,
            value: _subcategoryId,
            onChanged: (value) {
              if (_saving) return;
              setState(() {
                _classificationOverridden = true;
                _subcategoryId = value;
                _categoryId = selectedParentId;
              });
            },
          ),
          SizedBox(height: fieldGap),
          ButlerlyPaymentSourceSelector(
            label: context.l10n.text('paymentSource'),
            clearLabel: context.l10n.text('clear'),
            sources: _sources,
            value: _paymentSourceId,
            onChanged: (value) {
              if (!_saving) setState(() => _paymentSourceId = value);
            },
          ),
          SizedBox(height: fieldGap),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: ButlerlySpacing.compact,
              runSpacing: ButlerlySpacing.micro,
              children: [
                ButlerlyTagPicker(
                  searchLabel: context.l10n.text('search'),
                  createLabel: context.l10n.text('addTag'),
                  tags: _tags,
                  masterData: _masterData,
                  selected: _tagIds,
                  onChanged: (value) {
                    if (_saving) return;
                    setState(() {
                      _tagIds
                        ..clear()
                        ..addAll(value);
                    });
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: fieldGap),
          TextFormField(
            controller: _notes,
            readOnly: _saving,
            maxLines: 2,
            decoration: InputDecoration(labelText: context.l10n.text('notes')),
          ),
          if (_ocrResult != null)
            ExpansionTile(
              title: Text(context.l10n.text('extractedSourceText')),
              subtitle: Text(context.l10n.text('originalOcrPreserved')),
              children: [
                Padding(
                  padding: const EdgeInsets.all(ButlerlySpacing.small),
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
    );
    return PopScope(
      canPop: !_saving && !_processing && !_captureInFlight,
      child: Scaffold(
        appBar: AppBar(title: Text(context.l10n.text('captureReceipt'))),
        body: SafeArea(
          child: ButlerlyResponsiveBody(
            contentKey: const ValueKey('receipt-capture-content'),
            fullWidth: desktop,
            child: ListView(
              padding: const EdgeInsets.all(ButlerlySpacing.standard),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (_pendingRecoveryIssues.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(ButlerlySpacing.standard),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(context.l10n.text('receiptRecoveryWarning')),
                          for (final issue in _pendingRecoveryIssues)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: ButlerlySpacing.compact,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${issue.fileName}: ${context.l10n.text(issue.messageKey)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  if (issue.fileName.endsWith('.json'))
                                    TextButton(
                                      onPressed: () =>
                                          _repairPendingRecoveryIssue(
                                            issue.fileName,
                                          ),
                                      child: Text(
                                        context.l10n.text(
                                          'captureRecoveryRepair',
                                        ),
                                      ),
                                    ),
                                  TextButton(
                                    onPressed: () =>
                                        _dismissPendingRecoveryIssue(
                                          issue.fileName,
                                        ),
                                    child: Text(
                                      context.l10n.text(
                                        'captureRecoveryDismiss',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: ButlerlySpacing.compact),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              onPressed: _loadPendingReceiptRecovery,
                              child: Text(context.l10n.text('retry')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_source == null) ...[
                  for (final pending in _pendingReceiptRecoveries) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(ButlerlySpacing.standard),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              context.l10n.text('receiptRecoveryTitle'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: ButlerlySpacing.compact),
                            Text(context.l10n.text('receiptRecoveryBody')),
                            const SizedBox(height: ButlerlySpacing.compact),
                            Wrap(
                              spacing: ButlerlySpacing.compact,
                              children: [
                                FilledButton(
                                  onPressed: () =>
                                      _resumePendingReceipt(pending),
                                  child: Text(
                                    context.l10n.text('receiptRecoveryResume'),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _discardPendingReceiptRecovery(pending),
                                  child: Text(
                                    context.l10n.text('receiptRecoveryCancel'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: ButlerlySpacing.standard),
                  ],
                  for (final pending in _pendingGenericRecoveries) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(ButlerlySpacing.standard),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              context.l10n.text('receiptRecoveryTitle'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: ButlerlySpacing.compact),
                            Text(context.l10n.text('receiptRecoveryBody')),
                            const SizedBox(height: ButlerlySpacing.compact),
                            Wrap(
                              spacing: ButlerlySpacing.compact,
                              children: [
                                FilledButton(
                                  onPressed: () =>
                                      _resumePendingGenericReceipt(pending),
                                  child: Text(
                                    context.l10n.text('receiptRecoveryResume'),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _discardPendingGenericReceipt(pending),
                                  child: Text(
                                    context.l10n.text('receiptRecoveryCancel'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: ButlerlySpacing.standard),
                  ],
                  Text(
                    context.l10n.text('addReceipt'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: ButlerlySpacing.small),
                  FilledButton.icon(
                    onPressed: _saving ? null : _camera,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: Text(context.l10n.text('takePhoto')),
                  ),
                  const SizedBox(height: ButlerlySpacing.compact),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _photo,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(context.l10n.text('choosePhotos')),
                  ),
                  const SizedBox(height: ButlerlySpacing.compact),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _file,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: Text(context.l10n.text('chooseFiles')),
                  ),
                ] else ...[
                  if (desktop)
                    Row(
                      key: const ValueKey('receipt-desktop-review-layout'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: ButlerlySize.sourcePreviewHeight * 3,
                                child: Image.file(
                                  File(_source!.path),
                                  fit: BoxFit.contain,
                                ),
                              ),
                              if (_processing) ...[
                                const SizedBox(height: ButlerlySpacing.small),
                                const LinearProgressIndicator(),
                                const SizedBox(height: ButlerlySpacing.compact),
                                Text(context.l10n.text('readingReceipt')),
                              ] else
                                Wrap(
                                  children: [
                                    TextButton.icon(
                                      onPressed: _saving ? null : _camera,
                                      icon: const Icon(Icons.refresh),
                                      label: Text(context.l10n.text('retake')),
                                    ),
                                    TextButton.icon(
                                      onPressed: _saving ? null : _photo,
                                      icon: const Icon(Icons.swap_horiz),
                                      label: Text(context.l10n.text('replace')),
                                    ),
                                    TextButton.icon(
                                      onPressed: _saving ? null : _file,
                                      icon: const Icon(
                                        Icons.folder_open_outlined,
                                      ),
                                      label: Text(
                                        context.l10n.text('chooseFiles'),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: ButlerlySpacing.cardGap),
                        Expanded(
                          child: _processing
                              ? const SizedBox.shrink()
                              : receiptForm,
                        ),
                      ],
                    )
                  else ...[
                    SizedBox(
                      height: ButlerlySize.sourcePreviewHeight * 3,
                      child: Image.file(
                        File(_source!.path),
                        fit: BoxFit.contain,
                      ),
                    ),
                    if (_processing) ...[
                      const SizedBox(height: ButlerlySpacing.small),
                      const LinearProgressIndicator(),
                      const SizedBox(height: ButlerlySpacing.compact),
                      Text(context.l10n.text('readingReceipt')),
                    ] else ...[
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _saving ? null : _camera,
                            icon: const Icon(Icons.refresh),
                            label: Text(context.l10n.text('retake')),
                          ),
                          TextButton.icon(
                            onPressed: _saving ? null : _photo,
                            icon: const Icon(Icons.swap_horiz),
                            label: Text(context.l10n.text('replace')),
                          ),
                        ],
                      ),
                      receiptForm,
                    ],
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
