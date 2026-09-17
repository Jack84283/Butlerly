import 'dart:io';
import 'dart:math';

import 'package:butlerly/core/data/local_data_manager.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/evidence/evidence_mutation_lock.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path;

final class PreservedEvidenceSource {
  const PreservedEvidenceSource({
    required this.originalName,
    required this.localFileName,
    required this.mediaType,
  });

  final String originalName;
  final String localFileName;
  final String mediaType;
}

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
  Future<PreservedEvidenceSource> preserve(XFile source) =>
      _preservePending(source);

  Future<PreservedEvidenceSource> _preservePending(XFile source) async {
    final directory = await _pendingEvidenceDirectory();
    await directory.create(recursive: true);
    final extension = path.extension(source.name).toLowerCase();
    final localFileName = _newImmutableFileName(extension);
    final destination = File(path.join(directory.path, localFileName));

    // Exclusive creation turns the immutable-path rule into a filesystem
    // invariant as well as a naming convention. It must never truncate an
    // existing pending or published evidence binary.
    await destination.create(exclusive: true);
    try {
      await destination.writeAsBytes(await source.readAsBytes(), flush: true);
    } catch (_) {
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
    return PreservedEvidenceSource(
      originalName: source.name,
      localFileName: localFileName,
      mediaType: source.mimeType ?? _mediaType(extension),
    );
  }

  Future<void> discardPreserved(PreservedEvidenceSource source) =>
      EvidenceMutationLock.runExclusive(
        () => _discardPreservedUnlocked(source),
      );

  Future<void> _discardPreservedUnlocked(PreservedEvidenceSource source) async {
    final file = await _pendingFileFor(source);
    if (file != null && await file.exists()) await file.delete();
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
  }) => EvidenceMutationLock.runExclusive(() async {
    final liveFile = await _promotePreservedUnlocked(source);
    if (liveFile == null) return null;
    try {
      final result = await _attachPreservedAndReturnUnlocked(
        transactionId: transactionId,
        source: source,
        sourceType: sourceType,
      );
      if (result != null) return result;
      await _returnToPendingUnlocked(source, liveFile);
      return null;
    } catch (_) {
      await _returnToPendingUnlocked(source, liveFile);
      rethrow;
    }
  });

  Future<EvidenceItem?> _attachPreservedAndReturnUnlocked({
    required String transactionId,
    required PreservedEvidenceSource source,
    ProvenanceSourceType sourceType = ProvenanceSourceType.scan,
  }) async {
    final extension = path.extension(source.originalName).toLowerCase();
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final now = DateTime.now().toUtc();
    final evidence = EvidenceItem(
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
    if (result is ApplicationSuccess<EvidenceItem>) return result.value;
    await finance.removeEvidence(evidence.id.value);
    return null;
  }

  /// Publishes a preserved statement binary and its SQLite evidence record under
  /// the same mutation boundary as restore.
  Future<EvidenceItem?> storePreservedStatement(
    PreservedEvidenceSource source,
  ) => EvidenceMutationLock.runExclusive(() async {
    final liveFile = await _promotePreservedUnlocked(source);
    if (liveFile == null) return null;
    try {
      final result = await _storePreservedStatementUnlocked(source);
      if (result != null) return result;
      await _returnToPendingUnlocked(source, liveFile);
      return null;
    } catch (_) {
      await _returnToPendingUnlocked(source, liveFile);
      rethrow;
    }
  });

  Future<EvidenceItem?> _storePreservedStatementUnlocked(
    PreservedEvidenceSource source,
  ) async {
    final token = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final now = DateTime.now().toUtc();
    final evidence = EvidenceItem(
      id: EvidenceId('statement-evidence-$token'),
      type: EvidenceType.document,
      originalName: source.originalName,
      mediaType: source.mediaType,
      localFileName: source.localFileName,
      provenance: Provenance(
        id: ProvenanceId('statement-evidence-provenance-$token'),
        sourceType: ProvenanceSourceType.scan,
        capturedAt: now,
        originalRepresentation: source.originalName,
      ),
      createdAt: now,
    );
    final result = await finance.storeEvidence(evidence);
    return result is ApplicationSuccess<EvidenceItem> ? result.value : null;
  }

  /// Creates and publishes a receipt as one lock-protected logical mutation.
  Future<EvidenceItem?> attachAndReturn({
    required String transactionId,
    required XFile source,
    ProvenanceSourceType sourceType = ProvenanceSourceType.scan,
  }) => EvidenceMutationLock.runExclusive(() async {
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
      EvidenceMutationLock.runExclusive(() async {
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
    PreservedEvidenceSource source,
  ) async {
    final pending = await _pendingFileFor(source);
    if (pending == null || !await pending.exists()) return null;
    final liveDirectory = await data.evidenceDirectory();
    await liveDirectory.create(recursive: true);
    final live = File(path.join(liveDirectory.path, source.localFileName));
    if (await live.exists()) {
      // Random immutable names make this effectively impossible, but never
      // truncate an existing published binary if a collision is observed.
      return null;
    }
    return pending.rename(live.path);
  }

  Future<void> _returnToPendingUnlocked(
    PreservedEvidenceSource source,
    File liveFile,
  ) async {
    if (!await liveFile.exists()) return;
    final pendingDirectory = await _pendingEvidenceDirectory();
    await pendingDirectory.create(recursive: true);
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
    if (path.basename(source.localFileName) != source.localFileName) {
      return null;
    }
    return File(
      path.join((await _pendingEvidenceDirectory()).path, source.localFileName),
    );
  }

  Future<bool> remove(EvidenceItem evidence) =>
      EvidenceMutationLock.runExclusive(() async {
        final result = await finance.removeEvidence(evidence.id.value);
        if (result is! ApplicationSuccess<void>) return false;
        final file = await fileFor(evidence);
        if (file != null && await file.exists()) await file.delete();
        return true;
      });

  Future<bool> removeUnprocessedStatement(String statementId) =>
      EvidenceMutationLock.runExclusive(() async {
        final result = await finance.statementServices?.deleteStatement(
          statementId,
        );
        if (result is! ApplicationSuccess<EvidenceItem?>) return false;
        final evidence = result.value;
        if (evidence == null) return true;
        final file = await fileFor(evidence);
        if (file != null && await file.exists()) await file.delete();
        return true;
      });

  Future<bool> abandonStatementImport(String statementId) =>
      EvidenceMutationLock.runExclusive(() async {
        final result = await finance.statementServices?.abandonImport(
          statementId,
        );
        if (result is! ApplicationSuccess<EvidenceItem?>) return false;
        final evidence = result.value;
        if (evidence == null) return true;
        final file = await fileFor(evidence);
        if (file != null && await file.exists()) await file.delete();
        return true;
      });

  Future<File?> fileFor(EvidenceItem evidence) async {
    final name = evidence.localFileName;
    if (name == null || path.basename(name) != name) return null;
    return File(path.join((await data.evidenceDirectory()).path, name));
  }

  Future<File?> fileForPreserved(PreservedEvidenceSource source) =>
      _pendingFileFor(source);

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
