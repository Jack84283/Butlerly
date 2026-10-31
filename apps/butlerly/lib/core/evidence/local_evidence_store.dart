import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:butlerly/core/data/evidence_path_safety.dart';
import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path;

final class PreservedEvidenceSource {
  const PreservedEvidenceSource({
    required this.originalName,
    required this.localFileName,
    required this.mediaType,
    this.byteLength,
    this.sourceFingerprint,
  });

  final String originalName;
  final String localFileName;
  final String mediaType;
  final int? byteLength;
  final String? sourceFingerprint;
}

final class PendingReceiptCapture {
  const PendingReceiptCapture({
    required this.captureId,
    required this.transactionId,
    required this.source,
    required this.plannedEvidence,
  });

  final String captureId;
  final String transactionId;
  final PreservedEvidenceSource source;
  final EvidenceItem plannedEvidence;
}

final class PendingGenericCapture {
  const PendingGenericCapture({
    required this.source,
    required this.captureKind,
  });

  final PreservedEvidenceSource source;
  final String? captureKind;
}

/// A pending-capture journal that could not be trusted during recovery.
///
/// The source files remain untouched when an issue is reported. This is
/// intentionally diagnostic rather than a cleanup instruction: an uncertain
/// journal must never authorize destructive deletion of a user's evidence.
final class PendingCaptureJournalIssue {
  const PendingCaptureJournalIssue({
    required this.fileName,
    required this.messageKey,
  });

  final String fileName;
  final String messageKey;
}

enum PendingCaptureJournalResolution { repaired, dismissed, unavailable }

const _receiptCaptureStateKey = 'captureState';
const _pendingCaptureCopying = 'copying';
const _pendingCaptureReady = 'ready';
const _deletionPrepared = 'prepared';
const _deletionCommitted = 'committed';
const _receiptCapturePrepared = 'prepared';
const _receiptCaptureAwaitingTransaction = 'awaitingTransaction';
const _receiptCaptureTransactionCommitted = 'transactionCommitted';
const _receiptCaptureCompleted = 'completed';
const _receiptCaptureCancelled = 'cancelled';

final class LocalEvidenceStore {
  const LocalEvidenceStore(this.data, this.finance);

  final LocalDataManager data;
  final FinanceServices finance;

  Future<bool> attach({
    required String transactionId,
    required XFile source,
  }) async =>
      await attachAndReturn(transactionId: transactionId, source: source) !=
      null;

  /// Preserves an unpublished capture in a pending area outside the live
  /// evidence root.
  ///
  /// Receipt OCR/review can last much longer than a filesystem mutation. A
  /// pending file therefore must not live in the root that restore may replace.
  /// Publication later moves the immutable binary into the live root and writes
  /// its SQLite evidence record under one [EvidenceMutationLock] boundary.
  Future<PreservedEvidenceSource> preserve(
    XFile source, {
    String? captureKind,
  }) => _runFinancialEvidenceMutation(
    () => _preservePending(source, captureKind: captureKind),
  );

  Future<PreservedEvidenceSource> _preservePending(
    XFile source, {
    String? captureKind,
  }) async {
    final directory = await _pendingEvidenceDirectory();
    await rejectEvidenceRoot(
      directory,
      message: 'Unsafe pending evidence root.',
    );
    await directory.create(recursive: true);
    final extension = path.extension(source.name).toLowerCase();
    final localFileName = _newImmutableFileName(extension);
    await validateEvidencePath(
      directory,
      localFileName,
      message: 'Unsafe pending evidence path.',
    );
    await _writePreCaptureManifest(
      localFileName: localFileName,
      originalName: source.name,
      mediaType: source.mimeType ?? _mediaType(extension),
      captureKind: captureKind,
    );
    final destination = File(path.join(directory.path, localFileName));
    final temporary = File(path.join(directory.path, '$localFileName.tmp'));
    await validateEvidencePath(
      directory,
      '$localFileName.tmp',
      message: 'Unsafe pending evidence path.',
    );

    // Exclusive creation turns the immutable-path rule into a filesystem
    // invariant as well as a naming convention. It must never truncate an
    // existing pending or published evidence binary.
    await temporary.create(exclusive: true);
    try {
      final bytes = await source.readAsBytes();
      await temporary.writeAsBytes(bytes, flush: true);
      final fingerprint = sha256Bytes(bytes);
      await _markPreCaptureManifestReady(
        localFileName: localFileName,
        byteLength: bytes.length,
        sourceFingerprint: fingerprint,
      );
      // The manifest is ready before this atomic rename. If the process stops
      // between those operations, recovery can verify and finish this rename;
      // it can never import a partially written destination file.
      await temporary.rename(destination.path);
      return PreservedEvidenceSource(
        originalName: source.name,
        localFileName: localFileName,
        mediaType: source.mimeType ?? _mediaType(extension),
        byteLength: bytes.length,
        sourceFingerprint: fingerprint,
      );
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      if (await destination.exists()) await destination.delete();
      await _removePreCaptureManifest(localFileName);
      rethrow;
    }
  }

  Future<void> discardPreserved(PreservedEvidenceSource source) =>
      _runFinancialEvidenceMutation(() => _discardPreservedUnlocked(source));

  Future<void> _discardPreservedUnlocked(PreservedEvidenceSource source) async {
    final file = await _pendingFileFor(source);
    if (file != null && await file.exists()) await file.delete();
    final temporary = await _pendingFileForName('${source.localFileName}.tmp');
    if (temporary != null && await temporary.exists()) await temporary.delete();
    await _removePreCaptureManifest(source.localFileName);
  }

  /// Publishes an already preserved receipt and its SQLite evidence record as
  /// one logical evidence mutation.
  ///
  /// Restore cannot interpose between the pending-file promotion and metadata
  /// publication. If publication fails, the binary is returned to the pending
  /// area so the caller can retry or discard it without leaving an orphan in the
  /// live evidence root.
  Future<EvidenceItem?> attachPreservedAndReturn({
    required String transactionId,
    required PreservedEvidenceSource source,
    ProvenanceSourceType sourceType = ProvenanceSourceType.scan,
    EvidenceItem? planned,
  }) => _runFinancialEvidenceMutation(
    () => attachPreservedAndReturnWithinMutation(
      transactionId: transactionId,
      source: source,
      sourceType: sourceType,
      planned: planned,
    ),
  );

  /// Publishes a preserved receipt when the caller already owns the analysis
  /// and evidence mutation boundary.
  Future<EvidenceItem?> attachPreservedAndReturnWithinMutation({
    required String transactionId,
    required PreservedEvidenceSource source,
    ProvenanceSourceType sourceType = ProvenanceSourceType.scan,
    EvidenceItem? planned,
  }) => _attachPreservedAndReturnWithinMutation(
    transactionId: transactionId,
    source: source,
    sourceType: sourceType,
    planned: planned,
  );

  Future<EvidenceItem?> _attachPreservedAndReturnWithinMutation({
    required String transactionId,
    required PreservedEvidenceSource source,
    ProvenanceSourceType sourceType = ProvenanceSourceType.scan,
    EvidenceItem? planned,
  }) async {
    if (planned != null) {
      final existing = await finance.listEvidenceForTransaction.call(
        transactionId,
      );
      if (existing is! ApplicationSuccess<List<EvidenceItem>>) return null;
      final alreadyAttached = existing.value
          .where((item) => item.id == planned.id)
          .firstOrNull;
      if (alreadyAttached != null) {
        if (alreadyAttached.localFileName != source.localFileName) {
          // A corrupt or mismatched journal must not be allowed to retire
          // recovery state for a different immutable source.
          return null;
        }
        // A retry may resume after SQLite committed the attachment but before
        // the capture journal was completed. Reuse the existing link and
        // verify the source before retiring recovery state.
        final liveFile = await _promotePreservedUnlocked(source);
        if (liveFile == null || !await liveFile.exists()) return null;
        await _removePreCaptureManifest(source.localFileName);
        return alreadyAttached;
      }
    }
    final liveFile = await _promotePreservedUnlocked(source);
    if (liveFile == null) return null;
    try {
      final result = await _attachPreservedAndReturnUnlocked(
        transactionId: transactionId,
        source: source,
        sourceType: sourceType,
        planned: planned,
      );
      if (result != null) return result;
      await _returnToPendingUnlocked(source, liveFile);
      return null;
    } catch (_) {
      await _returnToPendingUnlocked(source, liveFile);
      rethrow;
    }
  }

  Future<EvidenceItem?> _attachPreservedAndReturnUnlocked({
    required String transactionId,
    required PreservedEvidenceSource source,
    ProvenanceSourceType sourceType = ProvenanceSourceType.scan,
    EvidenceItem? planned,
  }) async {
    final extension = path.extension(source.originalName).toLowerCase();
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final now = DateTime.now().toUtc();
    final evidence =
        planned ??
        EvidenceItem(
          id: EvidenceId('evidence-$token'),
          type: _type(extension),
          originalName: source.originalName,
          mediaType: source.mediaType,
          localFileName: source.localFileName,
          provenance: Provenance(
            id: ProvenanceId('evidence-provenance-$token'),
            sourceType: sourceType,
            capturedAt: now,
            originalRepresentation: source.originalName,
          ),
          createdAt: now,
        );
    final result = await finance.storeAndAttachEvidence(
      evidence,
      AttachmentLink(
        id: AttachmentLinkId('attachment-$token'),
        transactionId: TransactionId(transactionId),
        evidenceId: evidence.id,
        createdAt: now,
      ),
    );
    if (result is ApplicationSuccess<EvidenceItem>) {
      await _removePreCaptureManifest(source.localFileName);
      return result.value;
    }
    await finance.removeEvidence(evidence.id.value);
    return null;
  }

  /// Publishes a preserved statement binary and its SQLite evidence record under
  /// the same mutation boundary as restore.
  Future<EvidenceItem?> storePreservedStatement(
    PreservedEvidenceSource source, {
    String? pendingStatementId,
    String? pendingOriginalFilename,
    DateTime? pendingCreatedAt,
    String? pendingPaymentSourceId,
    EvidenceItem? planned,
  }) => _runFinancialEvidenceMutation(() async {
    EvidenceItem? plannedEvidence = planned;
    if (pendingStatementId != null &&
        pendingOriginalFilename != null &&
        pendingCreatedAt != null) {
      // Journal the capture intent before promoting or committing SQLite. A
      // process stop at any later point can reconstruct the source evidence
      // and statement instead of allowing orphan cleanup to discard it.
      plannedEvidence ??= await _preparePendingStatementCaptureUnlocked(
        statementId: pendingStatementId,
        source: source,
        originalFilename: pendingOriginalFilename,
        createdAt: pendingCreatedAt,
        paymentSourceId: pendingPaymentSourceId,
      );
    }
    final liveFile = await _promotePreservedUnlocked(source);
    if (liveFile == null) return null;
    EvidenceItem? result;
    try {
      result = await _storePreservedStatementUnlocked(
        source,
        planned: plannedEvidence,
      );
      if (result != null) return result;
      await _returnToPendingUnlocked(source, liveFile);
      return null;
    } catch (_) {
      if (result != null) {
        try {
          await finance.removeEvidence(result.id.value);
        } catch (_) {}
      }
      await _returnToPendingUnlocked(source, liveFile);
      rethrow;
    }
  });

  Future<EvidenceItem?> _storePreservedStatementUnlocked(
    PreservedEvidenceSource source, {
    EvidenceItem? planned,
  }) async {
    final evidence = planned ?? _newStatementEvidence(source);
    final result = await finance.storeEvidence(evidence);
    if (result is ApplicationSuccess<EvidenceItem>) {
      await _removePreCaptureManifest(source.localFileName);
      return result.value;
    }
    return null;
  }

