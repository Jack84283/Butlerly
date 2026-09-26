import '../analysis/analysis.dart';
import '../entities/account.dart';
import '../entities/attachment_link.dart';
import '../entities/category.dart';
import '../entities/duplicate_candidate_group.dart';
import '../entities/evidence_item.dart';
import '../entities/exchange_rate.dart';
import '../entities/extraction.dart';
import '../entities/master_translation.dart';
import '../entities/merchant.dart';
import '../entities/merchant_matching.dart';
import '../entities/payment_settlement.dart';
import '../entities/reconciliation_candidate.dart';
import '../entities/reconciliation_link.dart';
import '../entities/reference_data.dart';
import '../entities/statement.dart';
import '../entities/suggestion.dart';
import '../entities/tag.dart';
import '../entities/transaction.dart';
import '../entities/transaction_rule.dart';
import '../entities/user_preference.dart';
import '../value_objects/currency_code.dart';
import '../value_objects/domain_id.dart';

abstract interface class TransactionRepository {
  Future<void> save(Transaction transaction);
  Future<Transaction?> findById(TransactionId id);
  Future<List<Transaction>> listAll();
  Future<List<Transaction>> query(TransactionRepositoryQuery query);

  Future<void> removePermanently(TransactionId id);
}

/// Optional optimized access path for the Needs Review workflow.
abstract interface class ReviewTransactionRepository {
  Future<List<Transaction>> queryTransactionsForReview();
}

final class DuplicateTransactionGroupMatch {
  const DuplicateTransactionGroupMatch({
    required this.duplicateKey,
    required this.transactionIds,
  });

  final DuplicateTransactionKey duplicateKey;
  final List<TransactionId> transactionIds;
}

abstract interface class DuplicateCandidateGroupRepository {
  Future<List<DuplicateCandidateGroup>> list({
    DuplicateCandidateGroupStatus? status,
  });

  Future<List<DuplicateTransactionGroupMatch>> findActiveDuplicateGroups();
  Future<List<TransactionId>> findActiveTransactionIdsForKey(
    DuplicateTransactionKey key,
  );
  Future<void> save(DuplicateCandidateGroup group);
  Future<void> remove(String id);
}

abstract interface class ExchangeRateRepository {
  Future<void> save(ExchangeRate rate);
  Future<ExchangeRate?> findApplicable({
    required CurrencyCode fromCurrency,
    required CurrencyCode toCurrency,
    required DateTime financialDate,
  });
}

abstract interface class AnalysisRuleRepository {
  Future<void> install(
    AnalysisRuleDefinition definition, {
    required String sourceType,
    required String canonicalDefinition,
  });
  Future<List<AnalysisRuleDefinition>> listDefinitions();
  Future<void> activate(
    RuleIdentity id,
    RuleVersion version,
    bool enabled,
    DateTime at,
  );
  Future<List<AnalysisRuleDefinition>> listActive();
  Future<AnalysisRuleActivation?> existingActivation(RuleIdentity id);
}

final class AnalysisRuleActivation {
  const AnalysisRuleActivation({required this.version, required this.enabled});
  final RuleVersion version;
  final bool enabled;
}

abstract interface class AnalysisFindingRepository {
  Future<void> save(AnalysisFinding finding);
  Future<List<AnalysisFinding>> list({FindingLifecycle? lifecycle});
  Future<void> updateLifecycle(
    String id,
    FindingLifecycle lifecycle,
    DateTime at,
  );
}

abstract interface class AnalysisRuleResultRepository {
  Future<List<AnalysisRuleResult>> findAll({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    int? sourceRevision,
  });

  Future<AnalysisRuleResult?> find({
    required AnalysisRuleDefinition rule,
    required AnalysisContext context,
    String? dimension,
    int? sourceRevision,
  });

  Future<void> save(AnalysisRuleResult result);

  Future<void> markStale({
    String? periodStart,
    String? periodEnd,
    Set<String>? ruleIds,
  });
}

final class TransactionRepositoryQuery {
  const TransactionRepositoryQuery({
    this.text,
    this.transactionIds,
    this.from,
    this.to,
    this.categoryId,
    this.paymentSourceId,
    this.currency,
    this.direction,
    this.status,
    this.needsReview,
    this.uncategorized = false,
  });

  final String? text;
  final List<TransactionId>? transactionIds;
  final DateTime? from;
  final DateTime? to;
  final CategoryId? categoryId;
  final PaymentSourceId? paymentSourceId;
  final String? currency;
  final TransactionDirection? direction;
  final TransactionStatus? status;
  final bool? needsReview;
  final bool uncategorized;
}

abstract interface class PaymentSettlementRepository {
  Future<void> save(PaymentSettlement settlement);
  Future<PaymentSettlement?> findById(PaymentSettlementId id);
  Future<List<PaymentSettlement>> listAll();
  Future<List<Transaction>> listTransactions(PaymentSettlement settlement);
  Future<void> remove(PaymentSettlementId id);
}

abstract interface class PaymentSourceRepository {
  Future<void> save(PaymentSource paymentSource);
  Future<PaymentSource?> findById(PaymentSourceId id);
  Future<List<PaymentSource>> listAll();
}

abstract interface class MerchantRepository {
  Future<void> save(Merchant merchant);
  Future<Merchant?> findById(MerchantId id);
  Future<List<Merchant>> listAll();
}

