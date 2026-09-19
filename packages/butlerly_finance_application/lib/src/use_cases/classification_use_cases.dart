import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

enum ClassificationSource { rule, history, merchantDefault, unresolved }

final class ClassificationProposal {
  const ClassificationProposal({
    this.merchantId,
    required this.categoryId,
    required this.subcategoryId,
    required this.source,
    this.confidence,
    this.reason,
    this.tagIds = const [],
    this.ruleId,
  });

  final MerchantId? merchantId;
  final CategoryId? categoryId;
  final CategoryId? subcategoryId;
  final ClassificationSource source;
  final double? confidence;
  final String? reason;
  final List<TagId> tagIds;
  final ClassificationRuleId? ruleId;
}

/// Resolves a deterministic proposal without mutating the transaction.
final class ProposeTransactionClassification {
  const ProposeTransactionClassification(
    this.transactions,
    this.merchants, {
    this.historical,
    this.rules,
  });

  final TransactionRepository transactions;
  final MerchantRepository merchants;
  final HistoricalClassificationRepository? historical;
  final ClassificationRuleRepository? rules;

  Future<ApplicationResult<ClassificationProposal>> call({
    MerchantId? merchantId,
    String? description,
    TransactionId? excludeTransactionId,
  }) => runApplication('propose transaction classification', () async {
    final allMerchants = await merchants.listAll();
    final merchant = merchantId == null
        ? _resolveMerchant(allMerchants, description)
        : allMerchants.where((value) => value.id == merchantId).firstOrNull;
    final normalizedDescription = normalizeMerchantName(description ?? '');
    final configuredRules = rules == null
        ? const <ClassificationRule>[]
        : await rules!.listAll();
    final matches = configuredRules
        .where((rule) => rule.matches(description ?? ''))
        .toList(growable: false)
      ..sort((left, right) {
        final mode = left.matchMode == right.matchMode
            ? 0
            : left.matchMode == ClassificationRuleMatchMode.exact
            ? -1
            : 1;
        if (mode != 0) return mode;
        final pattern = right.pattern.length.compareTo(left.pattern.length);
        return pattern != 0 ? pattern : left.id.value.compareTo(right.id.value);
      });
    if (matches.isNotEmpty) {
      final rule = matches.first;
      return ClassificationProposal(
        merchantId: rule.merchantId ?? merchant?.id,
        categoryId: rule.categoryId,
        subcategoryId: rule.subcategoryId,
        tagIds: rule.tagIds,
        source: ClassificationSource.rule,
        confidence: 1,
        reason: 'matched user-approved classification rule',
        ruleId: rule.id,
      );
    }
    final candidates = historical == null
        ? (await transactions.listAll())
              .where((value) {
                if (value.id == excludeTransactionId ||
                    value.status != TransactionStatus.active ||
                    value.categoryId == null ||
                    value.reviewState != TransactionReviewState.clear) {
                  return false;
                }
                if (merchant != null && value.merchantId == merchant.id) {
                  return true;
                }
                return normalizedDescription.isNotEmpty &&
                    normalizeMerchantName(
                          value.description ?? value.rawCounterparty ?? '',
                        ) ==
                        normalizedDescription;
              })
              .toList(growable: false)
        : await historical!.findClassificationCandidates(
            merchantId: merchant?.id,
            normalizedDescription: normalizedDescription.isEmpty
                ? null
                : normalizedDescription,
            excludeTransactionId: excludeTransactionId,
          );
    final classification = _consistentClassification(candidates);
    if (classification != null) {
      return ClassificationProposal(
        merchantId: merchant?.id,
        categoryId: classification.$1,
        subcategoryId: classification.$2,
        source: ClassificationSource.history,
        confidence: candidates.length >= 3 ? 1 : .75,
        reason: 'matched ${candidates.length} confirmed transaction(s)',
      );
    }
    if (merchant?.defaultCategoryId != null) {
      return ClassificationProposal(
        merchantId: merchant?.id,
        categoryId: merchant!.defaultCategoryId,
        subcategoryId: merchant.defaultSubcategoryId,
        source: ClassificationSource.merchantDefault,
        confidence: .5,
        reason: 'built-in merchant default',
      );
    }
    return const ClassificationProposal(
      categoryId: null,
      subcategoryId: null,
      source: ClassificationSource.unresolved,
      reason: 'no confirmed history or merchant default matched',
    );
  });

  static Merchant? _resolveMerchant(List<Merchant> values, String? text) {
    final normalized = normalizeMerchantName(text ?? '');
    if (normalized.isEmpty) return null;
    return values
        .where((value) => value.status == MerchantStatus.active)
        .where(
          (value) =>
              normalized == value.normalizedName ||
              normalized.startsWith('${value.normalizedName} '),
        )
        .fold<Merchant?>(
          null,
          (best, value) =>
              best == null ||
                  value.normalizedName.length > best.normalizedName.length
              ? value
              : best,
        );
  }

  static (CategoryId, CategoryId?)? _consistentClassification(
    List<Transaction> values,
  ) {
    if (values.isEmpty) return null;
    final counts = <String, int>{};
    for (final value in values) {
      final key =
          '${value.categoryId!.value}\u0000${value.subcategoryId?.value ?? ''}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort(
        (a, b) => b.value == a.value
            ? a.key.compareTo(b.key)
            : b.value.compareTo(a.value),
      );
    final winner = sorted.first;
    if (sorted.length > 1 && winner.value == sorted[1].value) return null;
    final parts = winner.key.split('\u0000');
    return (
      CategoryId(parts.first),
      parts.length == 1 || parts[1].isEmpty ? null : CategoryId(parts[1]),
    );
  }
}
