import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

/// P0 profile persistence boundary.
///
/// P1 personalization of Analysis and Insights is intentionally deferred until
/// those surfaces expose a focused, testable relevance-ranking integration.
/// These use cases therefore never change transaction calculations or insight
/// output by themselves.
final class LoadFinancialProfile {
  const LoadFinancialProfile(this.repository);

  final FinancialProfileRepository repository;

  Future<ApplicationResult<FinancialProfile?>> call() =>
      runApplication('load financial profile', repository.load);
}

final class SaveFinancialProfile {
  const SaveFinancialProfile(this.repository);

  final FinancialProfileRepository repository;

  Future<ApplicationResult<FinancialProfile>> call(FinancialProfile profile) =>
      runApplication('save financial profile', () async {
        await repository.save(profile);
        return profile;
      });
}

final class ClearFinancialProfile {
  const ClearFinancialProfile(this.repository);

  final FinancialProfileRepository repository;

  Future<ApplicationResult<void>> call() =>
      runApplication('clear financial profile', repository.clear);
}
