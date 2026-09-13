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

  /// Preserves evidence under a new immutable local path.
  ///
  /// Once an evidence path is published to SQLite its bytes are never replaced
  /// in place. A new capture gets a new path. Restore and normal evidence
  /// mutations share one filesystem lock so the live evidence tree cannot
  /// change while restore stages/activates it.
  Future<PreservedEvidenceSource> preserve(XFile source) =>
      EvidenceMutationLock.runExclusive(() => _preserveUnlocked(source));

  Future<PreservedEvidenceSource> _preserveUnlocked(XFile source) async {
    final directory = await data.evidenceDirectory();
    await directory.create(recursive: true);
    final extension = path.extension(source.name).toLowerCase();
    final localFileName = _newImmutableFileName(extension);
    final destination = File(path.join(directory.path, localFileName));

    // Exclusive creation turns the immutable-path rule into a filesystem
    // invariant as well as a naming convention. It must never truncate an
    // existing evidence binary.
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
      EvidenceMutationLock.runExclusive(() => _discardPreservedUnlocked(source));

  Future<void> _discardPreservedUnlocked(PreservedEvidenceSource source) async {
    final file = await _fileForPreservedUnlocked(source);
    if (file != null && await file.exists()) await file.delete();
  }

  /// Publishes an already preserved binary and its SQLite evidence record under
  /// the same mutation boundary used by restore.
  ///
  /// A receipt may stay preserved while OCR/review is in progress, so keeping
  /// the global restore lock for the entire UI interaction would be unsafe. The
  /// publish step therefore reacquires the lock, verifies that restore has not
  /// replaced the preserved binary, and only then commits its database record.
  /// This prevents metadata from ever being published for a file that a restore
  /// removed between preserve and publish.
  Future<EvidenceItem?> attachPreservedAndReturn({
    required String transactionId,
    required PreservedEvidenceSource source,
    ProvenanceSourceType sourceType = ProvenanceSourceType.scan,
  }) => EvidenceMutationLock.runExclusive(() async {
    if (!await _preservedExistsUnlocked(source)) return null;
    return _attachPreservedAndReturnUnlocked(
      transactionId: transactionId,
      source: source,
      sourceType: sourceType,
    );
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

  /// Publishes a preserved statement binary and its SQLite evidence record while
  /// restore is excluded from the live evidence root.
  Future<EvidenceItem?> storePreservedStatement(
    PreservedEvidenceSource source,
  ) => EvidenceMutationLock.runExclusive(() async {
    if (!await _preservedExistsUnlocked(source)) return null;
    return _storePreservedStatementUnlocked(source);
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

  /// Creates the immutable binary and publishes its evidence metadata as one
  /// logical mutation. Restore cannot interpose between the file write and the
  /// SQLite publication on this convenience path.
  Future<EvidenceItem?> attachAndReturn({
    required String transactionId,
    required XFile source,
    ProvenanceSourceType sourceType = ProvenanceSourceType.scan,
  }) => EvidenceMutationLock.runExclusive(() async {
    final preserved = await _preserveUnlocked(source);
    final result = await _attachPreservedAndReturnUnlocked(
      transactionId: transactionId,
      source: preserved,
      sourceType: sourceType,
    );
    if (result == null) await _discardPreservedUnlocked(preserved);
    return result;
  });

  Future<bool> _preservedExistsUnlocked(PreservedEvidenceSource source) async {
    final file = await _fileForPreservedUnlocked(source);
    return file != null && await file.exists();
  }

  Future<File?> _fileForPreservedUnlocked(PreservedEvidenceSource source) async {
    if (path.basename(source.localFileName) != source.localFileName) {
      return null;
    }
    return File(
      path.join((await data.evidenceDirectory()).path, source.localFileName),
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
        final result = await finance.statementServices?.abandonImport(statementId);
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
      _fileForPreservedUnlocked(source);

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
