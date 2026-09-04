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
    MasterTranslationRepository? masterTranslations,
    ReferenceDataRepository? referenceData,
    ReconciliationCandidateRepository? reconciliationCandidates,
    ReconciliationLinkRepository? reconciliationLinks,
    ReconciliationWorkflowRepository? reconciliationWorkflow,
    ExchangeRateRepository? exchangeRates,
    AnalysisRuleRepository? analysisRules,
    AnalysisFindingRepository? analysisFindings,
    AnalysisRuleResultRepository? analysisResults,
    StatementRepository? statements,
    DuplicateCandidateGroupRepository? duplicateGroups,
  }) : listTransactions = ListTransactions(transactions),
       seedInitialMasterData = SeedInitialMasterData(
         merchants,
         categories,
         tags,
         masterTranslations ?? const _NoMasterTranslationRepository(),
         referenceData ?? const _NoReferenceDataRepository(),
       ),
       loadMasterTranslations = LoadMasterTranslations(
         masterTranslations ?? const _NoMasterTranslationRepository(),
       ),
       loadReferenceData = LoadReferenceData(
         referenceData ?? const _NoReferenceDataRepository(),
       ),
       createTransaction = CreateTransaction(
         transactions,
         const SystemApplicationClock(),
       ),
       createReceiptTransaction = CreateReceiptTransaction(
         transactions,
         const SystemApplicationClock(),
         classifier: ProposeTransactionClassification(transactions, merchants),
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
       storeEvidence = StoreEvidence(evidence),
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
       ),
       confirmReconciliation = ConfirmReconciliation(
         reconciliationWorkflow ?? const _NoReconciliationWorkflowRepository(),
         transactions,
       ),
       rejectReconciliation = RejectReconciliation(
         reconciliationWorkflow ?? const _NoReconciliationWorkflowRepository(),
         transactions,
       ),
       findReceiptPaymentMatch = FindReceiptPaymentMatch(transactions),
       duplicateTransactionChecker = DuplicateTransactionChecker(transactions),
       scanExistingTransactionsForDuplicates = duplicateGroups == null
           ? null
           : ScanExistingTransactionsForDuplicates(
               duplicateGroups,
               const SystemApplicationClock(),
             ),
       listDuplicateCandidateGroups = duplicateGroups == null
           ? null
           : ListDuplicateCandidateGroups(duplicateGroups),
       resolveDuplicateCandidateGroup = duplicateGroups == null
           ? null
           : ResolveDuplicateCandidateGroup(
               duplicateGroups,
               const SystemApplicationClock(),
             ),
       evaluateTransactionNormalization = EvaluateTransactionNormalization(
         transactions,
         preferences,
         exchangeRates,
         const SystemApplicationClock(),
       ),
       confirmUserNormalizedAmount = ConfirmUserNormalizedAmount(
         transactions,
         preferences,
         const SystemApplicationClock(),
       ),
       installBuiltInRules = analysisRules == null
           ? null
           : InstallBuiltInRules(analysisRules),
       calculateAnalysisOverview = analysisRules == null
           ? null
           : CalculateAnalysisOverview(
               analysisRules,
               AnalysisDatasetBuilder(
                 transactions,
                 preferences,
                 reconciliationLinks,
                 candidates: reconciliationCandidates,
               ),
               const AnalysisRuleEngine(),
               findings: analysisFindings,
               results: analysisResults,
             ),
       calculateAnalysisCalendar = analysisRules == null
           ? null
           : CalculateAnalysisCalendar(
               AnalysisDatasetBuilder(
                 transactions,
                 preferences,
                 reconciliationLinks,
                 candidates: reconciliationCandidates,
               ),
               analysisRules,
               const AnalysisRuleEngine(),
             ),
       queryTransactionsForFinancialDate = QueryTransactionsForFinancialDate(
         transactions,
       ),
       statementServices = statements == null || duplicateGroups == null
           ? null
           : StatementServices(
               statements,
               transactions,
               statements as StatementWorkflowRepository,
               const SystemApplicationClock(),
               evidence: evidence,
               duplicateGroups: duplicateGroups,
               duplicateChecker: DuplicateTransactionChecker(transactions),
               classifier: ProposeTransactionClassification(
                 transactions,
                 merchants,
               ),
             ),
       updateAnalysisFindingLifecycle = analysisFindings == null
           ? null
           : UpdateFindingLifecycle(analysisFindings),
       invalidateAnalysis = analysisFindings == null
           ? null
           : InvalidateAnalysis(
               analysisFindings,
               results: analysisResults,
               rules: analysisRules,
             );

  final ListTransactions listTransactions;
  final SeedInitialMasterData seedInitialMasterData;
  final LoadMasterTranslations loadMasterTranslations;
  final LoadReferenceData loadReferenceData;
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
  final StoreEvidence storeEvidence;
  final RemoveEvidence removeEvidence;
  final SaveExtraction saveExtraction;
  final ListReconciliationCandidates listReconciliationCandidates;
  final SaveReconciliationCandidate saveReconciliationCandidate;
  final RefreshReconciliationCandidates refreshReconciliationCandidates;
  final SaveReconciliationLink saveReconciliationLink;
  final ListReconciliationLinks listReconciliationLinks;
  final ConfirmReconciliation confirmReconciliation;
  final RejectReconciliation rejectReconciliation;
  final EvaluateTransactionNormalization evaluateTransactionNormalization;
  final ConfirmUserNormalizedAmount confirmUserNormalizedAmount;
  final FindReceiptPaymentMatch findReceiptPaymentMatch;
  final DuplicateTransactionChecker duplicateTransactionChecker;
  final ScanExistingTransactionsForDuplicates?
  scanExistingTransactionsForDuplicates;
  final ListDuplicateCandidateGroups? listDuplicateCandidateGroups;
  final ResolveDuplicateCandidateGroup? resolveDuplicateCandidateGroup;
  final InstallBuiltInRules? installBuiltInRules;
  final CalculateAnalysisOverview? calculateAnalysisOverview;
  final CalculateAnalysisCalendar? calculateAnalysisCalendar;
  final QueryTransactionsForFinancialDate queryTransactionsForFinancialDate;
  final UpdateFindingLifecycle? updateAnalysisFindingLifecycle;
  final InvalidateAnalysis? invalidateAnalysis;
  final StatementServices? statementServices;
}