  EvidenceItem _newStatementEvidence(PreservedEvidenceSource source) {
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final now = DateTime.now().toUtc();
    return EvidenceItem(
      id: EvidenceId('statement-evidence-$token'),
      type: EvidenceType.document,
      originalName: source.originalName,
      mediaType: source.mediaType,
      localFileName: source.localFileName,
      provenance: Provenance(
        id: ProvenanceId('statement-evidence-provenance-$token'),
        sourceType: ProvenanceSourceType.scan,
        capturedAt: now,
        sourceId: source.sourceFingerprint == null
            ? null
            : statementSourceFingerprintPrefix + source.sourceFingerprint!,
        originalRepresentation: source.originalName,
      ),
      createdAt: now,
    );
  }

  /// Creates the statement recovery journal before OCR begins. The source
  /// binary and this intent are both durable before any slow recognition work
  /// runs, so a process stop can reconstruct a reviewable statement shell.
  Future<EvidenceItem> preparePendingStatementCapture({
    required String statementId,
    required PreservedEvidenceSource source,
    required String originalFilename,
    required DateTime createdAt,
    String? paymentSourceId,
  }) => _runFinancialEvidenceMutation(
    () => _preparePendingStatementCaptureUnlocked(
      statementId: statementId,
      source: source,
      originalFilename: originalFilename,
      createdAt: createdAt,
      paymentSourceId: paymentSourceId,
    ),
  );

  Future<EvidenceItem> _preparePendingStatementCaptureUnlocked({
    required String statementId,
    required PreservedEvidenceSource source,
    required String originalFilename,
    required DateTime createdAt,
    String? paymentSourceId,
  }) async {
    final evidence = _newStatementEvidence(source);
    final integrity = await _captureIntegrity(source);
    await _writePendingStatementManifest(
      statementId: statementId,
      evidence: evidence,
      originalFilename: originalFilename,
      createdAt: createdAt,
      paymentSourceId: paymentSourceId,
      byteLength: integrity.byteLength,
      sourceFingerprint: integrity.sourceFingerprint,
    );
    return evidence;
  }

  Future<({int byteLength, String sourceFingerprint})> _captureIntegrity(
    PreservedEvidenceSource source,
  ) async {
    final file = await fileForPreserved(source);
    if (file == null || !await file.exists()) {
      throw StateError('Preserved capture source is unavailable.');
    }
    return (
      byteLength: await file.length(),
      sourceFingerprint: await sha256FileRange(file),
    );
  }

  /// Creates and publishes a receipt as one lock-protected logical mutation.
  Future<EvidenceItem?> attachAndReturn({
    required String transactionId,
    required XFile source,
    ProvenanceSourceType sourceType = ProvenanceSourceType.scan,
  }) => _runFinancialEvidenceMutation(() async {
    final preserved = await _preservePending(source);
    final liveFile = await _promotePreservedUnlocked(preserved);
    if (liveFile == null) {
      await _discardPreservedUnlocked(preserved);
      return null;
    }
    try {
      final result = await _attachPreservedAndReturnUnlocked(
        transactionId: transactionId,
        source: preserved,
        sourceType: sourceType,
      );
      if (result != null) return result;
      await _returnToPendingUnlocked(preserved, liveFile);
      await _discardPreservedUnlocked(preserved);
      return null;
    } catch (_) {
      await _returnToPendingUnlocked(preserved, liveFile);
      await _discardPreservedUnlocked(preserved);
      rethrow;
    }
  });

  /// Creates and publishes statement evidence as one lock-protected logical
  /// mutation. Callers that do not need pre-publication OCR should prefer this
  /// over the split preserve/store API.
  Future<EvidenceItem?> preserveAndStoreStatement(XFile source) =>
      _runFinancialEvidenceMutation(() async {
        final preserved = await _preservePending(source);
        final liveFile = await _promotePreservedUnlocked(preserved);
        if (liveFile == null) {
          await _discardPreservedUnlocked(preserved);
          return null;
        }
        try {
          final result = await _storePreservedStatementUnlocked(preserved);
          if (result != null) return result;
          await _returnToPendingUnlocked(preserved, liveFile);
          await _discardPreservedUnlocked(preserved);
          return null;
        } catch (_) {
          await _returnToPendingUnlocked(preserved, liveFile);
          await _discardPreservedUnlocked(preserved);
          rethrow;
        }
      });

  Future<File?> _promotePreservedUnlocked(
    PreservedEvidenceSource source, {
    int? expectedByteLength,
    String? expectedSourceFingerprint,
  }) async {
    final pendingDirectory = await _pendingEvidenceDirectory();
    await rejectEvidenceTree(
      pendingDirectory,
      message: 'Unsafe pending evidence tree.',
    );
    final liveDirectory = await data.evidenceDirectory();
    await rejectEvidenceTree(
      liveDirectory,
      message: 'Unsafe live evidence tree.',
    );
    final pending = await _pendingFileFor(source);
    await liveDirectory.create(recursive: true);
    await validateEvidencePath(
      liveDirectory,
      source.localFileName,
      message: 'Unsafe live evidence path.',
    );
    final live = File(path.join(liveDirectory.path, source.localFileName));
    final expectedLength = expectedByteLength ?? source.byteLength;
    final expectedFingerprint =
        expectedSourceFingerprint ??
        (source.byteLength == null ? null : source.sourceFingerprint);
    Future<bool> isValid(File file) async {
      if (expectedLength != null && await file.length() != expectedLength) {
        return false;
      }
      if (expectedFingerprint != null &&
          await sha256FileRange(file) != expectedFingerprint) {
        return false;
      }
      return true;
    }

    if (pending == null || !await pending.exists()) {
      // Recovery may have stopped after pending evidence was promoted but
      // before its SQLite publication completed. A validated live artifact is
      // still the user's immutable source and can be retried in place.
      return await live.exists() && await isValid(live) ? live : null;
    }
    if (await live.exists()) {
      // Random immutable names make this effectively impossible, but never
      // truncate an existing published binary if a collision is observed.
      return await isValid(live) ? live : null;
    }
    if (!await isValid(pending)) return null;
    return pending.rename(live.path);
  }

  Future<bool> _matchesIntegrity(
    File file, {
    required int byteLength,
    required String sourceFingerprint,
  }) async =>
      await file.exists() &&
      await file.length() == byteLength &&
      await sha256FileRange(file) == sourceFingerprint;

  Future<void> _returnToPendingUnlocked(
    PreservedEvidenceSource source,
    File liveFile,
  ) async {
    if (!await liveFile.exists()) return;
    final pendingDirectory = await _pendingEvidenceDirectory();
    await rejectEvidenceTree(
      pendingDirectory,
      message: 'Unsafe pending evidence tree.',
    );
    await pendingDirectory.create(recursive: true);
    await validateEvidencePath(
      pendingDirectory,
      source.localFileName,
      message: 'Unsafe pending evidence path.',
    );
    final pending = File(
      path.join(pendingDirectory.path, source.localFileName),
    );
    if (await pending.exists()) {
      // Preserve the unpublished copy and remove only the failed live
      // publication. This branch is defensive against unexpected duplicate
      // calls using the same PreservedEvidenceSource.
      await liveFile.delete();
      return;
    }
    await liveFile.rename(pending.path);
  }

  Future<Directory> _pendingEvidenceDirectory() async {
    final live = await data.evidenceDirectory();
    return Directory('${live.path}.pending');
  }

  Future<File?> _pendingFileFor(PreservedEvidenceSource source) async {
    return _pendingFileForName(source.localFileName);
  }

  Future<File?> _pendingFileForName(String localFileName) async {
    final directory = await _pendingEvidenceDirectory();
    try {
      final normalized = await validateEvidencePath(
        directory,
        localFileName,
        message: 'Unsafe pending evidence path.',
      );
      return File(path.join(directory.path, normalized));
    } on FormatException {
      return null;
    }
  }

  Future<File> _preCaptureManifestFor(String localFileName) async {
    final directory = await _pendingEvidenceDirectory();
    final name = await validateEvidencePath(
      directory,
      'capture-$localFileName.json',
      message: 'Unsafe pending capture manifest path.',
    );
    return File(path.join(directory.path, name));
  }

  Future<void> _writePreCaptureManifest({
    required String localFileName,
    required String originalName,
    required String mediaType,
    String? captureKind,
  }) async {
    final directory = await _pendingEvidenceDirectory();
    await rejectEvidenceRoot(
      directory,
      message: 'Unsafe pending evidence root.',
    );
    await directory.create(recursive: true);
    final manifest = await _preCaptureManifestFor(localFileName);
    await manifest.writeAsString(
      jsonEncode({
        'localFileName': localFileName,
        'originalName': originalName,
        'mediaType': mediaType,
        _receiptCaptureStateKey: _pendingCaptureCopying,
        ...?captureKind == null ? null : {'captureKind': captureKind},
      }),
      flush: true,
    );
  }

