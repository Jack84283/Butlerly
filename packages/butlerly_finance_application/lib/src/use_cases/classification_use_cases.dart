import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../result/application_result.dart';

enum ClassificationSource { history, merchantDefault, unresolved }

final class ClassificationProposal {
  const ClassificationProposal({
    this.merchantId,
    required this.categoryId,
    required this.subcategoryId,
    required this.source,
    this.confidence,
    this.reason,
  });

  final MerchantId? merchantId;
  final CategoryId? categoryId;
  final CategoryId? subcategoryId;
  final ClassificationSource source;
  final double? confidence;
  final String? reason;
}

/// Resolves a deterministic proposal without mutating the transaction.
final class ProposeTransactionClassification {
  const ProposeTransactionClassification(this.transactions, this.merchants);

  final TransactionRepository transactions;
  final MerchantRepository merchants;

  Future<ApplicationResult<ClassificationProposal>> call({
    MerchantId? merchantId,
    String? description,
    TransactionId? excludeTransactionId,
  }) => runApplication('propose transaction classification', () async {
    final allMerchants = await merchants.listAll();
    final merchant = merchantId == null
        ? _resolveMerchant(allMerchants, description)
        : allMerchants.where((value) => value.id == merchantId).firstOrNull;
    final history = await transactions.listAll();
    final candidates = history
        .where((value) {
          if (value.id == excludeTransactionId ||
              value.status != TransactionStatus.active ||
              value.categoryId == null ||
              value.reviewState != TransactionReviewState.clear) {
            return false;
          }
          if (merchant != null && value.merchantId == merchant.id) return true;
          final query = normalizeMerchantName(description ?? '');
          return query.isNotEmpty &&
              normalizeMerchantName(
                    value.description ?? value.rawCounterparty ?? '',
                  ) ==
                  query;
        })
        .toList(growable: false);
    final classification = _consistentClassification(candidates);
    if (classification != null) {
      return ClassificationProposal(
        merchantId: merchant?.id,
        categoryId: classification.$1,
        subcategoryId: null,
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
      final key = value.categoryId!.value;
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
    return (CategoryId(winner.key), null);
  }
}
