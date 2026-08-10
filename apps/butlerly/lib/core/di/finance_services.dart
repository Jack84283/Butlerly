import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class FinanceServices {
  FinanceServices(
    TransactionRepository transactions,
    PaymentSourceRepository paymentSources,
    MerchantRepository merchants,
    CategoryRepository categories,
    TagRepository tags,
    EvidenceRepository evidence,
  ) : listTransactions = ListTransactions(transactions),
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
      deleteTransactionPermanently = DeleteTransactionPermanently(transactions),
      listPaymentSources = ListPaymentSources(paymentSources),
      savePaymentSource = SavePaymentSource(paymentSources),
      archivePaymentSource = ArchivePaymentSource(paymentSources),
      assignPaymentSource = AssignPaymentSource(
        transactions,
        paymentSources,
        const SystemApplicationClock(),
      ),
      listMerchants = ListMerchants(merchants),
      listCategories = ListCategories(categories),
      listTags = ListTags(tags),
      saveMerchant = SaveMerchant(merchants),
      saveCategory = SaveCategory(categories),
      saveTag = SaveTag(tags),
      assignMerchant = AssignMerchant(
        transactions,
        merchants,
        const SystemApplicationClock(),
      ),
      assignCategory = AssignCategory(
        transactions,
        categories,
        const SystemApplicationClock(),
      ),
      addTag = AddTag(transactions, tags, const SystemApplicationClock()),
      removeTag = RemoveTag(transactions, const SystemApplicationClock()),
      listReviewItems = ListReviewItems(transactions),
      resolveReviewIssue = ResolveReviewIssue(
        transactions,
        const SystemApplicationClock(),
      ),
      dismissReviewIssue = DismissReviewIssue(
        transactions,
        const SystemApplicationClock(),
      ),
      listEvidenceForTransaction = ListEvidenceForTransaction(evidence);

  final ListTransactions listTransactions;
  final CreateTransaction createTransaction;
  final GetTransaction getTransaction;
  final UpdateTransaction updateTransaction;
  final ArchiveTransaction archiveTransaction;
  final RestoreTransaction restoreTransaction;
  final DeleteTransactionPermanently deleteTransactionPermanently;
  final ListPaymentSources listPaymentSources;
  final SavePaymentSource savePaymentSource;
  final ArchivePaymentSource archivePaymentSource;
  final AssignPaymentSource assignPaymentSource;
  final ListMerchants listMerchants;
  final ListCategories listCategories;
  final ListTags listTags;
  final SaveMerchant saveMerchant;
  final SaveCategory saveCategory;
  final SaveTag saveTag;
  final AssignMerchant assignMerchant;
  final AssignCategory assignCategory;
  final AddTag addTag;
  final RemoveTag removeTag;
  final ListReviewItems listReviewItems;
  final ResolveReviewIssue resolveReviewIssue;
  final DismissReviewIssue dismissReviewIssue;
  final ListEvidenceForTransaction listEvidenceForTransaction;
}
