import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class FinanceServices {
  FinanceServices(TransactionRepository transactions)
    : listTransactions = ListTransactions(transactions),
      createTransaction = CreateTransaction(
        transactions,
        const SystemApplicationClock(),
      ),
      getTransaction = GetTransaction(transactions),
      updateTransaction = UpdateTransaction(
        transactions,
        const SystemApplicationClock(),
      ),
      archiveTransaction = ArchiveTransaction(
        transactions,
        const SystemApplicationClock(),
      ),
      restoreTransaction = RestoreTransaction(
        transactions,
        const SystemApplicationClock(),
      ),
      deleteTransactionPermanently = DeleteTransactionPermanently(transactions);

  final ListTransactions listTransactions;
  final CreateTransaction createTransaction;
  final GetTransaction getTransaction;
  final UpdateTransaction updateTransaction;
  final ArchiveTransaction archiveTransaction;
  final RestoreTransaction restoreTransaction;
  final DeleteTransactionPermanently deleteTransactionPermanently;
}
