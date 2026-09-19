/// Semantic roles in versioned rule definitions. IDs identify a definition;
/// these roles describe the result consumed by application projections.
abstract final class AnalysisSemanticRole {
  static const expenseTotal = 'expenseTotal';
  static const incomeTotal = 'incomeTotal';
  static const netCashFlow = 'netCashFlow';
  static const eligibleTransactionCount = 'eligibleTransactionCount';
  static const spendingComparison = 'comparison:spending';
}
