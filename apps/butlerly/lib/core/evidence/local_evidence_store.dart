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
      EvidenceMutationLock.runExclusive(() async {
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
      });

  Future<void> discardPreserved(PreservedEvidenceSource source) =>
      EvidenceMutationLock.runExclusive(() async {
        final file = File(
          path.join((await data.evidenceDirectory()).path, source.localFileName),
        );
        if (await file.exists()) await file.delete();
      });

  Future<EvidenceItem?> attachPreservedAndReturn({
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

  Future<EvidenceItem?> storePreservedStatement(
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

  Future<EvidenceItem?> attachAndReturn({
    required String transactionId,
    required XFile source,
    ProvenanceSourceType sourceType = ProvenanceSourceType.scan,
  }) async {
    final preserved = await preserve(source);
    final result = await attachPreservedAndReturn(
      transactionId: transactionId,
      source: preserved,
      sourceType: sourceType,
    );
    if (result == null) await discardPreserved(preserved);
    return result;
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

  Future<File?> fileForPreserved(PreservedEvidenceSource source) async {
    if (path.basename(source.localFileName) != source.localFileName) {
      return null;
    }
    return File(
      path.join((await data.evidenceDirectory()).path, source.localFileName),
    );
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
