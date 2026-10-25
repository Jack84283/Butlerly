import 'package:flutter/foundation.dart';

/// Refresh budget summaries after local budget writes without coupling Home to storage.
final ChangeNotifier budgetChanges = ChangeNotifier();

void notifyBudgetsChanged() => budgetChanges.notifyListeners();
