import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

SynchronizeMerchantReviewIssues _merchantReviewSynchronizer(
  TransactionRepository transactions,
  MerchantRepository merchants,
) => SynchronizeMerchantReviewIssues(
  transactions,
  merchants,
  const SystemApplicationClock().now,
);

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
    RecurringPatternDecisionRepository? recurringPatternDecisions,
    PaymentSettlementRepository? paymentSettlements,
    MerchantAliasRepository? merchantAliases,
    MerchantNormalizationPatternRepository? merchantNormalizationPatterns,
    MerchantMatchingConfigurationRepository? merchantMatchingConfiguration,
    TransactionRuleRepository? transactionRules,
    BudgetRepository? budgetRepository,
    FinancialProfileRepository? financialProfileRepository,
    HomeCanonicalTransactionIdsLoader? canonicalTransactionIds,
    Future<void> Function()? ensureAnalysisRules,
    InvalidateAnalysis? analysisInvalidation,
    AnalysisConsistencyGate? consistencyGate,
    Future<void> Function(EvidenceItem evidence)? deleteEvidenceFile,
    Future<void> Function(EvidenceItem evidence)? finalizeDeletedEvidenceFile,
    Future<T> Function<T>(Future<T> Function() action)?
    withEvidenceMutationLock,
  }) : consistencyGate = consistencyGate,
       manageBudgets = budgetRepository == null
           ? null
           : ManageBudgets(budgetRepository),
       listTransactions = ListTransactions(
         transactions,
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       calculateCanonicalBudgetActuals = CalculateCanonicalBudgetActuals(
         AnalysisDatasetBuilder(
           transactions,
           preferences,
           reconciliationLinks,
           candidates: reconciliationCandidates,
           duplicateGroups: duplicateGroups,
           categories: categories,
         ),
         consistencyGate: consistencyGate,
       ),
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
       proposeTransactionClassification = ProposeTransactionClassification(
         transactions,
         merchants,
         historical: transactions is HistoricalClassificationRepository
             ? transactions as HistoricalClassificationRepository
             : null,
       ),
       createTransaction = CreateTransaction(
         transactions,
         const SystemApplicationClock(),
         classifier: ProposeTransactionClassification(
           transactions,
           merchants,
           historical: transactions is HistoricalClassificationRepository
               ? transactions as HistoricalClassificationRepository
               : null,
         ),
         applyRules: transactionRules == null
             ? null
             : ApplyTransactionRules(
                 transactionRules,
                 const SystemApplicationClock(),
               ),
         merchants: merchants,
         consistencyGate: consistencyGate,
       ),
       createReceiptTransaction = CreateReceiptTransaction(
         transactions,
         const SystemApplicationClock(),
         classifier: ProposeTransactionClassification(
           transactions,
           merchants,
           historical: transactions is HistoricalClassificationRepository
               ? transactions as HistoricalClassificationRepository
               : null,
         ),
         applyRules: transactionRules == null
             ? null
             : ApplyTransactionRules(
                 transactionRules,
                 const SystemApplicationClock(),
               ),
         merchants: merchants,
         consistencyGate: consistencyGate,
       ),
       createPaymentTransaction = CreatePaymentTransaction(
         transactions,
         const SystemApplicationClock(),
         merchants: merchants,
         consistencyGate: consistencyGate,
       ),
       importTransaction = ImportTransaction(
         transactions,
         const SystemApplicationClock(),
         classifier: ProposeTransactionClassification(
           transactions,
           merchants,
           historical: transactions is HistoricalClassificationRepository
               ? transactions as HistoricalClassificationRepository
               : null,
         ),
         applyRules: transactionRules == null
             ? null
             : ApplyTransactionRules(
                 transactionRules,
                 const SystemApplicationClock(),
               ),
         merchants: merchants,
         consistencyGate: consistencyGate,
       ),
       getTransaction = GetTransaction(
         transactions,
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       resolveHomePeriod = ResolveHomePeriod(preferences),
       updateTransaction = UpdateTransaction(
         transactions,
         const SystemApplicationClock(),
         preferences: preferences,
         merchants: merchants,
         consistencyGate: consistencyGate,
       ),
       archiveTransaction = ArchiveTransaction(
         transactions,
         const SystemApplicationClock(),
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       restoreTransaction = RestoreTransaction(
         transactions,
         const SystemApplicationClock(),
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       deleteTransactionPermanently = DeleteTransactionPermanently(
         transactions,
         evidence: evidence,
         deleteEvidenceFile: deleteEvidenceFile,
         finalizeDeletedEvidenceFile: finalizeDeletedEvidenceFile,
         withEvidenceMutationLock: withEvidenceMutationLock,
         consistencyGate: consistencyGate,
       ),
       listPaymentSources = ListPaymentSources(paymentSources),
       savePaymentSource = SavePaymentSource(paymentSources),
       archivePaymentSource = ArchivePaymentSource(paymentSources),
       assignPaymentSource = AssignPaymentSource(
         transactions,
         paymentSources,
         const SystemApplicationClock(),
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       listMerchants = ListMerchants(merchants),
       listCategories = ListCategories(categories),
       listTags = ListTags(tags),
       saveMerchant = SaveMerchant(
         merchants,
         synchronize: _merchantReviewSynchronizer(transactions, merchants),
       ),
       saveCategory = SaveCategory(
         categories,
         invalidateAnalysis: analysisInvalidation,
         consistencyGate: consistencyGate,
       ),
       saveTag = SaveTag(tags),
       assignMerchant = AssignMerchant(
         transactions,
         merchants,
         const SystemApplicationClock(),
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       assignCategory = AssignCategory(
         transactions,
         categories,
         const SystemApplicationClock(),
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       addTag = AddTag(
         transactions,
         tags,
         const SystemApplicationClock(),
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       removeTag = RemoveTag(
         transactions,
         const SystemApplicationClock(),
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       listReviewItems = ListReviewItems(
         transactions,
         consistencyGate: consistencyGate,
       ),
       synchronizeMerchantReviewIssues = SynchronizeMerchantReviewIssues(
         transactions,
         merchants,
         const SystemApplicationClock().now,
       ),
       resolveReviewIssue = ResolveReviewIssue(
         transactions,
         const SystemApplicationClock(),
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       dismissReviewIssue = DismissReviewIssue(
         transactions,
         const SystemApplicationClock(),
         preferences: preferences,
         consistencyGate: consistencyGate,
       ),
       listEvidenceForTransaction = ListEvidenceForTransaction(evidence),
       listAllEvidence = ListAllEvidence(evidence),
       getEvidence = GetEvidence(evidence),
       getExtractionForEvidence = GetExtractionForEvidence(
         evidence is ExtractionLookupRepository
             ? evidence as ExtractionLookupRepository
             : const _NoExtractionLookupRepository(),
       ),
       cleanupUnreferencedEvidence = CleanupUnreferencedEvidence(
         evidence,
         deleteEvidenceFile: deleteEvidenceFile,
         finalizeDeletedEvidenceFile: finalizeDeletedEvidenceFile,
         consistencyGate: consistencyGate,
       ),
       removeEvidenceFromTransaction = RemoveEvidenceFromTransaction(
         evidence,
         deleteEvidenceFile: deleteEvidenceFile,
         finalizeDeletedEvidenceFile: finalizeDeletedEvidenceFile,
         withEvidenceMutationLock: withEvidenceMutationLock,
         consistencyGate: consistencyGate,
       ),
       recoverUnreferencedEvidence = RecoverUnreferencedEvidence(
         evidence,
         deleteEvidenceFile: deleteEvidenceFile,
         finalizeDeletedEvidenceFile: finalizeDeletedEvidenceFile,
         consistencyGate: consistencyGate,
       ),
       loadUserPreference = LoadUserPreference(preferences),
       saveUserPreference = SaveUserPreference(
         preferences,
         invalidateAnalysis: analysisInvalidation,
         consistencyGate: consistencyGate,
       ),
       loadFinancialProfile = financialProfileRepository == null
           ? null
           : LoadFinancialProfile(financialProfileRepository),
       saveFinancialProfile = financialProfileRepository == null
           ? null
           : SaveFinancialProfile(financialProfileRepository),
       clearFinancialProfile = financialProfileRepository == null
           ? null
           : ClearFinancialProfile(financialProfileRepository),
       storeAndAttachEvidence = StoreAndAttachEvidence(evidence),
       storeEvidence = StoreEvidence(evidence),
       removeEvidence = RemoveEvidence(evidence),
       saveExtraction = SaveExtraction(evidence),
       listReconciliationCandidates = ListReconciliationCandidates(
         reconciliationCandidates ??
             const _NoReconciliationCandidateRepository(),
         transactions: transactions,
         consistencyGate: consistencyGate,
       ),
       saveReconciliationCandidate = SaveReconciliationCandidate(
         reconciliationCandidates ??
             const _NoReconciliationCandidateRepository(),
         invalidateAnalysis: analysisInvalidation,
         consistencyGate: consistencyGate,
       ),
       refreshReconciliationCandidates = RefreshReconciliationCandidates(
         transactions,
         reconciliationCandidates ??
             const _NoReconciliationCandidateRepository(),
         invalidateAnalysis: analysisInvalidation,
         consistencyGate: consistencyGate,
       ),
       saveReconciliationLink = SaveReconciliationLink(
         reconciliationLinks ?? const _NoReconciliationLinkRepository(),
         candidates:
             reconciliationCandidates ??
             const _NoReconciliationCandidateRepository(),
         invalidateAnalysis: analysisInvalidation,
         consistencyGate: consistencyGate,
       ),
       listReconciliationLinks = ListReconciliationLinks(
         reconciliationLinks ?? const _NoReconciliationLinkRepository(),
         consistencyGate: consistencyGate,
       ),
       confirmReconciliation = ConfirmReconciliation(
         reconciliationWorkflow ?? const _NoReconciliationWorkflowRepository(),
         transactions: transactions,
         invalidateAnalysis: analysisInvalidation,
         consistencyGate: consistencyGate,
       ),
       rejectReconciliation = RejectReconciliation(
         reconciliationWorkflow ?? const _NoReconciliationWorkflowRepository(),
         transactions: transactions,
         invalidateAnalysis: analysisInvalidation,
         consistencyGate: consistencyGate,
       ),
       findReceiptPaymentMatch = FindReceiptPaymentMatch(
         transactions,
         consistencyGate: consistencyGate,
       ),
       duplicateTransactionChecker = DuplicateTransactionChecker(
         transactions,
         consistencyGate: consistencyGate,
       ),
       scanExistingTransactionsForDuplicates = duplicateGroups == null
           ? null
           : ScanExistingTransactionsForDuplicates(
               duplicateGroups,
               const SystemApplicationClock(),
               transactions: transactions,
               invalidateAnalysis: analysisInvalidation,
               consistencyGate: consistencyGate,
             ),
       rebuildDuplicateGroupsAfterRestore = duplicateGroups == null
           ? null
           : RebuildDuplicateGroupsAfterRestore(
               duplicateGroups,
               const SystemApplicationClock(),
               transactions: transactions,
               invalidateAnalysis: analysisInvalidation,
               consistencyGate: consistencyGate,
             ),
       listDuplicateCandidateGroups = duplicateGroups == null
           ? null
           : ListDuplicateCandidateGroups(
               duplicateGroups,
               transactions: ListTransactions(
                 transactions,
                 preferences: preferences,
                 consistencyGate: consistencyGate,
               ),
               statements: statements,
               consistencyGate: consistencyGate,
             ),
       resolveDuplicateCandidateGroup = duplicateGroups == null
           ? null
           : ResolveDuplicateCandidateGroup(
               duplicateGroups,
               const SystemApplicationClock(),
               invalidateAnalysis:
                   analysisInvalidation ??
                   (analysisFindings == null
                       ? null
                       : InvalidateAnalysis(
                           analysisFindings,
                           results: analysisResults,
                           rules: analysisRules,
                           consistencyGate: consistencyGate,
                         )),
               consistencyGate: consistencyGate,
             ),
       repairDuplicateCandidateGroup = duplicateGroups == null
           ? null
           : RepairDuplicateCandidateGroup(
               duplicateGroups,
               const SystemApplicationClock(),
               invalidateAnalysis:
                   analysisInvalidation ??
                   (analysisFindings == null
                       ? null
                       : InvalidateAnalysis(
                           analysisFindings,
                           results: analysisResults,
                           rules: analysisRules,
                           consistencyGate: consistencyGate,
                         )),
               consistencyGate: consistencyGate,
             ),
       evaluateTransactionNormalization = EvaluateTransactionNormalization(
         transactions,
         preferences,
         exchangeRates,
         const SystemApplicationClock(),
         consistencyGate: consistencyGate,
       ),
       confirmUserNormalizedAmount = ConfirmUserNormalizedAmount(
         transactions,
         preferences,
         const SystemApplicationClock(),
         consistencyGate: consistencyGate,
       ),
       installBuiltInRules = analysisRules == null
           ? null
           : InstallBuiltInRules(analysisRules),
       ensureAnalysisRules = ensureAnalysisRules,
       calculateAnalysisOverview = analysisRules == null
           ? null
           : CalculateAnalysisOverview(
               analysisRules,
               AnalysisDatasetBuilder(
                 transactions,
                 preferences,
                 reconciliationLinks,
                 candidates: reconciliationCandidates,
                 duplicateGroups: duplicateGroups,
                 categories: categories,
               ),
               const AnalysisRuleEngine(),
               findings: analysisFindings,
               results: analysisResults,
               consistencyGate: consistencyGate,
             ),
       calculateAnalysisCalendar = analysisRules == null
           ? null
           : CalculateAnalysisCalendar(
               AnalysisDatasetBuilder(
                 transactions,
                 preferences,
                 reconciliationLinks,
                 candidates: reconciliationCandidates,
                 duplicateGroups: duplicateGroups,
                 categories: categories,
               ),
               analysisRules,
               const AnalysisRuleEngine(),
               consistencyGate: consistencyGate,
             ),
       calculateInsights = analysisRules == null
           ? null
           : CalculateInsights(
               CalculateAnalysisOverview(
                 analysisRules,
                 AnalysisDatasetBuilder(
                   transactions,
                   preferences,
                   reconciliationLinks,
                   candidates: reconciliationCandidates,
                   duplicateGroups: duplicateGroups,
                   categories: categories,
                 ),
                 const AnalysisRuleEngine(),
                 findings: analysisFindings,
                 results: analysisResults,
                 consistencyGate: consistencyGate,
               ),
             ),
       detectRecurringPatterns = DetectRecurringPatterns(
         transactions,
         preferences: preferences,
         links: reconciliationLinks,
         candidates: reconciliationCandidates,
         duplicateGroups: duplicateGroups,
         decisions: recurringPatternDecisions,
         consistencyGate: consistencyGate,
       ),
       saveRecurringPatternDecision = recurringPatternDecisions == null
           ? null
           : SaveRecurringPatternDecision(
               recurringPatternDecisions,
               const SystemApplicationClock(),
             ),
       queryTransactionsForFinancialDate = QueryTransactionsForFinancialDate(
         transactions,
         preferences: preferences,
         links: reconciliationLinks,
         candidates: reconciliationCandidates,
         duplicateGroups: duplicateGroups,
         consistencyGate: consistencyGate,
       ),
       statementServices = statements == null || duplicateGroups == null
           ? null
           : StatementServices(
               statements,
               transactions,
               statements as StatementWorkflowRepository,
               const SystemApplicationClock(),
               evidence: evidence,
               merchants: merchants,
               invalidateAnalysis: analysisInvalidation,
               consistencyGate: consistencyGate,
               applyRules: transactionRules == null
                   ? null
                   : ApplyTransactionRules(
                       transactionRules,
                       const SystemApplicationClock(),
                     ),
               duplicateGroups: duplicateGroups,
               duplicateChecker: DuplicateTransactionChecker(
                 transactions,
                 consistencyGate: consistencyGate,
               ),
               classifier: ProposeTransactionClassification(
                 transactions,
                 merchants,
                 historical: transactions is HistoricalClassificationRepository
                     ? transactions as HistoricalClassificationRepository
                     : null,
               ),
             ),
       savePaymentSettlement = paymentSettlements == null
           ? null
           : SavePaymentSettlement(
               paymentSettlements,
               paymentSources,
               const SystemApplicationClock(),
             ),
       listPaymentSettlements = paymentSettlements == null
           ? null
           : ListPaymentSettlements(paymentSettlements),
       getPaymentSettlementDetail = paymentSettlements == null
           ? null
           : GetPaymentSettlementDetail(
               paymentSettlements,
               preferences: preferences,
             ),
       setPaymentSettlementStatus = paymentSettlements == null
           ? null
           : SetPaymentSettlementStatus(
               paymentSettlements,
               const SystemApplicationClock(),
             ),
       deletePaymentSettlement = paymentSettlements == null
           ? null
           : DeletePaymentSettlement(paymentSettlements),
       listMerchantAliases = merchantAliases == null
           ? null
           : ListMerchantAliases(merchantAliases),
       saveMerchantAlias = merchantAliases == null
           ? null
           : SaveMerchantAlias(
               merchantAliases,
               const SystemApplicationClock(),
               synchronize: _merchantReviewSynchronizer(
                 transactions,
                 merchants,
               ),
             ),
       deleteMerchantAlias = merchantAliases == null
           ? null
           : DeleteMerchantAlias(
               merchantAliases,
               synchronize: _merchantReviewSynchronizer(
                 transactions,
                 merchants,
               ),
             ),
       listMerchantNormalizationPatterns = merchantNormalizationPatterns == null
           ? null
           : ListMerchantNormalizationPatterns(merchantNormalizationPatterns),
       saveMerchantNormalizationPattern = merchantNormalizationPatterns == null
           ? null
           : SaveMerchantNormalizationPattern(
               merchantNormalizationPatterns,
               const SystemApplicationClock(),
               synchronize: _merchantReviewSynchronizer(
                 transactions,
                 merchants,
               ),
             ),
       deleteMerchantNormalizationPattern =
           merchantNormalizationPatterns == null
           ? null
           : DeleteMerchantNormalizationPattern(
               merchantNormalizationPatterns,
               synchronize: _merchantReviewSynchronizer(
                 transactions,
                 merchants,
               ),
             ),
       updateMerchantMatchingConfiguration =
           merchantMatchingConfiguration == null
           ? null
           : UpdateMerchantMatchingConfiguration(
               merchantMatchingConfiguration,
               const SystemApplicationClock(),
               synchronize: _merchantReviewSynchronizer(
                 transactions,
                 merchants,
               ),
             ),
       listTransactionRules = transactionRules == null
           ? null
           : ListTransactionRules(transactionRules),
       previewTransactionRule = transactionRules == null
           ? null
           : PreviewTransactionRule(transactions),
       saveTransactionRule = transactionRules == null
           ? null
           : SaveTransactionRule(transactionRules, categories),
       setTransactionRuleEnabled = transactionRules == null
           ? null
           : SetTransactionRuleEnabled(
               transactionRules,
               const SystemApplicationClock(),
             ),
       deleteTransactionRule = transactionRules == null
           ? null
           : DeleteTransactionRule(transactionRules),
       updateAnalysisFindingLifecycle = analysisFindings == null
           ? null
           : UpdateFindingLifecycle(analysisFindings),
       invalidateAnalysis = analysisFindings == null
           ? null
           : InvalidateAnalysis(
               analysisFindings,
               results: analysisResults,
               rules: analysisRules,
               consistencyGate: consistencyGate,
             ) {
    calculateMonthlySpendingTrend = calculateAnalysisOverview == null
        ? null
        : CalculateMonthlySpendingTrend(calculateAnalysisOverview!);
    loadHomeOverview = GetHomeOverview(
      resolveHomePeriod: resolveHomePeriod,
      calculateAnalysis: calculateAnalysisOverview,
      calculateInsights: calculateInsights,
      listTransactions: listTransactions,
      listReviewItems: listReviewItems,
      listDuplicateCandidateGroups: listDuplicateCandidateGroups,
      merchants: merchants,
      canonicalTransactionIds: canonicalTransactionIds,
      consistencyGate: consistencyGate,
      ensureAnalysisRules: ensureAnalysisRules,
    );
  }

  final ManageBudgets? manageBudgets;
  final CalculateCanonicalBudgetActuals calculateCanonicalBudgetActuals;
  final ListTransactions listTransactions;
  final SeedInitialMasterData seedInitialMasterData;
  final LoadMasterTranslations loadMasterTranslations;
  final LoadReferenceData loadReferenceData;
  final CreateTransaction createTransaction;
  final ProposeTransactionClassification proposeTransactionClassification;
  final CreateReceiptTransaction createReceiptTransaction;
  final CreatePaymentTransaction createPaymentTransaction;
  final ImportTransaction importTransaction;
  final GetTransaction getTransaction;
  final ResolveHomePeriod resolveHomePeriod;
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
  final SynchronizeMerchantReviewIssues synchronizeMerchantReviewIssues;
  final ResolveReviewIssue resolveReviewIssue;
  final DismissReviewIssue dismissReviewIssue;
  final ListEvidenceForTransaction listEvidenceForTransaction;
  final ListAllEvidence listAllEvidence;
  final GetEvidence getEvidence;
  final GetExtractionForEvidence getExtractionForEvidence;
  final CleanupUnreferencedEvidence cleanupUnreferencedEvidence;
  final RemoveEvidenceFromTransaction removeEvidenceFromTransaction;
  final RecoverUnreferencedEvidence recoverUnreferencedEvidence;
  final LoadUserPreference loadUserPreference;
  final SaveUserPreference saveUserPreference;
  final LoadFinancialProfile? loadFinancialProfile;
  final SaveFinancialProfile? saveFinancialProfile;
  final ClearFinancialProfile? clearFinancialProfile;
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
  final RebuildDuplicateGroupsAfterRestore? rebuildDuplicateGroupsAfterRestore;
  final ListDuplicateCandidateGroups? listDuplicateCandidateGroups;
  final ResolveDuplicateCandidateGroup? resolveDuplicateCandidateGroup;
  final RepairDuplicateCandidateGroup? repairDuplicateCandidateGroup;
  final InstallBuiltInRules? installBuiltInRules;
  final Future<void> Function()? ensureAnalysisRules;
  final CalculateAnalysisOverview? calculateAnalysisOverview;
  late final CalculateMonthlySpendingTrend? calculateMonthlySpendingTrend;
  final CalculateAnalysisCalendar? calculateAnalysisCalendar;
  final CalculateInsights? calculateInsights;
  final DetectRecurringPatterns detectRecurringPatterns;
  final SaveRecurringPatternDecision? saveRecurringPatternDecision;
  late final CalculatePeriodicFinancialReport?
  calculatePeriodicFinancialReport = calculateAnalysisOverview == null
      ? null
      : CalculatePeriodicFinancialReport(
          calculateAnalysisOverview!,
          detectRecurringPatterns,
        );
  late final GetHomeOverview loadHomeOverview;
  final QueryTransactionsForFinancialDate queryTransactionsForFinancialDate;
  final UpdateFindingLifecycle? updateAnalysisFindingLifecycle;
  final InvalidateAnalysis? invalidateAnalysis;
  final AnalysisConsistencyGate? consistencyGate;
  final StatementServices? statementServices;
  final SavePaymentSettlement? savePaymentSettlement;
  final ListPaymentSettlements? listPaymentSettlements;
  final GetPaymentSettlementDetail? getPaymentSettlementDetail;
  final SetPaymentSettlementStatus? setPaymentSettlementStatus;
  final DeletePaymentSettlement? deletePaymentSettlement;
  final ListMerchantAliases? listMerchantAliases;
  final SaveMerchantAlias? saveMerchantAlias;
  final DeleteMerchantAlias? deleteMerchantAlias;
  final ListMerchantNormalizationPatterns? listMerchantNormalizationPatterns;
  final SaveMerchantNormalizationPattern? saveMerchantNormalizationPattern;
  final DeleteMerchantNormalizationPattern? deleteMerchantNormalizationPattern;
  final UpdateMerchantMatchingConfiguration?
  updateMerchantMatchingConfiguration;
  final ListTransactionRules? listTransactionRules;
  final PreviewTransactionRule? previewTransactionRule;
  final SaveTransactionRule? saveTransactionRule;
  final SetTransactionRuleEnabled? setTransactionRuleEnabled;
  final DeleteTransactionRule? deleteTransactionRule;
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
