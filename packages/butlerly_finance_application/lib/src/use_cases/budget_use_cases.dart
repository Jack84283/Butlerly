import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

/// Application boundary for persisted user-approved monthly budget limits.
final class ManageBudgets {
  const ManageBudgets(this.repository);

  final BudgetRepository repository;

  Future<ApplicationResult<List<Budget>>> list() =>
      runApplication('list monthly budgets', repository.list);

  Future<ApplicationResult<bool>> save(Budget budget) =>
      runApplication('save monthly budget', () async {
        await repository.save(budget);
        return true;
      });

  Future<ApplicationResult<bool>> remove(String id) =>
      runApplication('delete monthly budget', () async {
        await repository.remove(id);
        return true;
      });
}