  Future<void> _markPreCaptureManifestReady({
    required String localFileName,
    required int byteLength,
    required String sourceFingerprint,
  }) async {
    final manifest = await _preCaptureManifestFor(localFileName);
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pending capture manifest.');
    }
    decoded[_receiptCaptureStateKey] = _pendingCaptureReady;
    decoded['byteLength'] = byteLength;
    decoded['sourceFingerprint'] = sourceFingerprint;
    await manifest.writeAsString(jsonEncode(decoded), flush: true);
  }

  Future<void> _removePreCaptureManifest(String localFileName) async {
    final manifest = await _preCaptureManifestFor(localFileName);
    if (await manifest.exists()) await manifest.delete();
  }

  Future<Set<String>> _specificPendingJournalLocalFileNames(
    Directory directory, {
    bool failOnMalformed = true,
  }) async {
    final localFileNames = <String>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = path.basename(entity.path);
      if (!name.startsWith('statement-') && !name.startsWith('receipt-')) {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic> ||
            decoded['localFileName'] is! String) {
          throw FormatException('Malformed pending capture journal: $name');
        }
        if (name.startsWith('receipt-')) {
          _validatePendingReceiptManifest(decoded);
        } else {
          _validatePendingStatementManifest(decoded);
        }
        final localFileName = await validateEvidencePath(
          directory,
          decoded['localFileName'] as String,
          message: 'Unsafe pending capture source path.',
        );
        localFileNames.add(localFileName);
      } on Object {
        // A malformed specific journal cannot safely authorize a generic
        // source to be hidden or discarded. Report it when requested, but do
        // not add an unverified filename to the protected set.
        if (failOnMalformed) {
          throw FormatException('Unresolved pending capture journal: $name');
        }
      }
    }
    return localFileNames;
  }

  /// Removes pending binaries whose process stopped before a statement or
  /// receipt-specific journal could be created. The generic journal is written
  /// before the binary copy, so this cleanup is deterministic and private.
  Future<int> recoverUnclaimedPendingCaptures() async =>
      _runFinancialEvidenceMutation(() async {
        final directory = await _pendingEvidenceDirectory();
        if (!await directory.exists()) return 0;
        // Read and validate every journal and generic manifest before making
        // any deletion. Generic capture manifests are durable recovery
        // sources until a specific statement/receipt journal or an explicit
        // cancellation retires them; absence of a specific journal only means
        // the process stopped before that journal was created.
        await _specificPendingJournalLocalFileNames(directory);
        await for (final entity in directory.list(followLinks: false)) {
          final name = path.basename(entity.path);
          if (entity is! File ||
              !name.endsWith('.json') ||
              !name.startsWith('capture-')) {
            continue;
          }
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map<String, dynamic> ||
              decoded['localFileName'] is! String) {
            throw FormatException('Invalid pending capture manifest: $name');
          }
          await validateEvidencePath(
            directory,
            decoded['localFileName'] as String,
            message: 'Unsafe pending capture source path.',
          );
        }
        return 0;
      });

  Future<bool> remove(EvidenceItem evidence) =>
      _runFinancialEvidenceMutation(() async {
        final result = await finance.cleanupUnreferencedEvidence(
          evidence.id.value,
        );
        return result is ApplicationSuccess<bool> && result.value == true;
      });

  /// Deletes a transaction and its exclusively-owned evidence while holding
  /// the evidence mutation lock across the database and filesystem work.
  Future<ApplicationResult<void>> deleteTransactionPermanently(
    String transactionId,
  ) => finance.deleteTransactionPermanently(transactionId);

  /// Rolls back a transaction while the caller already owns the enclosing
  /// analysis/evidence mutation boundary.
  Future<ApplicationResult<void>> deleteTransactionPermanentlyWithinMutation(
    String transactionId,
  ) => finance.deleteTransactionPermanently.callWithinEvidenceMutation(
    transactionId,
  );

  Future<bool> retryEvidenceCleanup(String evidenceId) =>
      _runFinancialEvidenceMutation(() async {
        final result = await finance.cleanupUnreferencedEvidence(evidenceId);
        if (result is! ApplicationSuccess<bool> || !result.value) return false;
        try {
          await _finalizeDeletedEvidenceForId(evidenceId);
          return true;
        } on Object {
          return false;
        }
      });

  Future<ApplicationResult<bool>> removeEvidenceFromTransaction(
    String transactionId,
    String evidenceId,
  ) => finance.removeEvidenceFromTransaction(transactionId, evidenceId);

  Future<int> recoverUnreferencedEvidence() async {
    final result = await _runFinancialEvidenceMutation(() async {
      // An unresolved typed journal can own an evidence row before its
      // transaction/statement reference is durable. Never let orphan
      // cleanup delete that row or its live binary while recovery still has
      // a source to resume.
      if (await _hasUnresolvedSpecificCaptureJournalUnlocked()) {
        return const ApplicationSuccess<int>(0);
      }
      return finance.recoverUnreferencedEvidence();
    });
    if (result is ApplicationSuccess<int>) return result.value;
    if (result is ApplicationFailure<int>) {
      throw StateError(
        'Evidence recovery failed: ${result.failure.operation} '
        '${result.failure.detail ?? result.failure.code.name}',
      );
    }
    throw StateError('Evidence recovery returned an invalid result.');
  }

  Future<bool> _hasUnresolvedSpecificCaptureJournalUnlocked() async {
    final directory = await _pendingEvidenceDirectory();
    if (!await directory.exists()) return false;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = path.basename(entity.path);
      if (!name.startsWith('receipt-') && !name.startsWith('statement-')) {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) return true;
        if (name.startsWith('receipt-')) {
          _validatePendingReceiptManifest(decoded);
        } else {
          _validatePendingStatementManifest(decoded);
        }
        await validateEvidencePath(
          directory,
          decoded['localFileName'] as String,
          message: 'Unsafe pending capture source path.',
        );
        final state = decoded[_receiptCaptureStateKey];
        if (state == _receiptCaptureCompleted ||
            state == _receiptCaptureCancelled) {
          continue;
        }
        return true;
      } on Object {
        // Uncertainty is itself a reason to retain all evidence until the
        // journal is repaired or explicitly cancelled.
        return true;
      }
    }
    return false;
  }

  /// Called by the finance use cases before SQLite metadata cleanup. The
  /// binary is moved to the durable deletion journal first, so a database
  /// rollback can restore it during startup recovery.
  Future<void> deletePublishedFile(EvidenceItem evidence) async {
    await _stagePublishedFileForDeletion(evidence);
  }

  /// Finalizes a staged binary after its SQLite metadata has committed. If the
  /// process stops before this runs, startup recovery sees the missing
  /// evidence row and removes the staged binary safely.
  Future<void> finalizeDeletedEvidenceFile(EvidenceItem evidence) async {
    await _finalizeDeletedEvidenceForId(
      evidence.id.value,
      expectedLocalFileName: evidence.localFileName,
    );
  }

  Future<void> _finalizeDeletedEvidenceForId(
    String evidenceId, {
    String? expectedLocalFileName,
  }) async {
    final root = await data.evidenceDirectory();
    final deleting = Directory('${root.path}.deleting');
    await rejectEvidenceRoot(
      deleting,
      message: 'Unsafe deleting evidence root.',
    );
    if (!await deleting.exists()) return;
    await for (final entity in deleting.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic> ||
            decoded['evidenceId'] != evidenceId) {
          continue;
        }
        final stagedFileName = decoded['stagedFileName'];
        final localFileName = decoded['localFileName'];
        final byteLength = decoded['byteLength'];
        final sourceFingerprint = decoded['sourceFingerprint'];
        if (localFileName is! String ||
            byteLength is! int ||
            byteLength < 0 ||
            sourceFingerprint is! String ||
            sourceFingerprint.isEmpty ||
            (expectedLocalFileName != null &&
                localFileName != expectedLocalFileName)) {
          throw const FormatException('Invalid evidence deletion identity.');
        }
        if (stagedFileName is! String) {
          throw const FormatException('Invalid staged evidence identity.');
        }
        final deletionState = decoded['deletionState'];
        if (deletionState != null &&
            deletionState != _deletionPrepared &&
            deletionState != _deletionCommitted) {
          throw const FormatException('Invalid evidence deletion state.');
        }
        final normalized = await validateEvidencePath(
          deleting,
          stagedFileName,
          message: 'Unsafe staged evidence finalization path.',
        );
        final staged = File(path.join(deleting.path, normalized));
        if (!await _matchesIntegrity(
          staged,
          byteLength: byteLength,
          sourceFingerprint: sourceFingerprint,
        )) {
          throw StateError('Staged evidence integrity could not be verified.');
        }
        decoded['deletionState'] = _deletionCommitted;
        await entity.writeAsString(jsonEncode(decoded), flush: true);
        if (await staged.exists()) await staged.delete();
        if (await entity.exists()) await entity.delete();
        return;
      } on Object {
        // Leave the manifest for startup recovery, while surfacing the
        // failure so callers can present a recoverable cleanup state.
        rethrow;
      }
    }
  }

  Future<bool> removeUnprocessedStatement(String statementId) =>
      _runFinancialEvidenceMutation(
        () => _removeStatementSafely(
          statementId,
          () => finance.statementServices?.deleteStatement(statementId),
        ),
      );

  Future<bool> abandonStatementImport(String statementId) =>
      _runFinancialEvidenceMutation(
        () => _removeStatementSafely(
          statementId,
          () => finance.statementServices?.abandonImport(statementId),
        ),
      );

  Future<bool> _removeStatementSafely(
    String statementId,
    Future<ApplicationResult<EvidenceItem?>>? Function() removeStatement,
  ) async {
    final statements = finance.statementServices;
    if (statements == null) return false;
    final listed = await statements.list();
    if (listed is! ApplicationSuccess<List<FinancialStatement>>) return false;
    final statement = listed.value
        .where((value) => value.id == statementId)
        .firstOrNull;
    if (statement == null) return false;
    final evidenceResult = await finance.getEvidence(statement.evidenceId);
    if (evidenceResult is! ApplicationSuccess<EvidenceItem?> ||
        evidenceResult.value == null) {
      return false;
    }
    final evidence = evidenceResult.value!;
    ({File original, File staged, File manifest})? staged;
    try {
      final allEvidence = await finance.listAllEvidence.call();
      if (allEvidence is! ApplicationSuccess<List<EvidenceItem>>) {
        return false;
      }
      final sharedFile = allEvidence.value.any(
        (item) =>
            item.id != evidence.id &&
            item.localFileName != null &&
            item.localFileName == evidence.localFileName,
      );
      staged = sharedFile
          ? null
          : await _stagePublishedFileForDeletion(evidence);
    } on Object {
      return false;
    }
    bool cancellationMarked;
    try {
      cancellationMarked =
          await _markPendingStatementCaptureCancelledWithinMutation(
            statementId,
          );
    } catch (_) {
      if (staged != null) {
        try {
          await _restoreStagedFile(staged);
        } catch (_) {
          // Keep the staged file and manifest for startup recovery.
        }
      }
      return false;
    }
    final result = await removeStatement();
    if (result is! ApplicationSuccess<EvidenceItem?>) {
      if (cancellationMarked) {
        try {
          await _restorePendingStatementCapturePreparedWithinMutation(
            statementId,
          );
        } catch (_) {
          // Keep the durable cancellation marker if the rollback write fails;
          // startup recovery will reconcile it against the still-present row.
        }
      }
      if (staged != null) {
        try {
          await _restoreStagedFile(staged);
        } catch (_) {
          // Keep the staged file for the next recovery pass.
        }
      }
      return false;
    }
    if (cancellationMarked) {
      try {
        await _cancelPendingStatementCaptureWithinMutation(statementId);
      } catch (_) {
        // The database deletion is already durable. Retain an unresolved
        // journal for startup recovery instead of reporting a false delete
        // failure or deleting uncertain evidence.
      }
    }
    if (staged != null) {
      try {
        await _finalizeDeletedEvidenceForId(
          evidence.id.value,
          expectedLocalFileName: evidence.localFileName,
        );
      } on Object {
        // The database record is gone; retain the manifest for startup
        // recovery if filesystem cleanup was interrupted. The logical delete
        // succeeded, so callers must not retry it by the now-missing ID.
        return true;
      }
    }
    return true;
  }

  Future<({File original, File staged, File manifest})?>
  _stagePublishedFileForDeletion(EvidenceItem evidence) async {
    final original = await fileFor(evidence);
    if (original == null || !await original.exists()) return null;
    final root = await data.evidenceDirectory();
    final deleting = Directory('${root.path}.deleting');
    await rejectEvidenceRoot(
      deleting,
      message: 'Unsafe deleting evidence root.',
    );
    await deleting.create(recursive: true);
    final token = _newImmutableFileName(path.extension(original.path));
    final stagedName = 'delete-$token';
    final manifestName = '$stagedName.json';
    await validateEvidencePath(
      deleting,
      stagedName,
      message: 'Unsafe staged evidence path.',
    );
    await validateEvidencePath(
      deleting,
      manifestName,
      message: 'Unsafe staged evidence manifest path.',
    );
    final staged = File(path.join(deleting.path, stagedName));
    final manifest = File(path.join(deleting.path, manifestName));
    final byteLength = await original.length();
    final sourceFingerprint = await sha256FileRange(original);
    await manifest.writeAsString(
      jsonEncode({
        'evidenceId': evidence.id.value,
        'localFileName': evidence.localFileName,
        'stagedFileName': stagedName,
        'deletionState': _deletionPrepared,
        'byteLength': byteLength,
        'sourceFingerprint': sourceFingerprint,
      }),
      flush: true,
    );
    try {
      await original.rename(staged.path);
    } catch (_) {
      if (await manifest.exists()) await manifest.delete();
      rethrow;
    }
    return (original: original, staged: staged, manifest: manifest);
  }

  Future<void> _restoreStagedFile(
    ({File original, File staged, File manifest}) staged,
  ) async {
    if (!await staged.staged.exists()) {
      // Do not retire an unresolved deletion journal merely because the
      // staged artifact is missing. The database row may still reference the
      // evidence, so startup recovery must retain and diagnose this state.
      return;
    }
    if (await staged.original.exists()) {
      // A collision means the filesystem state is ambiguous. Preserve both
      // artifacts and the journal for integrity-checked startup recovery.
      return;
    }
    await staged.staged.rename(staged.original.path);
    if (await staged.manifest.exists()) await staged.manifest.delete();
  }

  Future<void> recoverStagedEvidenceDeletions() =>
      _runFinancialEvidenceMutation(() async {
        final root = await data.evidenceDirectory();
        final deleting = Directory('${root.path}.deleting');
        await rejectEvidenceRoot(root, message: 'Unsafe live evidence root.');
        await rejectEvidenceRoot(
          deleting,
          message: 'Unsafe deleting evidence root.',
        );
        if (!await deleting.exists()) return;
        Object? firstFailure;
        final entities = await deleting
            .list(followLinks: false)
            .where((entity) => entity is File)
            .cast<File>()
            .where((entity) => entity.path.endsWith('.json'))
            .toList();
        final entityPaths = entities.map((entity) => entity.path).toSet();
        for (final entity in entities) {
          // A JSON source is named `delete-<token>.json`, while its manifest
          // is `delete-<token>.json.json`. Do not try to decode the source as
          // a second manifest during recovery.
          if (entityPaths.contains('${entity.path}.json')) continue;
          final manifest = entity;
          try {
            final decoded = jsonDecode(await manifest.readAsString());
            if (decoded is! Map<String, dynamic>) {
              throw const FormatException('Invalid evidence manifest.');
            }
            final evidenceId = decoded['evidenceId'];
            final localFileName = decoded['localFileName'];
            final stagedFileName = decoded['stagedFileName'];
            final deletionState = decoded['deletionState'];
            final byteLength = decoded['byteLength'];
            final sourceFingerprint = decoded['sourceFingerprint'];
            if (evidenceId is! String ||
                localFileName is! String ||
                stagedFileName is! String ||
                (deletionState != null &&
                    deletionState != _deletionPrepared &&
                    deletionState != _deletionCommitted) ||
                byteLength is! int ||
                byteLength < 0 ||
                sourceFingerprint is! String ||
                sourceFingerprint.isEmpty) {
              throw const FormatException('Invalid evidence manifest fields.');
            }
            final normalizedStagedFileName = await validateEvidencePath(
              deleting,
              stagedFileName,
              message: 'Unsafe staged evidence recovery path.',
            );
            final staged = File(
              path.join(deleting.path, normalizedStagedFileName),
            );
            final evidenceResult = await finance.getEvidence(evidenceId);
            if (evidenceResult is! ApplicationSuccess<EvidenceItem?>) {
              throw StateError('Evidence metadata is unavailable.');
            }
            final evidence = evidenceResult.value;
            if (evidence != null && evidence.localFileName == localFileName) {
              final live = File(path.join(root.path, localFileName));
              await validateEvidenceReferencePath(
                root,
                localFileName,
                message: 'Unsafe staged evidence recovery path.',
              );
              await root.create(recursive: true);
              final stagedValid = await _matchesIntegrity(
                staged,
                byteLength: byteLength,
                sourceFingerprint: sourceFingerprint,
              );
              final liveValid = await _matchesIntegrity(
                live,
                byteLength: byteLength,
                sourceFingerprint: sourceFingerprint,
              );
              if (stagedValid && !await live.exists()) {
                await staged.rename(live.path);
              } else if (stagedValid && liveValid) {
                await staged.delete();
              } else if (!liveValid) {
                throw StateError('Staged evidence source is unavailable.');
              }
            } else if (evidence == null &&
                (deletionState == _deletionPrepared ||
                    deletionState == _deletionCommitted)) {
              // A missing evidence row is the durable reference-aware delete
              // decision. A prepared journal means the process stopped after
              // that SQLite commit but before the finalization marker; the
              // source is still safe to retire only after integrity checking.
              final stagedValid = await _matchesIntegrity(
                staged,
                byteLength: byteLength,
                sourceFingerprint: sourceFingerprint,
              );
              if (!stagedValid) {
                throw StateError('Staged evidence source is corrupted.');
              }
              if (await staged.exists()) await staged.delete();
            } else {
              throw StateError('Staged evidence ownership is unresolved.');
            }
            if (await manifest.exists()) await manifest.delete();
          } on Object catch (error) {
            // Retain malformed or unavailable recovery artifacts for the next
            // startup rather than deleting user evidence blindly.
            firstFailure ??= error;
          }
        }
        final failure = firstFailure;
        if (failure != null) throw failure;
      });

  Future<void> _writePendingStatementManifest({
    required String statementId,
    required EvidenceItem evidence,
    required String originalFilename,
    required DateTime createdAt,
    required int byteLength,
    required String sourceFingerprint,
    String? paymentSourceId,
  }) async {
    final directory = await _pendingEvidenceDirectory();
    await rejectEvidenceRoot(
      directory,
      message: 'Unsafe pending evidence root.',
    );
    await directory.create(recursive: true);
    final name = 'statement-$statementId.json';
    await validateEvidencePath(
      directory,
      name,
      message: 'Unsafe pending statement manifest path.',
    );
    final manifest = File(path.join(directory.path, name));
    final manifestData = <String, Object?>{
      'statementId': statementId,
      'evidenceId': evidence.id.value,
      'evidenceType': evidence.type.name,
      'evidenceOriginalName': evidence.originalName,
      'evidenceMediaType': evidence.mediaType,
      'localFileName': evidence.localFileName,
      'provenanceId': evidence.provenance.id.value,
      'provenanceCapturedAt': evidence.provenance.capturedAt
          .toUtc()
          .toIso8601String(),
      'evidenceCreatedAt': evidence.createdAt.toUtc().toIso8601String(),
      'originalFilename': originalFilename,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'byteLength': byteLength,
      'sourceFingerprint': sourceFingerprint,
      _receiptCaptureStateKey: _receiptCapturePrepared,
    };
    if (evidence.provenance.sourceId != null) {
      manifestData['provenanceSourceId'] = evidence.provenance.sourceId;
    }
    if (paymentSourceId != null) {
      manifestData['paymentSourceId'] = paymentSourceId;
    }
    await manifest.writeAsString(jsonEncode(manifestData), flush: true);
  }

  Future<bool> completePendingStatementCapture(String statementId) =>
      _runFinancialEvidenceMutation(() async {
        final directory = await _pendingEvidenceDirectory();
        try {
          final name = await validateEvidencePath(
            directory,
            'statement-$statementId.json',
            message: 'Unsafe pending statement manifest path.',
          );
          final manifest = File(path.join(directory.path, name));
          if (!await manifest.exists()) return true;
          final decoded = jsonDecode(await manifest.readAsString());
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid pending statement manifest.');
          }
          _validatePendingStatementManifest(decoded);
          final localFileName = decoded['localFileName'] as String;
          decoded[_receiptCaptureStateKey] = _receiptCaptureCompleted;
          await manifest.writeAsString(jsonEncode(decoded), flush: true);
          await _discardPendingStatementJournal(manifest, localFileName);
          return true;
        } on Object {
          return false;
        }
      });

  /// Returns a published statement capture to the pending area when statement
  /// creation fails after evidence publication. The source and journal then
  /// remain directly retryable without leaving an orphan evidence row behind.
  Future<bool> rollbackPendingStatementCaptureForRetry({
    required String statementId,
    required PreservedEvidenceSource source,
    required EvidenceItem evidence,
  }) => _runFinancialEvidenceMutation(() async {
    final manifest = await _pendingStatementManifestFor(statementId);
    if (!await manifest.exists()) return false;
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pending statement manifest.');
    }
    _validatePendingStatementManifest(decoded);
    final localFileName = decoded['localFileName'] as String;
    if (localFileName != source.localFileName ||
        evidence.localFileName != localFileName) {
      throw const FormatException(
        'Pending statement source does not match its evidence.',
      );
    }
    final liveRoot = await data.evidenceDirectory();
    final liveName = await validateEvidenceReferencePath(
      liveRoot,
      localFileName,
      message: 'Unsafe live statement source path.',
    );
    final removed = await finance.removeEvidence(evidence.id.value);
    if (removed is! ApplicationSuccess<void>) return false;
    final live = File(path.join(liveRoot.path, liveName));
    if (await live.exists()) await _returnToPendingUnlocked(source, live);
    return true;
  });

  Future<bool> _markPendingStatementCaptureCancelledWithinMutation(
    String statementId,
  ) async {
    final manifest = await _pendingStatementManifestFor(statementId);
    if (!await manifest.exists()) return false;
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pending statement manifest.');
    }
    _validatePendingStatementManifest(decoded);
    decoded[_receiptCaptureStateKey] = _receiptCaptureCancelled;
    await manifest.writeAsString(jsonEncode(decoded), flush: true);
    return true;
  }

  Future<void> _restorePendingStatementCapturePreparedWithinMutation(
    String statementId,
  ) async {
    final manifest = await _pendingStatementManifestFor(statementId);
    if (!await manifest.exists()) return;
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pending statement manifest.');
    }
    _validatePendingStatementManifest(decoded);
    decoded[_receiptCaptureStateKey] = _receiptCapturePrepared;
    await manifest.writeAsString(jsonEncode(decoded), flush: true);
  }

  Future<void> _cancelPendingStatementCaptureWithinMutation(
    String statementId,
  ) async {
    final manifest = await _pendingStatementManifestFor(statementId);
    if (!await manifest.exists()) return;
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pending statement manifest.');
    }
    _validatePendingStatementManifest(decoded);
    await _discardPendingStatementJournal(
      manifest,
      decoded['localFileName'] as String,
    );
  }

  Future<File> _pendingStatementManifestFor(String statementId) async {
    final directory = await _pendingEvidenceDirectory();
    final name = await validateEvidencePath(
      directory,
      'statement-$statementId.json',
      message: 'Unsafe pending statement manifest path.',
    );
    return File(path.join(directory.path, name));
  }

  Future<void> _discardPendingStatementJournal(
    File manifest,
    String localFileName,
  ) async {
    final directory = await _pendingEvidenceDirectory();
    final normalized = await validateEvidencePath(
      directory,
      localFileName,
      message: 'Unsafe pending statement source path.',
    );
    final pending = File(path.join(directory.path, normalized));
    if (await pending.exists()) await pending.delete();
    if (await manifest.exists()) await manifest.delete();
    await _removePreCaptureManifest(localFileName);
  }

  /// Journals a receipt transaction before its source transaction is created.
  /// The journal lets startup finish the evidence attachment if the process
  /// stops after the transaction commit and before attachment completes.
  Future<EvidenceItem> preparePendingReceiptCapture({
    required String transactionId,
    required PreservedEvidenceSource source,
  }) => _runFinancialEvidenceMutation(
    () => preparePendingReceiptCaptureWithinMutation(
      transactionId: transactionId,
      source: source,
    ),
  );

  Future<EvidenceItem> preparePendingReceiptCaptureWithinMutation({
    required String transactionId,
    required PreservedEvidenceSource source,
  }) async {
    final evidence = _newReceiptEvidence(source);
    final integrity = await _captureIntegrity(source);
    final directory = await _pendingEvidenceDirectory();
    await rejectEvidenceRoot(
      directory,
      message: 'Unsafe pending evidence root.',
    );
    await directory.create(recursive: true);
    final name = await validateEvidencePath(
      directory,
      'receipt-$transactionId.json',
      message: 'Unsafe pending receipt manifest path.',
    );
    final manifest = File(path.join(directory.path, name));
    await manifest.writeAsString(
      jsonEncode({
        'transactionId': transactionId,
        'evidenceId': evidence.id.value,
        'evidenceType': evidence.type.name,
        'evidenceOriginalName': evidence.originalName,
        'evidenceMediaType': evidence.mediaType,
        'localFileName': evidence.localFileName,
        'provenanceId': evidence.provenance.id.value,
        'provenanceCapturedAt': evidence.provenance.capturedAt
            .toUtc()
            .toIso8601String(),
        'evidenceCreatedAt': evidence.createdAt.toUtc().toIso8601String(),
        'provenanceSourceId': source.sourceFingerprint,
        'sourceFingerprint': integrity.sourceFingerprint,
        'byteLength': integrity.byteLength,
        _receiptCaptureStateKey: _receiptCapturePrepared,
      }),
      flush: true,
    );
    return evidence;
  }

  Future<bool> markPendingReceiptCaptureTransactionCommitted({
    required String captureId,
    required String transactionId,
  }) => _runFinancialEvidenceMutation(
    () => markPendingReceiptCaptureTransactionCommittedWithinMutation(
      captureId: captureId,
      transactionId: transactionId,
    ),
  );

  /// Records the transaction commit before evidence attachment starts. A
  /// prepared receipt remains recoverable when the process stops before this
  /// marker is written; the marker makes the lifecycle explicit for restart
  /// recovery and for confirmed rollback/cancellation.
  Future<bool> markPendingReceiptCaptureTransactionCommittedWithinMutation({
    required String captureId,
    required String transactionId,
  }) async {
    final manifest = await _pendingReceiptManifestFor(captureId);
    if (!await manifest.exists()) return false;
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pending receipt manifest.');
    }
    _validatePendingReceiptManifest(decoded);
    decoded['transactionId'] = transactionId;
    decoded[_receiptCaptureStateKey] = _receiptCaptureTransactionCommitted;
    await manifest.writeAsString(jsonEncode(decoded), flush: true);
    return true;
  }

  Future<bool> completePendingReceiptCapture(String transactionId) =>
      _runFinancialEvidenceMutation(
        () => completePendingReceiptCaptureWithinMutation(transactionId),
      );

  Future<bool> completePendingReceiptCaptureWithinMutation(
    String transactionId,
  ) async {
    final manifest = await _pendingReceiptManifestFor(transactionId);
    if (!await manifest.exists()) return true;
    try {
      final decoded = jsonDecode(await manifest.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid pending receipt manifest.');
      }
      _validatePendingReceiptManifest(decoded);
      final localFileName = decoded['localFileName'] as String;
      decoded[_receiptCaptureStateKey] = _receiptCaptureCompleted;
      await manifest.writeAsString(jsonEncode(decoded), flush: true);
      await manifest.delete();
      await _removePreCaptureManifest(localFileName);
      return true;
    } on Object {
      // Preserve malformed or unavailable journals for explicit recovery.
      return false;
    }
  }

  Future<bool> cancelPendingReceiptCapture(String captureId) =>
      _runFinancialEvidenceMutation(
        () => cancelPendingReceiptCaptureWithinMutation(captureId),
      );

  /// Explicitly cancels a receipt review. The cancellation marker is durable
  /// before cleanup so a stop during deletion cannot be mistaken for an
  /// uncommitted capture that still needs recovery.
  Future<bool> cancelPendingReceiptCaptureWithinMutation(
    String captureId,
  ) async {
    final manifest = await _pendingReceiptManifestFor(captureId);
    if (!await manifest.exists()) return true;
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pending receipt manifest.');
    }
    _validatePendingReceiptManifest(decoded);
    final localFileName = decoded['localFileName'];
    final sourceName = localFileName as String;
    decoded[_receiptCaptureStateKey] = _receiptCaptureCancelled;
    await manifest.writeAsString(jsonEncode(decoded), flush: true);
    await _discardPendingReceiptJournal(manifest, sourceName);
    return true;
  }

  /// Retargets a receipt journal from the provisional new-transaction ID to an
  /// existing transaction selected during duplicate/reconciliation review.
  /// The manifest filename remains the immutable capture ID, so recovery never
  /// has a gap between the old and new target.
  Future<bool> rebindPendingReceiptCapture({
    required String captureId,
    required String transactionId,
  }) => _runFinancialEvidenceMutation(
    () => rebindPendingReceiptCaptureWithinMutation(
      captureId: captureId,
      transactionId: transactionId,
    ),
  );

  Future<bool> rebindPendingReceiptCaptureWithinMutation({
    required String captureId,
    required String transactionId,
  }) async {
    final manifest = await _pendingReceiptManifestFor(captureId);
    if (!await manifest.exists()) return false;
    final decoded = jsonDecode(await manifest.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pending receipt manifest.');
    }
    decoded['transactionId'] = transactionId;
    await manifest.writeAsString(jsonEncode(decoded), flush: true);
    return true;
  }

  Future<void> _discardPendingReceiptJournal(
    File manifest,
    String localFileName,
  ) async {
    final directory = await _pendingEvidenceDirectory();
    final normalized = await validateEvidencePath(
      directory,
      localFileName,
      message: 'Unsafe pending receipt source path.',
    );
    final pending = File(path.join(directory.path, normalized));
    if (await pending.exists()) await pending.delete();
    if (await manifest.exists()) await manifest.delete();
    await _removePreCaptureManifest(localFileName);
  }

  Future<int> recoverPendingReceiptCaptures() async {
    final result = await _runFinancialEvidenceMutation(() async {
      final directory = await _pendingEvidenceDirectory();
      if (!await directory.exists()) return 0;
      var recovered = 0;
      Object? firstFailure;
      await for (final entity in directory.list(followLinks: false)) {
        final name = path.basename(entity.path);
        if (entity is! File ||
            !name.endsWith('.json') ||
            !name.startsWith('receipt-')) {
          continue;
        }
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid pending receipt manifest.');
          }
          final transactionId = decoded['transactionId'];
          final evidenceId = decoded['evidenceId'];
          final localFileName = decoded['localFileName'];
          final originalName = decoded['evidenceOriginalName'];
          final mediaType = decoded['evidenceMediaType'];
          final sourceFingerprint = decoded['sourceFingerprint'];
          final captureState = decoded[_receiptCaptureStateKey];
          if (transactionId is! String ||
              evidenceId is! String ||
              localFileName is! String ||
              originalName is! String ||
              mediaType is! String ||
              (sourceFingerprint != null && sourceFingerprint is! String) ||
              (captureState != null && captureState is! String)) {
            throw const FormatException('Invalid pending receipt fields.');
          }
          _validatePendingReceiptManifest(decoded);
          final expectedByteLength = decoded['byteLength'] as int;
          final expectedSourceFingerprint =
              decoded['sourceFingerprint'] as String;
          final source = PreservedEvidenceSource(
            originalName: originalName,
            localFileName: localFileName,
            mediaType: mediaType,
            byteLength: expectedByteLength,
            sourceFingerprint: expectedSourceFingerprint,
          );
          await validateEvidencePath(
            directory,
            localFileName,
            message: 'Unsafe pending receipt source path.',
          );
          if (await fileForPreserved(source) == null) {
            throw StateError(
              'Pending receipt source does not match its journal.',
            );
          }
          if (captureState == _receiptCaptureCancelled ||
              captureState == _receiptCaptureCompleted) {
            await _discardPendingReceiptJournal(entity, localFileName);
            continue;
          }
          if (captureState != null &&
              captureState != _receiptCapturePrepared &&
              captureState != _receiptCaptureAwaitingTransaction &&
              captureState != _receiptCaptureTransactionCommitted) {
            throw FormatException(
              'Unsupported pending receipt state: $captureState',
            );
          }
          final transaction = await finance.getTransaction.call(transactionId);
          if (transaction is! ApplicationSuccess<TransactionDto>) {
            if (transaction is ApplicationFailure<TransactionDto> &&
                transaction.failure.code == ApplicationFailureCode.notFound) {
              // Not-found is not proof that the user cancelled or permanently
              // deleted the transaction. It may be the crash window between
              // preserving the source and committing the new transaction.
              // Keep the source and make that lifecycle state explicit.
              if (captureState == null ||
                  captureState == _receiptCapturePrepared) {
                decoded[_receiptCaptureStateKey] =
                    _receiptCaptureAwaitingTransaction;
                await entity.writeAsString(jsonEncode(decoded), flush: true);
              }
              continue;
            }
            throw StateError('Receipt transaction lookup failed.');
          }
          final evidence = _evidenceFromPendingStatementManifest(decoded);
          if (evidence == null) {
            throw const FormatException(
              'Pending receipt evidence cannot be reconstructed.',
            );
          }
          final existingEvidence = await finance.listEvidenceForTransaction
              .call(transactionId);
          if (existingEvidence is! ApplicationSuccess<List<EvidenceItem>>) {
            throw StateError('Receipt evidence lookup failed.');
          }
          final existing = existingEvidence.value
              .where((item) => item.id.value == evidenceId)
              .firstOrNull;
          if (existing != null) {
            if (existing.localFileName != source.localFileName) {
              throw const FormatException(
                'Committed receipt evidence does not match its journal.',
              );
            }
            // The evidence row may have been committed immediately before a
            // process stop. Never retire the journal solely because the row
            // exists: first prove that its immutable source is still
            // available in live storage, promoting the pending copy when
            // necessary. Otherwise SQLite would retain a dangling reference.
            final liveRoot = await data.evidenceDirectory();
            await rejectEvidenceRoot(
              liveRoot,
              message: 'Unsafe live receipt source tree.',
            );
            final liveName = await validateEvidenceReferencePath(
              liveRoot,
              source.localFileName,
              message: 'Unsafe live receipt source path.',
            );
            var live = File(path.join(liveRoot.path, liveName));
            if (!await _matchesIntegrity(
              live,
              byteLength: expectedByteLength,
              sourceFingerprint: expectedSourceFingerprint,
            )) {
              live =
                  await _promotePreservedUnlocked(
                    source,
                    expectedByteLength: expectedByteLength,
                    expectedSourceFingerprint: expectedSourceFingerprint,
                  ) ??
                  live;
            }
            if (!await _matchesIntegrity(
              live,
              byteLength: expectedByteLength,
              sourceFingerprint: expectedSourceFingerprint,
            )) {
              throw StateError('Committed receipt source is unavailable.');
            }
            await _discardPendingReceiptJournal(entity, localFileName);
            recovered++;
            continue;
          }
          final liveRoot = await data.evidenceDirectory();
          await rejectEvidenceRoot(
            liveRoot,
            message: 'Unsafe live evidence tree.',
          );
          await validateEvidencePath(
            directory,
            localFileName,
            message: 'Unsafe pending receipt source path.',
          );
          await validateEvidenceReferencePath(
            liveRoot,
            localFileName,
            message: 'Unsafe live receipt source path.',
          );
          await liveRoot.create(recursive: true);
          final promoted = await _promotePreservedUnlocked(
            source,
            expectedByteLength: expectedByteLength,
            expectedSourceFingerprint: expectedSourceFingerprint,
          );
          if (promoted == null ||
              !await _matchesIntegrity(
                promoted,
                byteLength: expectedByteLength,
                sourceFingerprint: expectedSourceFingerprint,
              )) {
            throw StateError('Pending receipt source is unavailable.');
          }
          final now = evidence.createdAt;
          final attached = await finance.storeAndAttachEvidence(
            evidence,
            AttachmentLink(
              id: AttachmentLinkId('attachment-${evidence.id.value}'),
              transactionId: TransactionId(transactionId),
              evidenceId: evidence.id,
              createdAt: now,
            ),
          );
          if (attached is! ApplicationSuccess<EvidenceItem>) {
            throw StateError('Receipt evidence attachment failed.');
          }
          await _discardPendingReceiptJournal(entity, localFileName);
          recovered++;
        } on Object catch (error) {
          // Keep the manifest and source for the next restart if the database
          // or filesystem is temporarily unavailable.
          firstFailure ??= error;
        }
      }
      final failure = firstFailure;
      if (failure != null) throw failure;
      return recovered;
    });
    return result;
  }

  /// Lists receipt captures retained after the transaction commit window.
  /// These are intentionally exposed to the receipt UI: a missing transaction
  /// is not proof of cancellation, so the source must remain resumable or
  /// explicitly cancellable by the user.
  Future<List<PendingReceiptCapture>> listPendingReceiptCaptures() async {
    final result = await _runFinancialEvidenceMutation(() async {
      final directory = await _pendingEvidenceDirectory();
      if (!await directory.exists()) return const <PendingReceiptCapture>[];
      final captures = <PendingReceiptCapture>[];
      await for (final entity in directory.list(followLinks: false)) {
        final name = path.basename(entity.path);
        if (entity is! File ||
            !name.endsWith('.json') ||
            !name.startsWith('receipt-')) {
          continue;
        }
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid pending receipt manifest.');
          }
          _validatePendingReceiptManifest(decoded);
          final state = decoded[_receiptCaptureStateKey] as String?;
          if (state == _receiptCaptureCancelled ||
              state == _receiptCaptureCompleted) {
            continue;
          }
          final transactionId = decoded['transactionId'] as String;
          final localFileName = decoded['localFileName'] as String;
          await validateEvidencePath(
            directory,
            localFileName,
            message: 'Unsafe pending receipt source path.',
          );
          final source = PreservedEvidenceSource(
            originalName: decoded['evidenceOriginalName'] as String,
            localFileName: localFileName,
            mediaType: decoded['evidenceMediaType'] as String,
            byteLength: decoded['byteLength'] as int,
            sourceFingerprint: decoded['sourceFingerprint'] as String,
          );
          if (await fileForPreserved(source) == null) {
            throw StateError(
              'Pending receipt source does not match its journal.',
            );
          }
          final evidence = _evidenceFromPendingStatementManifest(decoded);
          if (evidence == null) {
            throw const FormatException('Invalid pending receipt evidence.');
          }
          final captureId = name.substring(
            'receipt-'.length,
            name.length - '.json'.length,
          );
          captures.add(
            PendingReceiptCapture(
              captureId: captureId,
              transactionId: transactionId,
              source: PreservedEvidenceSource(
                originalName: decoded['evidenceOriginalName'] as String,
                localFileName: localFileName,
                mediaType: decoded['evidenceMediaType'] as String,
                byteLength: decoded['byteLength'] as int,
                sourceFingerprint: decoded['sourceFingerprint'] as String,
              ),
              plannedEvidence: evidence,
            ),
          );
        } on Object {
          // Keep malformed journals for startup diagnostics and allow valid
          // captures in the same directory to remain recoverable.
        }
      }
      return captures;
    });
    return result;
  }

  Future<List<PendingGenericCapture>> listPendingGenericCaptures({
    String? captureKind,
  }) async {
    final result = await _runFinancialEvidenceMutation(() async {
      final directory = await _pendingEvidenceDirectory();
      if (!await directory.exists()) return const <PendingGenericCapture>[];
      final specific = await _specificPendingJournalLocalFileNames(
        directory,
        failOnMalformed: false,
      );
      final captures = <PendingGenericCapture>[];
      await for (final entity in directory.list(followLinks: false)) {
        final name = path.basename(entity.path);
        if (entity is! File ||
            !name.endsWith('.json') ||
            !name.startsWith('capture-')) {
          continue;
        }
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid pending capture manifest.');
          }
          final localFileName = decoded['localFileName'];
          final originalName = decoded['originalName'];
          final mediaType = decoded['mediaType'];
          final kind = decoded['captureKind'];
          if (localFileName is! String ||
              originalName is! String ||
              mediaType is! String ||
              (kind != null && kind is! String) ||
              specific.contains(localFileName)) {
            continue;
          }
          if (captureKind != null && kind != captureKind) continue;
          final pendingFile = await _validatedReadyPendingCaptureFile(
            directory,
            decoded,
          );
          final sourceFingerprint =
              decoded['sourceFingerprint'] as String? ??
              await sha256FileRange(pendingFile);
          captures.add(
            PendingGenericCapture(
              source: PreservedEvidenceSource(
                originalName: originalName,
                localFileName: localFileName,
                mediaType: mediaType,
                byteLength: decoded['byteLength'] as int,
                sourceFingerprint: sourceFingerprint,
              ),
              captureKind: kind as String?,
            ),
          );
        } on Object {
          // Preserve malformed generic manifests for explicit startup
          // diagnostics; valid captures remain listable.
        }
      }
      return captures;
    });
    return result;
  }

  Future<File> _validatedReadyPendingCaptureFile(
    Directory directory,
    Map<String, dynamic> decoded,
  ) async {
    final localFileName = decoded['localFileName'];
    if (localFileName is! String) {
      throw const FormatException('Pending capture source is invalid.');
    }
    await validateEvidencePath(
      directory,
      localFileName,
      message: 'Unsafe pending capture source path.',
    );
    final state = decoded[_receiptCaptureStateKey];
    if (state != null && state != _pendingCaptureReady) {
      throw StateError('Pending capture source is incomplete.');
    }
    final expectedLength = decoded['byteLength'];
    final expectedFingerprint = decoded['sourceFingerprint'];
    if (state == _pendingCaptureReady &&
        (expectedLength is! int ||
            expectedLength < 0 ||
            expectedFingerprint is! String ||
            expectedFingerprint.isEmpty)) {
      throw const FormatException('Pending capture readiness is invalid.');
    }
    final pending = File(path.join(directory.path, localFileName));
    if (!await pending.exists() && state == _pendingCaptureReady) {
      final temporary = await _pendingFileForName('$localFileName.tmp');
      if (temporary != null && await temporary.exists()) {
        if (await temporary.length() != expectedLength ||
            await sha256FileRange(temporary) != expectedFingerprint) {
          throw StateError('Pending capture source is incomplete.');
        }
        await temporary.rename(pending.path);
      }
    }
    if (!await pending.exists()) {
      throw StateError('Pending capture source is unavailable.');
    }
    if (state == _pendingCaptureReady &&
        (await pending.length() != expectedLength ||
            await sha256FileRange(pending) != expectedFingerprint)) {
      throw StateError('Pending capture source does not match its journal.');
    }
    return pending;
  }

  Future<bool> hasUnresolvedPendingCaptureJournals() async {
    return (await listPendingCaptureJournalIssues()).isNotEmpty;
  }

  /// Returns actionable, non-destructive diagnostics for journals that could
  /// not be parsed or safely associated with a pending source.
  ///
  /// The directory is scanned under the same evidence mutation lock as all
  /// other pending-capture operations. A malformed journal is reported by its
  /// own filename, so it cannot make every other pending source appear
  /// referenced or silently hide unrelated orphan files.
  Future<List<PendingCaptureJournalIssue>>
  listPendingCaptureJournalIssues() async {
    return _runFinancialEvidenceMutation(() async {
      final directory = await _pendingEvidenceDirectory();
      if (!await directory.exists()) {
        return const <PendingCaptureJournalIssue>[];
      }
      final files = await directory
          .list(followLinks: false)
          .where((entity) => entity is File && entity.path.endsWith('.json'))
          .toList();
      files.sort(
        (a, b) => path.basename(a.path).compareTo(path.basename(b.path)),
      );
      final issues = <PendingCaptureJournalIssue>[];
      for (final entity in files) {
        final file = entity as File;
        final fileName = path.basename(file.path);
        try {
          final decoded = jsonDecode(await file.readAsString());
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Journal is not a JSON object.');
          }
          if (fileName.startsWith('capture-')) {
            final localFileName = decoded['localFileName'];
            if (localFileName is! String ||
                (decoded['captureKind'] != null &&
                    decoded['captureKind'] is! String)) {
              throw const FormatException(
                'Generic capture fields are invalid.',
              );
            }
            await _validatedReadyPendingCaptureFile(directory, decoded);
          } else if (fileName.startsWith('receipt-')) {
            _validatePendingReceiptManifest(decoded);
            final localFileName = decoded['localFileName'] as String;
            await validateEvidencePath(
              directory,
              localFileName,
              message: 'Unsafe pending receipt source path.',
            );
            final source = PreservedEvidenceSource(
              originalName: decoded['evidenceOriginalName'] as String,
              localFileName: localFileName,
              mediaType: decoded['evidenceMediaType'] as String,
              byteLength: decoded['byteLength'] as int,
              sourceFingerprint: decoded['sourceFingerprint'] as String,
            );
            if (await fileForPreserved(source) == null) {
              throw StateError(
                'Pending receipt source does not match its journal.',
              );
            }
          } else if (fileName.startsWith('statement-')) {
            _validatePendingStatementManifest(decoded);
            final localFileName = decoded['localFileName'] as String;
            await validateEvidencePath(
              directory,
              localFileName,
              message: 'Unsafe pending statement source path.',
            );
            final source = PreservedEvidenceSource(
              originalName: decoded['evidenceOriginalName'] as String,
              localFileName: localFileName,
              mediaType: decoded['evidenceMediaType'] as String,
              byteLength: decoded['byteLength'] as int,
              sourceFingerprint: decoded['sourceFingerprint'] as String,
            );
            if (await fileForPreserved(source) == null) {
              throw StateError(
                'Pending statement source does not match its journal.',
              );
            }
          } else {
            throw const FormatException('Unrecognized pending journal name.');
          }
        } on Object catch (error) {
          issues.add(
            PendingCaptureJournalIssue(
              fileName: fileName,
              messageKey: _pendingCaptureJournalIssueKey(error),
            ),
          );
        }
      }
      return issues;
    });
  }

  String _pendingCaptureJournalIssueKey(Object error) {
    final detail = error.toString().toLowerCase();
    if (detail.contains('source')) {
      return 'captureRecoverySourceUnavailable';
    }
    return 'captureRecoveryJournalIssue';
  }

  /// Repairs a malformed typed journal into a generic, source-verified
  /// recovery record. When no source identity can be recovered, an explicit
  /// user dismissal removes only the journal and leaves every binary intact.
  Future<PendingCaptureJournalResolution> resolvePendingCaptureJournalIssue(
    String fileName, {
    String? captureKind,
  }) {
    return _runFinancialEvidenceMutation(() async {
      if (path.basename(fileName) != fileName || !fileName.endsWith('.json')) {
        return PendingCaptureJournalResolution.unavailable;
      }
      final isStatement = fileName.startsWith('statement-');
      final isReceipt = fileName.startsWith('receipt-');
      final isGeneric = fileName.startsWith('capture-');
      if (!isStatement && !isReceipt && !isGeneric) {
        return PendingCaptureJournalResolution.unavailable;
      }
      final directory = await _pendingEvidenceDirectory();
      final normalized = await validateEvidencePath(
        directory,
        fileName,
        message: 'Unsafe pending capture manifest path.',
      );
      final journal = File(path.join(directory.path, normalized));
      if (!await journal.exists()) {
        return PendingCaptureJournalResolution.unavailable;
      }
      Map<String, dynamic> decoded;
      try {
        final value = jsonDecode(await journal.readAsString());
        if (value is! Map<String, dynamic>) {
          if (!isGeneric) return PendingCaptureJournalResolution.unavailable;
          decoded = <String, dynamic>{};
        } else {
          decoded = value;
        }
      } on Object {
        if (!isGeneric) return PendingCaptureJournalResolution.unavailable;
        decoded = <String, dynamic>{};
      }
      var localFileName = decoded['localFileName'];
      if (localFileName is! String && isGeneric) {
        final derived = fileName.substring(
          'capture-'.length,
          fileName.length - '.json'.length,
        );
        if (derived.isNotEmpty) localFileName = derived;
      }
      if (localFileName is! String) {
        return PendingCaptureJournalResolution.unavailable;
      }
      try {
        await validateEvidencePath(
          directory,
          localFileName,
          message: 'Unsafe pending capture source path.',
        );
      } on FormatException {
        return PendingCaptureJournalResolution.unavailable;
      }
      final source = File(path.join(directory.path, localFileName));
      if (!await source.exists()) {
        return PendingCaptureJournalResolution.unavailable;
      }
      final byteLength = await source.length();
      final sourceFingerprint = await sha256FileRange(source);
      final originalName = decoded['originalName'] is String
          ? decoded['originalName'] as String
          : decoded['evidenceOriginalName'] is String
          ? decoded['evidenceOriginalName'] as String
          : localFileName;
      final mediaType = decoded['mediaType'] is String
          ? decoded['mediaType'] as String
          : decoded['evidenceMediaType'] is String
          ? decoded['evidenceMediaType'] as String
          : 'application/octet-stream';
      final genericManifest = await _preCaptureManifestFor(localFileName);
      await genericManifest.writeAsString(
        jsonEncode({
          'localFileName': localFileName,
          'originalName': originalName,
          'mediaType': mediaType,
          ...?captureKind == null ? null : {'captureKind': captureKind},
          if (isStatement) 'captureKind': 'statement',
          if (isReceipt) 'captureKind': 'receipt',
          _receiptCaptureStateKey: _pendingCaptureReady,
          'byteLength': byteLength,
          'sourceFingerprint': sourceFingerprint,
        }),
        flush: true,
      );
      // A malformed generic journal is itself the generic manifest path. Keep
      // the repaired ready-state record so the source remains listable and
      // recoverable after restart; typed journals are retired once converted.
      if (journal.path != genericManifest.path && await journal.exists()) {
        await journal.delete();
      }
      return PendingCaptureJournalResolution.repaired;
    });
  }

  Future<PendingCaptureJournalResolution> dismissPendingCaptureJournalIssue(
    String fileName,
  ) {
    return _runFinancialEvidenceMutation(() async {
      if (path.basename(fileName) != fileName || !fileName.endsWith('.json')) {
        return PendingCaptureJournalResolution.unavailable;
      }
      final directory = await _pendingEvidenceDirectory();
      final normalized = await validateEvidencePath(
        directory,
        fileName,
        message: 'Unsafe pending capture manifest path.',
      );
      final journal = File(path.join(directory.path, normalized));
      if (!await journal.exists()) {
        return PendingCaptureJournalResolution.unavailable;
      }
      await journal.delete();
      return PendingCaptureJournalResolution.dismissed;
    });
  }

  Future<bool> discardPendingGenericCapture(PreservedEvidenceSource source) =>
      _runFinancialEvidenceMutation(() async {
        final directory = await _pendingEvidenceDirectory();
        if (await directory.exists()) {
          try {
            final specific = await _specificPendingJournalLocalFileNames(
              directory,
            );
            if (specific.contains(source.localFileName)) return false;
          } on Object {
            // Any unresolved specific journal makes generic cancellation
            // unsafe. Leave all sources in place until recovery can classify
            // the journal explicitly.
            return false;
          }
        }
        await _discardPreservedUnlocked(source);
        return true;
      });

  Future<File> _pendingReceiptManifestFor(String captureId) async {
    final directory = await _pendingEvidenceDirectory();
    final name = await validateEvidencePath(
      directory,
      'receipt-$captureId.json',
      message: 'Unsafe pending receipt manifest path.',
    );
    return File(path.join(directory.path, name));
  }

  void _validatePendingReceiptManifest(Map<String, dynamic> decoded) {
    final transactionId = decoded['transactionId'];
    final evidenceId = decoded['evidenceId'];
    final localFileName = decoded['localFileName'];
    final originalName = decoded['evidenceOriginalName'];
    final mediaType = decoded['evidenceMediaType'];
    final sourceFingerprint = decoded['sourceFingerprint'];
    final byteLength = decoded['byteLength'];
    final captureState = decoded[_receiptCaptureStateKey];
    if (transactionId is! String ||
        evidenceId is! String ||
        localFileName is! String ||
        originalName is! String ||
        mediaType is! String ||
        sourceFingerprint is! String ||
        sourceFingerprint.isEmpty ||
        byteLength is! int ||
        byteLength < 0 ||
        (captureState != null && captureState is! String) ||
        _evidenceFromPendingStatementManifest(decoded) == null) {
      throw const FormatException('Invalid pending receipt fields.');
    }
    if (captureState != null &&
        captureState != _receiptCapturePrepared &&
        captureState != _receiptCaptureAwaitingTransaction &&
        captureState != _receiptCaptureTransactionCommitted &&
        captureState != _receiptCaptureCompleted &&
        captureState != _receiptCaptureCancelled) {
      throw FormatException('Unsupported pending receipt state: $captureState');
    }
  }

  EvidenceItem _newReceiptEvidence(PreservedEvidenceSource source) {
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final now = DateTime.now().toUtc();
    final extension = path.extension(source.originalName).toLowerCase();
    return EvidenceItem(
      id: EvidenceId('evidence-$token'),
      type: _type(extension),
      originalName: source.originalName,
      mediaType: source.mediaType,
      localFileName: source.localFileName,
      provenance: Provenance(
        id: ProvenanceId('evidence-provenance-$token'),
        sourceType: ProvenanceSourceType.scan,
        capturedAt: now,
        sourceId: source.sourceFingerprint,
        originalRepresentation: source.originalName,
      ),
      createdAt: now,
    );
  }

  /// Reconstructs a recoverable statement shell for a capture whose evidence
  /// was published before the process stopped. The shell keeps the original
  /// document visible and exposes the existing technical-retry flow instead
  /// of allowing orphan recovery to discard the user's source.
  Future<int> recoverPendingStatementCaptures() async {
    final result = await _runFinancialEvidenceMutation(() async {
      final statements = finance.statementServices;
      if (statements == null) return 0;
      final directory = await _pendingEvidenceDirectory();
      await rejectEvidenceRoot(
        directory,
        message: 'Unsafe pending evidence root.',
      );
      if (!await directory.exists()) return 0;
      final listed = await statements.list(includeArchived: true);
      if (listed is! ApplicationSuccess<List<FinancialStatement>>) {
        throw StateError('Pending statement listing failed.');
      }
      final existing = [...listed.value];
      var recovered = 0;
      Object? firstFailure;
      StackTrace? firstFailureStack;
      await for (final entity in directory.list(followLinks: false)) {
        final name = path.basename(entity.path);
        if (entity is! File ||
            !name.endsWith('.json') ||
            !name.startsWith('statement-')) {
          continue;
        }
        final manifest = entity;
        try {
          final decoded = jsonDecode(await manifest.readAsString());
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('Invalid pending statement manifest.');
          }
          _validatePendingStatementManifest(decoded);
          final statementId = decoded['statementId'];
          final evidenceId = decoded['evidenceId'];
          final originalFilename = decoded['originalFilename'];
          final createdAtValue = decoded['createdAt'];
          final paymentSourceId = decoded['paymentSourceId'];
          final manifestLocalFileName = decoded['localFileName'];
          final byteLength = decoded['byteLength'] as int;
          final sourceFingerprint = decoded['sourceFingerprint'] as String;
          final createdAt = DateTime.tryParse(createdAtValue)?.toUtc();
          if (createdAt == null) {
            throw const FormatException('Invalid pending statement timestamp.');
          }
          final manifestSource = PreservedEvidenceSource(
            originalName: decoded['evidenceOriginalName'] as String,
            localFileName: manifestLocalFileName as String,
            mediaType: decoded['evidenceMediaType'] as String,
            byteLength: byteLength,
            sourceFingerprint: sourceFingerprint,
          );
          await validateEvidencePath(
            directory,
            manifestLocalFileName,
            message: 'Unsafe pending statement source path.',
          );
          if (await fileForPreserved(manifestSource) == null) {
            throw StateError(
              'Pending statement source does not match its journal.',
            );
          }
          final captureState = decoded[_receiptCaptureStateKey] as String?;
          final existingStatement = existing
              .where((item) => item.id == statementId)
              .firstOrNull;
          final existingEvidenceOwner = existing
              .where((item) => item.evidenceId == evidenceId)
              .firstOrNull;
          if (captureState == _receiptCaptureCompleted) {
            await _discardPendingStatementJournal(
              manifest,
              manifestSource.localFileName,
            );
            continue;
          }
          if (existingStatement != null || existingEvidenceOwner != null) {
            if (existingStatement != null &&
                existingStatement.evidenceId != evidenceId) {
              throw const FormatException(
                'Pending statement does not match its existing evidence.',
              );
            }
            final existingEvidenceResult = await finance.getEvidence(
              evidenceId,
            );
            if (existingEvidenceResult case ApplicationFailure<EvidenceItem?>(
              :final failure,
            )) {
              if (failure.code == ApplicationFailureCode.notFound) {
                throw StateError('Existing statement evidence is unavailable.');
              }
              throw StateError('Existing statement evidence lookup failed.');
            }
            if (existingEvidenceResult case ApplicationSuccess<EvidenceItem?>(
              value: final existingEvidence,
            ) when existingEvidence != null) {
              if (existingEvidence.localFileName !=
                  manifestSource.localFileName) {
                throw const FormatException(
                  'Pending statement source does not match its evidence.',
                );
              }
              var live = await fileFor(existingEvidence);
              if (live == null ||
                  !await _matchesIntegrity(
                    live,
                    byteLength: byteLength,
                    sourceFingerprint: sourceFingerprint,
                  )) {
                live = await _promotePreservedUnlocked(
                  manifestSource,
                  expectedByteLength: byteLength,
                  expectedSourceFingerprint: sourceFingerprint,
                );
              }
              if (live == null ||
                  !await _matchesIntegrity(
                    live,
                    byteLength: byteLength,
                    sourceFingerprint: sourceFingerprint,
                  )) {
                throw StateError('Existing statement source is unavailable.');
              }
            } else {
              throw StateError('Existing statement evidence is unavailable.');
            }
            await _discardPendingStatementJournal(
              manifest,
              manifestSource.localFileName,
            );
            continue;
          }
          if (captureState == _receiptCaptureCancelled) {
            // A cancelled marker is only authoritative once the source row is
            // gone. If deletion or the prepared-state rollback failed, retain
            // the source and journal rather than deleting evidence still owned
            // by a live statement on restart.
            await _discardPendingStatementJournal(
              manifest,
              manifestSource.localFileName,
            );
            continue;
          }
          final evidenceResult = await finance.getEvidence(evidenceId);
          EvidenceItem? evidence;
          if (evidenceResult is ApplicationSuccess<EvidenceItem?>) {
            evidence = evidenceResult.value;
          } else if (evidenceResult case ApplicationFailure<EvidenceItem?>(
            :final failure,
          ) when failure.code == ApplicationFailureCode.notFound) {
            evidence = null;
          } else {
            throw StateError('Pending statement evidence lookup failed.');
          }
          if (evidence == null) {
            // The manifest is written before SQLite publication. If the
            // process stopped between those operations, rebuild the evidence
            // row from the journal and promote its already-preserved binary.
            final reconstructed = _evidenceFromPendingStatementManifest(
              decoded,
            );
            if (reconstructed == null) {
              throw const FormatException(
                'Pending statement evidence cannot be reconstructed.',
              );
            }
            final promoted = await _promotePreservedUnlocked(
              manifestSource,
              expectedByteLength: byteLength,
              expectedSourceFingerprint: sourceFingerprint,
            );
            if (promoted == null ||
                !await _matchesIntegrity(
                  promoted,
                  byteLength: byteLength,
                  sourceFingerprint: sourceFingerprint,
                )) {
              throw StateError('Pending statement source is unavailable.');
            }
            final stored = await finance.storeEvidence(reconstructed);
            if (stored is! ApplicationSuccess<EvidenceItem>) {
              throw StateError('Pending statement evidence store failed.');
            }
            evidence = reconstructed;
          }
          final localFileName = evidence.localFileName;
          if (localFileName == null) {
            throw StateError('Pending statement has no local evidence file.');
          }
          final promoted = await _promotePreservedUnlocked(
            manifestSource,
            expectedByteLength: byteLength,
            expectedSourceFingerprint: sourceFingerprint,
          );
          if (promoted == null ||
              !await _matchesIntegrity(
                promoted,
                byteLength: byteLength,
                sourceFingerprint: sourceFingerprint,
              )) {
            throw StateError('Pending statement source is unavailable.');
          }
          final statement = FinancialStatement(
            id: statementId,
            evidenceId: evidenceId,
            paymentSourceId: paymentSourceId as String?,
            status: paymentSourceId == null
                ? StatementStatus.needsSource
                : StatementStatus.ready,
            originalFilename: originalFilename,
            createdAt: createdAt,
            updatedAt: createdAt,
            extractionMessage: 'statementProcessingFailed',
          );
          final created = await statements.create(statement, const []);
          if (created is! ApplicationSuccess<void>) {
            throw StateError('Pending statement creation failed.');
          }
          existing.add(statement);
          await manifest.delete();
          await _removePreCaptureManifest(manifestLocalFileName);
          recovered++;
        } on Object catch (error, stackTrace) {
          // Do not let orphan cleanup run after an unresolved journal failure.
          // The manifest and any source evidence remain for the next recovery.
          if (firstFailure == null) {
            firstFailure = error;
            firstFailureStack = stackTrace;
          }
        }
      }
      if (firstFailure != null) {
        Error.throwWithStackTrace(firstFailure, firstFailureStack!);
      }
      return recovered;
    });
    return result;
  }

  EvidenceItem? _evidenceFromPendingStatementManifest(
    Map<String, dynamic> decoded,
  ) {
    final evidenceId = decoded['evidenceId'];
    final type = decoded['evidenceType'];
    final originalName = decoded['evidenceOriginalName'];
    final mediaType = decoded['evidenceMediaType'];
    final localFileName = decoded['localFileName'];
    final provenanceId = decoded['provenanceId'];
    final capturedAtValue = decoded['provenanceCapturedAt'];
    final createdAtValue = decoded['evidenceCreatedAt'];
    final sourceId = decoded['provenanceSourceId'];
    if (evidenceId is! String ||
        type is! String ||
        originalName is! String ||
        mediaType is! String ||
        localFileName is! String ||
        provenanceId is! String ||
        capturedAtValue is! String ||
        createdAtValue is! String ||
        (sourceId != null && sourceId is! String)) {
      return null;
    }
    final capturedAt = DateTime.tryParse(capturedAtValue)?.toUtc();
    final createdAt = DateTime.tryParse(createdAtValue)?.toUtc();
    if (capturedAt == null || createdAt == null) return null;
    final evidenceType = switch (type) {
      'document' => EvidenceType.document,
      'receiptImage' => EvidenceType.receiptImage,
      'other' => EvidenceType.other,
      _ => null,
    };
    if (evidenceType == null) return null;
    return EvidenceItem(
      id: EvidenceId(evidenceId),
      type: evidenceType,
      originalName: originalName,
      mediaType: mediaType,
      localFileName: localFileName,
      provenance: Provenance(
        id: ProvenanceId(provenanceId),
        sourceType: ProvenanceSourceType.scan,
        capturedAt: capturedAt,
        sourceId: sourceId as String?,
        originalRepresentation: originalName,
      ),
      createdAt: createdAt,
    );
  }

  void _validatePendingStatementManifest(Map<String, dynamic> decoded) {
    final statementId = decoded['statementId'];
    final evidenceId = decoded['evidenceId'];
    final originalFilename = decoded['originalFilename'];
    final createdAt = decoded['createdAt'];
    final localFileName = decoded['localFileName'];
    final paymentSourceId = decoded['paymentSourceId'];
    final sourceFingerprint = decoded['sourceFingerprint'];
    final byteLength = decoded['byteLength'];
    final captureState = decoded[_receiptCaptureStateKey];
    if (statementId is! String ||
        evidenceId is! String ||
        originalFilename is! String ||
        createdAt is! String ||
        DateTime.tryParse(createdAt) == null ||
        localFileName is! String ||
        (paymentSourceId != null && paymentSourceId is! String) ||
        sourceFingerprint is! String ||
        sourceFingerprint.isEmpty ||
        byteLength is! int ||
        byteLength < 0 ||
        (captureState != null && captureState is! String) ||
        _evidenceFromPendingStatementManifest(decoded) == null) {
      throw const FormatException('Invalid pending statement fields.');
    }
    if (captureState != null &&
        captureState != _receiptCapturePrepared &&
        captureState != _receiptCaptureCompleted &&
        captureState != _receiptCaptureCancelled) {
      throw FormatException(
        'Unsupported pending statement state: $captureState',
      );
    }
  }

  Future<T> _runFinancialEvidenceMutation<T>(Future<T> Function() operation) {
    final gate = finance.consistencyGate;
    Future<T> locked() => EvidenceMutationLock.runExclusive(operation);
    return gate == null ? locked() : gate.runExclusive(locked);
  }

  Future<T> runFinancialEvidenceMutation<T>(Future<T> Function() operation) =>
      _runFinancialEvidenceMutation(operation);

  Future<File?> fileFor(EvidenceItem evidence) async {
    final name = evidence.localFileName;
    if (name == null) return null;
    final root = await data.evidenceDirectory();
    try {
      final normalized = await validateEvidenceReferencePath(
        root,
        name,
        message: 'Unsafe local evidence path.',
      );
      return File(path.join(root.path, normalized));
    } on FormatException {
      // Invalid or symlinked references are not usable local evidence files.
      // Treating them as absent keeps preview/delete operations fail-safe.
      return null;
    }
  }

  Future<File?> fileForPreserved(PreservedEvidenceSource source) async {
    final pending = await _pendingFileFor(source);
    if (pending != null && await _matchesPreservedIntegrity(pending, source)) {
      return pending;
    }
    final liveRoot = await data.evidenceDirectory();
    try {
      final normalized = await validateEvidenceReferencePath(
        liveRoot,
        source.localFileName,
        message: 'Unsafe local evidence path.',
      );
      final live = File(path.join(liveRoot.path, normalized));
      return await _matchesPreservedIntegrity(live, source) ? live : null;
    } on FormatException {
      return null;
    }
  }

  Future<bool> _matchesPreservedIntegrity(
    File file,
    PreservedEvidenceSource source,
  ) async {
    if (!await file.exists()) return false;
    final expectedLength = source.byteLength;
    if (expectedLength == null) return true;
    final expectedFingerprint = source.sourceFingerprint;
    if (expectedFingerprint == null || expectedFingerprint.isEmpty) {
      return false;
    }
    return await file.length() == expectedLength &&
        await sha256FileRange(file) == expectedFingerprint;
  }

  /// Finds a statement by immutable source bytes, including statements
  /// created before source fingerprints were persisted in provenance.
  Future<FinancialStatement?> findStatementBySourceFingerprint(
    String fingerprint,
  ) async {
    final statements = finance.statementServices;
    if (statements == null) return null;
    final indexed = await statements.findBySourceFingerprint(fingerprint);
    if (indexed is ApplicationFailure<FinancialStatement?>) {
      throw StateError('Statement fingerprint lookup failed.');
    }
    if (indexed case ApplicationSuccess<FinancialStatement?>(
      value: final item,
    ) when item != null) {
      final evidenceResult = await finance.getEvidence(item.evidenceId);
      if (evidenceResult case ApplicationFailure<EvidenceItem?>(
        :final failure,
      )) {
        if (failure.code != ApplicationFailureCode.notFound) {
          throw StateError('Statement fingerprint evidence lookup failed.');
        }
      } else if (evidenceResult case ApplicationSuccess<EvidenceItem?>(
        value: final evidence,
      ) when evidence != null) {
        final expectedSourceId = statementSourceFingerprintPrefix + fingerprint;
        final file = await fileFor(evidence);
        if (evidence.provenance.sourceId == expectedSourceId &&
            file != null &&
            await file.exists() &&
            await sha256FileRange(file) == fingerprint) {
          return item;
        }
      }
    }
    final listed = await statements.list(includeArchived: true);
    if (listed is! ApplicationSuccess<List<FinancialStatement>>) {
      throw StateError('Statement fingerprint listing failed.');
    }
    for (final item in listed.value) {
      final evidenceResult = await finance.getEvidence(item.evidenceId);
      if (evidenceResult case ApplicationFailure<EvidenceItem?>(
        :final failure,
      )) {
        if (failure.code != ApplicationFailureCode.notFound) {
          throw StateError('Statement fingerprint evidence lookup failed.');
        }
        // A missing historical evidence row must not make an otherwise valid
        // new import impossible. The unavailable record is reported by
        // [listUnavailableStatementEvidence] for recovery diagnostics.
        continue;
      }
      if (evidenceResult is! ApplicationSuccess<EvidenceItem?> ||
          evidenceResult.value == null) {
        // A missing historical evidence row must not make an otherwise valid
        // new import impossible. The unavailable record is reported by
        // [listUnavailableStatementEvidence] for recovery diagnostics.
        continue;
      }
      if (evidenceResult.value!.provenance.sourceId != null) continue;
      final file = await fileFor(evidenceResult.value!);
      if (file == null || !await file.exists()) continue;
      if (await sha256FileRange(file) == fingerprint) return item;
    }
    return null;
  }

  /// Returns IDs for historical statements whose durable source evidence is
  /// unavailable. This is diagnostic only: missing historical evidence must
  /// not block a new statement import or authorize destructive cleanup.
  Future<List<String>> listUnavailableStatementEvidence() async {
    return _runFinancialEvidenceMutation(() async {
      final statements = finance.statementServices;
      if (statements == null) return const <String>[];
      final listed = await statements.list(includeArchived: true);
      if (listed is! ApplicationSuccess<List<FinancialStatement>>) {
        return const <String>[];
      }
      final unavailable = <String>[];
      for (final statement in listed.value) {
        final evidence = await finance.getEvidence(statement.evidenceId);
        if (evidence case ApplicationFailure<EvidenceItem?>(:final failure)) {
          if (failure.code != ApplicationFailureCode.notFound) {
            throw StateError('Statement evidence lookup failed.');
          }
          unavailable.add(statement.id);
          continue;
        }
        if (evidence is! ApplicationSuccess<EvidenceItem?> ||
            evidence.value == null) {
          unavailable.add(statement.id);
          continue;
        }
        final file = await fileFor(evidence.value!);
        if (file == null || !await file.exists()) {
          unavailable.add(statement.id);
        }
      }
      return unavailable;
    });
  }

  static String _newImmutableFileName(String extension) {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final token = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'evidence-$token$extension';
  }

  static EvidenceType _type(String extension) => switch (extension) {
    '.jpg' ||
    '.jpeg' ||
    '.png' ||
    '.heic' ||
    '.webp' => EvidenceType.receiptImage,
    '.pdf' => EvidenceType.document,
    _ => EvidenceType.other,
  };

  static String _mediaType(String extension) => switch (extension) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.heic' => 'image/heic',
    '.webp' => 'image/webp',
    '.pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };
}
