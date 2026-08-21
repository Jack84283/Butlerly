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
    UserPreferenceRepository preferences, {
    ReconciliationCandidateRepository? reconciliationCandidates,
    ReconciliationLinkRepository? reconciliationLinks,
  }) : listTransactions = ListTransactions(transactions),
       seedInitialMasterData = SeedInitialMasterData(
         merchants,
         categories,
         tags,
       ),
       createTransaction = CreateTransaction(
         transactions,
         const SystemApplicationClock(),
       ),
       createReceiptTransaction = CreateReceiptTransaction(
         transactions,
         const SystemApplicationClock(),
       ),
       createPaymentTransaction = CreatePaymentTransaction(
         transactions,
         const SystemApplicationClock(),
       ),
       importTransaction = ImportTransaction(
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
       deleteTransactionPermanently = DeleteTransactionPermanently(
         transactions,
       ),
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
       listEvidenceForTransaction = ListEvidenceForTransaction(evidence),
       getExtractionForEvidence = GetExtractionForEvidence(
         evidence is ExtractionLookupRepository
             ? evidence as ExtractionLookupRepository
             : const _NoExtractionLookupRepository(),
       ),
       loadUserPreference = LoadUserPreference(preferences),
       saveUserPreference = SaveUserPreference(preferences),
       storeAndAttachEvidence = StoreAndAttachEvidence(evidence),
       removeEvidence = RemoveEvidence(evidence),
       saveExtraction = SaveExtraction(evidence),
       listReconciliationCandidates = ListReconciliationCandidates(
         reconciliationCandidates ??
             const _NoReconciliationCandidateRepository(),
       ),
       saveReconciliationCandidate = SaveReconciliationCandidate(
         reconciliationCandidates ??
             const _NoReconciliationCandidateRepository(),
       ),
       refreshReconciliationCandidates = RefreshReconciliationCandidates(
         transactions,
         reconciliationCandidates ??
             const _NoReconciliationCandidateRepository(),
       ),
       saveReconciliationLink = SaveReconciliationLink(
         reconciliationLinks ?? const _NoReconciliationLinkRepository(),
       ),
       listReconciliationLinks = ListReconciliationLinks(
         reconciliationLinks ?? const _NoReconciliationLinkRepository(),
       );

  final ListTransactions listTransactions;
  final SeedInitialMasterData seedInitialMasterData;
  final CreateTransaction createTransaction;
  final CreateReceiptTransaction createReceiptTransaction;
  final CreatePaymentTransaction createPaymentTransaction;
  final ImportTransaction importTransaction;
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
  final GetExtractionForEvidence getExtractionForEvidence;
  final LoadUserPreference loadUserPreference;
  final SaveUserPreference saveUserPreference;
  final StoreAndAttachEvidence storeAndAttachEvidence;
  final RemoveEvidence removeEvidence;
  final SaveExtraction saveExtraction;
  final ListReconciliationCandidates listReconciliationCandidates;
  final SaveReconciliationCandidate saveReconciliationCandidate;
  final RefreshReconciliationCandidates refreshReconciliationCandidates;
  final SaveReconciliationLink saveReconciliationLink;
  final ListReconciliationLinks listReconciliationLinks;
}

final class _NoExtractionLookupRepository
    implements ExtractionLookupRepository {
  const _NoExtractionLookupRepository();

  @override
  Future<Extraction?> findExtractionForEvidence(EvidenceId id) async => null;
}

final class _NoReconciliationCandidateRepository
    implements ReconciliationCandidateRepository {
  const _NoReconciliationCandidateRepository();

  @override
  Future<void> save(ReconciliationCandidate candidate) async {}

  @override
  Future<ReconciliationCandidate?> findById(String id) async => null;

  @override
  Future<List<ReconciliationCandidate>> listAll() async => const [];
}

final class _NoReconciliationLinkRepository
    implements ReconciliationLinkRepository {
  const _NoReconciliationLinkRepository();

  @override
  Future<void> save(ReconciliationLink link) async {}

  @override
  Future<List<ReconciliationLink>> listAll() async => const [];
}
