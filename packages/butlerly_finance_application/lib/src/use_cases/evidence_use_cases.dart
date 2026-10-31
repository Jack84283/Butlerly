import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../analysis/invalidation.dart';
import '../result/application_result.dart';

const _evidenceCleanupRecoveryPrefix = 'Evidence cleanup requires recovery:';

final class ListAllEvidence {
  const ListAllEvidence(this.repository);

  final EvidenceRepository repository;

  Future<ApplicationResult<List<EvidenceItem>>> call() =>
      runApplication('list all evidence', () async {
        if (repository is! EvidenceListingRepository) {
          throw const RepositoryException(
            RepositoryFailureCode.unavailable,
            'list all evidence: repository capability',
          );
        }
        return List.unmodifiable(
          await (repository as EvidenceListingRepository).listAll(),
        );
      });
}

final class StoreEvidence {
  const StoreEvidence(this.repository);
  final EvidenceRepository repository;
  Future<ApplicationResult<EvidenceItem>> call(EvidenceItem evidence) =>
      runApplication('store evidence', () async {
        await repository.save(evidence);
        return evidence;
      });
}

final class GetEvidence {
  const GetEvidence(this.repository);

  final EvidenceRepository repository;

  Future<ApplicationResult<EvidenceItem?>> call(String evidenceId) =>
      runApplication('get evidence', () {
        return repository.findById(EvidenceId(evidenceId));
      });
}

final class GetExtractionForEvidence {
  const GetExtractionForEvidence(this.repository);

  final ExtractionLookupRepository repository;

  Future<ApplicationResult<Extraction?>> call(String evidenceId) =>
      runApplication('get evidence extraction', () {
        return repository.findExtractionForEvidence(EvidenceId(evidenceId));
      });
}

/// Removes evidence only after confirming that no durable record still owns
/// it. The optional file callback runs before metadata removal so a failed
/// filesystem cleanup leaves the evidence record available for retry.
final class CleanupUnreferencedEvidence {
  const CleanupUnreferencedEvidence(
    this.repository, {
    this.deleteEvidenceFile,
    this.finalizeDeletedEvidenceFile,
    this.consistencyGate,
  });

  final EvidenceRepository repository;
  final Future<void> Function(EvidenceItem evidence)? deleteEvidenceFile;
  final Future<void> Function(EvidenceItem evidence)?
  finalizeDeletedEvidenceFile;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<bool>> call(String evidenceId) => _runExclusive(
    () => runApplication('cleanup unreferenced evidence', () async {
      final referenceAware = repository;
      if (referenceAware is! ReferenceAwareEvidenceRepository) {
        throw const RepositoryException(
          RepositoryFailureCode.unavailable,
          'cleanup unreferenced evidence: repository capability',
        );
      }
      final capability = referenceAware as ReferenceAwareEvidenceRepository;
      final evidence = await repository.findById(EvidenceId(evidenceId));
      if (evidence == null) return true;
      final removed = await capability.removeIfUnreferenced(
        evidence.id,
        beforeRemove: deleteEvidenceFile == null
            ? null
            : () async {
                try {
                  await deleteEvidenceFile!(evidence);
                  return true;
                } on Object {
                  return false;
                }
              },
      );
      if (removed) {
        await finalizeDeletedEvidenceFile?.call(evidence);
        return true;
      }
      // Shared evidence is intentionally retained and therefore already
      // satisfies cleanup for the deleted transaction.
      return await capability.hasReferences(evidence.id);
    }),
  );

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}

/// Removes only the attachment from one transaction. Evidence is deleted
/// afterward only when no statement or transaction still owns it.
final class RemoveEvidenceFromTransaction {
  const RemoveEvidenceFromTransaction(
    this.repository, {
    this.deleteEvidenceFile,
    this.finalizeDeletedEvidenceFile,
    this.withEvidenceMutationLock,
    this.consistencyGate,
  });

  final EvidenceRepository repository;
  final Future<void> Function(EvidenceItem evidence)? deleteEvidenceFile;
  final Future<void> Function(EvidenceItem evidence)?
  finalizeDeletedEvidenceFile;
  final Future<T> Function<T>(Future<T> Function() action)?
  withEvidenceMutationLock;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<bool>> call(
    String transactionId,
    String evidenceId,
  ) => _runExclusive(() {
    final lock = withEvidenceMutationLock;
    return lock == null
        ? _remove(transactionId, evidenceId)
        : lock(() => _remove(transactionId, evidenceId));
  });

  Future<ApplicationResult<bool>> _remove(
    String transactionId,
    String evidenceId,
  ) => runApplication('remove evidence from transaction', () async {
    await repository.unlinkFromTransaction(
      TransactionId(transactionId),
      EvidenceId(evidenceId),
    );
    if (repository case final ReferenceAwareEvidenceRepository capability) {
      final evidence = await repository.findById(EvidenceId(evidenceId));
      if (evidence == null) return true;
      final removed = await capability.removeIfUnreferenced(
        evidence.id,
        beforeRemove: deleteEvidenceFile == null
            ? null
            : () async {
                try {
                  await deleteEvidenceFile!(evidence);
                  return true;
                } on Object {
                  return false;
                }
              },
      );
      if (removed) {
        await finalizeDeletedEvidenceFile?.call(evidence);
        return true;
      }
      if (await capability.hasReferences(evidence.id)) return true;
      throw RepositoryException(
        RepositoryFailureCode.unavailable,
        '$_evidenceCleanupRecoveryPrefix${evidence.id.value}',
      );
    }
    return true;
  });

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}

/// Repairs evidence left unowned by an interrupted transaction/statement
/// deletion. This is intentionally conservative: referenced evidence is
/// retained, while unreferenced records use the same file-before-metadata
/// cleanup contract as normal deletion.
final class RecoverUnreferencedEvidence {
  const RecoverUnreferencedEvidence(
    this.repository, {
    this.deleteEvidenceFile,
    this.finalizeDeletedEvidenceFile,
    this.consistencyGate,
  });

  final EvidenceRepository repository;
  final Future<void> Function(EvidenceItem evidence)? deleteEvidenceFile;
  final Future<void> Function(EvidenceItem evidence)?
  finalizeDeletedEvidenceFile;
  final AnalysisConsistencyGate? consistencyGate;

  Future<ApplicationResult<int>> call() => _runExclusive(
    () => runApplication('recover unreferenced evidence', () async {
      if (repository is! ReferenceAwareEvidenceRepository ||
          repository is! EvidenceListingRepository) {
        return 0;
      }
      final references = repository as ReferenceAwareEvidenceRepository;
      final listing = repository as EvidenceListingRepository;
      var repaired = 0;
      for (final evidence in await listing.listAll()) {
        if (await references.hasReferences(evidence.id)) continue;
        final removed = await references.removeIfUnreferenced(
          evidence.id,
          beforeRemove: deleteEvidenceFile == null
              ? null
              : () async {
                  try {
                    await deleteEvidenceFile!(evidence);
                    return true;
                  } on Object {
                    return false;
                  }
                },
        );
        if (removed) {
          await finalizeDeletedEvidenceFile?.call(evidence);
          repaired++;
        }
      }
      return repaired;
    }),
  );

  Future<ApplicationResult<T>> _runExclusive<T>(
    Future<ApplicationResult<T>> Function() operation,
  ) {
    final gate = consistencyGate;
    return gate == null ? operation() : gate.runExclusive(operation);
  }
}