abstract interface class MerchantAliasRepository {
  Future<void> save(MerchantAlias alias);
  Future<MerchantAlias?> findById(MerchantAliasId id);
  Future<List<MerchantAlias>> listForMerchant(MerchantId merchantId);
  Future<void> remove(MerchantAliasId id);
}

abstract interface class MerchantNormalizationPatternRepository {
  Future<void> save(MerchantNormalizationPattern pattern);
  Future<MerchantNormalizationPattern?> findById(
    MerchantNormalizationPatternId id,
  );
  Future<List<MerchantNormalizationPattern>> listForMerchant(
    MerchantId merchantId,
  );
  Future<void> remove(MerchantNormalizationPatternId id);
}

/// Persists a merchant and its complete matching configuration as one unit.
///
/// Implementations should use one database transaction when the underlying
/// storage supports it, so an edit cannot leave the merchant, aliases, and
/// normalization patterns out of sync.
abstract interface class MerchantMatchingConfigurationRepository {
  Future<void> saveConfiguration({
    required Merchant merchant,
    required List<MerchantAlias> aliases,
    required List<MerchantNormalizationPattern> patterns,
  });
}

abstract interface class TransactionRuleRepository {
  Future<void> save(TransactionRule rule);
  Future<List<TransactionRule>> listAll();
  Future<TransactionRule?> findById(TransactionRuleId id);
  Future<void> remove(TransactionRuleId id);
}

/// Repository-owned, already-filtered candidates for local classification.
abstract interface class HistoricalClassificationRepository {
  Future<List<Transaction>> findClassificationCandidates({
    MerchantId? merchantId,
    String? normalizedDescription,
    TransactionId? excludeTransactionId,
  });
}

abstract interface class CategoryRepository {
  Future<void> save(Category category);
  Future<Category?> findById(CategoryId id);
  Future<List<Category>> listAll();
}

abstract interface class TagRepository {
  Future<void> save(Tag tag);
  Future<Tag?> findById(TagId id);
  Future<List<Tag>> listAll();
}

abstract interface class MasterTranslationRepository {
  Future<void> saveAll(List<MasterTranslation> translations);
  Future<Map<String, String>> labels({
    required String masterType,
    required String locale,
  });
}

abstract interface class ReferenceDataRepository {
  Future<void> save(ReferenceData value);
  Future<ReferenceData?> findById(ReferenceDataId id);
  Future<List<ReferenceData>> list({
    String? type,
    bool includeArchived = false,
  });
  Future<Map<String, String>> labels({
    required String type,
    required String locale,
    bool includeArchived = false,
  });
  Future<void> saveTranslation({
    required ReferenceDataId id,
    required String locale,
    required String label,
  });
}

abstract interface class EvidenceRepository {
  Future<void> save(EvidenceItem evidence);
  Future<void> saveExtraction(Extraction extraction);
  Future<void> link(AttachmentLink link);
  Future<EvidenceItem?> findById(EvidenceId id);
  Future<List<EvidenceItem>> listForTransaction(TransactionId id);
  Future<void> remove(EvidenceId id);
}

abstract interface class StatementRepository {
  Future<void> saveStatement(FinancialStatement statement);
  Future<void> saveRows(List<StatementRow> rows);
  Future<void> saveStatementWithRows(
    FinancialStatement statement,
    List<StatementRow> rows,
  );
  Future<FinancialStatement?> findStatement(String id);
  Future<List<FinancialStatement>> listStatements({
    bool includeArchived = false,
  });
  Future<List<StatementRow>> listRows(String statementId);
  Future<void> assignPaymentSource(
    String statementId,
    String paymentSourceId,
    DateTime updatedAt,
  );
  Future<void> updateRow(StatementRow row);
  Future<bool> canDeleteStatement(String id);
  Future<void> removeStatement(String id);
}

abstract interface class StatementWorkflowRepository {
  Future<void> saveRowTransactions(List<StatementRowTransaction> values);
  Future<void> saveRowTransaction(StatementRow row, Transaction transaction);
  Future<void> linkRow(StatementRow row);
}

final class StatementRowTransaction {
  const StatementRowTransaction({required this.row, required this.transaction});

  final StatementRow row;
  final Transaction transaction;
}

abstract interface class ExtractionLookupRepository {
  Future<Extraction?> findExtractionForEvidence(EvidenceId id);
}

abstract interface class SuggestionRepository {
  Future<void> save(Suggestion suggestion);
  Future<Suggestion?> findById(SuggestionId id);
  Future<List<Suggestion>> listForTransaction(TransactionId id);
}

abstract interface class ReconciliationCandidateRepository {
  Future<void> save(ReconciliationCandidate candidate);
  Future<ReconciliationCandidate?> findById(String id);
  Future<List<ReconciliationCandidate>> listAll();
}

abstract interface class ReconciliationLinkRepository {
  Future<void> save(ReconciliationLink link);
  Future<List<ReconciliationLink>> listAll();
}

abstract interface class ReconciliationWorkflowRepository {
  Future<void> confirm(
    ReconciliationCandidate candidate,
    ReconciliationLink link,
  );

  Future<void> reject(ReconciliationCandidate candidate);
}

abstract interface class UserPreferenceRepository {
  Future<UserPreference?> load();
  Future<void> save(UserPreference preference);
}
