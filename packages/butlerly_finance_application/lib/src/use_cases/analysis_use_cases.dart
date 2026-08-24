import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';
import '../dto/transaction_dto.dart';
import '../analysis/dataset_builder.dart';
import '../analysis/rule_engine.dart';

final class CalculateAnalysisOverview {
  const CalculateAnalysisOverview(this.rules, this.datasetBuilder, this.engine);
  final AnalysisRuleRepository rules;
  final AnalysisDatasetBuilder datasetBuilder;
  final AnalysisRuleEngine engine;

  Future<ApplicationResult<List<RuleExecutionResult>>> call(
    AnalysisContext context,
  ) => runApplication('calculate analysis overview', () async {
    final dataset = await datasetBuilder.build(context);
    if (dataset case ApplicationDatasetFailure()) {
      throw const RepositoryException(
        RepositoryFailureCode.unavailable,
        'analysis dataset unavailable',
      );
    }
    final definitions = await rules.listActive();
    return engine.execute(
      dataset: (dataset as ApplicationDatasetSuccess).dataset,
      definitions: definitions,
    );
  });
}

final class QueryTransactionsForFinancialDate {
  const QueryTransactionsForFinancialDate(this.repository);
  final TransactionRepository repository;

  Future<ApplicationResult<List<TransactionDto>>> call(String date) =>
      runApplication('query financial date transactions', () async {
        final values = await repository.listAll();
        return values
            .where(
              (value) =>
                  value.transactionDate == date &&
                  value.status == TransactionStatus.active,
            )
            .map(TransactionDto.fromDomain)
            .toList(growable: false);
      });
}

final class UpdateFindingLifecycle {
  const UpdateFindingLifecycle(this.repository);
  final AnalysisFindingRepository repository;

  Future<ApplicationResult<void>> call(
    String id,
    FindingLifecycle lifecycle,
    DateTime at,
  ) => runApplication(
    'update analysis finding lifecycle',
    () => repository.updateLifecycle(id, lifecycle, at),
  );
}