final class _NoMasterTranslationRepository
    implements MasterTranslationRepository {
  const _NoMasterTranslationRepository();

  @override
  Future<Map<String, String>> labels({
    required String masterType,
    required String locale,
  }) async => {};

  @override
  Future<void> saveAll(List<MasterTranslation> translations) async {}
}

final class _NoReferenceDataRepository implements ReferenceDataRepository {
  const _NoReferenceDataRepository();

  @override
  Future<ReferenceData?> findById(ReferenceDataId id) async => null;

  @override
  Future<Map<String, String>> labels({
    required String type,
    required String locale,
    bool includeArchived = false,
  }) async => {};

  @override
  Future<List<ReferenceData>> list({
    String? type,
    bool includeArchived = false,
  }) async => const [];

  @override
  Future<void> save(ReferenceData value) async {}

  @override
  Future<void> saveTranslation({
    required ReferenceDataId id,
    required String locale,
    required String label,
  }) async {}
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

final class _NoReconciliationWorkflowRepository
    implements ReconciliationWorkflowRepository {
  const _NoReconciliationWorkflowRepository();

  @override
  Future<void> confirm(
    ReconciliationCandidate candidate,
    ReconciliationLink link,
  ) async {
    throw const RepositoryException(
      RepositoryFailureCode.unavailable,
      'reconciliation workflow unavailable',
    );
  }

  @override
  Future<void> reject(ReconciliationCandidate candidate) async {
    throw const RepositoryException(
      RepositoryFailureCode.unavailable,
      'reconciliation workflow unavailable',
    );
  }
}
