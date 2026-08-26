import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

final class StoreEvidence {
  const StoreEvidence(this.repository);
  final EvidenceRepository repository;
  Future<ApplicationResult<EvidenceItem>> call(EvidenceItem evidence) =>
      runApplication('store evidence', () async {
        await repository.save(evidence);
        return evidence;
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
