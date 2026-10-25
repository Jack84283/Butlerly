import 'package:flutter/foundation.dart';

/// Refresh budget summaries after local writes without coupling Home to storage.
final BudgetChangeNotifier budgetChanges = BudgetChangeNotifier();

void notifyBudgetsChanged() => budgetChanges.changed();

class BudgetChangeNotifier extends ChangeNotifier {
  void changed() => notifyListeners();
}
