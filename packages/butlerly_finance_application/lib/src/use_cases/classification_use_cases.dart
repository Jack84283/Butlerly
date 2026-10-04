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
  const ProposeTransactionClassification(
    this.transactions,
    this.merchants, {
    this.historical,
  });

  final TransactionRepository transactions;
  final MerchantRepository merchants;
  final HistoricalClassificationRepository? historical;

  Future<ApplicationResult<ClassificationProposal>> call({
    MerchantId? merchantId,
    String? description,
    TransactionId? excludeTransactionId,
  }) => runApplication('propose transaction classification', () async {
    final allMerchants = await merchants.listAll();
    final merchant = merchantId == null
        ? resolveMerchantFromEvidence(allMerchants, description)
        : allMerchants.where((value) => value.id == merchantId).firstOrNull;
    final normalizedDescription = normalizeMerchantName(description ?? '');
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
    final classification = consistentClassification(candidates);
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
}

/// Resolves a merchant only through Butlerly's deterministic canonical,
/// alias, and normalization-pattern matching rules.
Merchant? resolveMerchantFromEvidence(Iterable<Merchant> values, String? text) {
  final normalized = normalizeMerchantName(text ?? '');
  if (normalized.isEmpty) return null;
  final matches = <_MerchantMatch>[];
  for (final merchant in values.where(
    (value) => value.status == MerchantStatus.active,
  )) {
    final evidence = <_MerchantMatch>[];
    if (normalized == merchant.normalizedName) {
      evidence.add(
        _MerchantMatch(
          merchant: merchant,
          evidenceLength: merchant.normalizedName.length,
          kind: _MerchantMatchKind.exactCanonical,
        ),
      );
    } else if (normalized.startsWith('${merchant.normalizedName} ')) {
      evidence.add(
        _MerchantMatch(
          merchant: merchant,
          evidenceLength: merchant.normalizedName.length,
          kind: _MerchantMatchKind.canonicalPrefix,
        ),
      );
    }
    for (final alias in merchant.aliases.where(
      (value) => value.status == MerchantMatchingStatus.active,
    )) {
      if (normalized == alias.normalizedAlias) {
        evidence.add(
          _MerchantMatch(
            merchant: merchant,
            evidenceLength: alias.normalizedAlias.length,
            kind: _MerchantMatchKind.exactAlias,
          ),
        );
      } else if (normalized.startsWith('${alias.normalizedAlias} ')) {
        evidence.add(
          _MerchantMatch(
            merchant: merchant,
            evidenceLength: alias.normalizedAlias.length,
            kind: _MerchantMatchKind.aliasPrefix,
          ),
        );
      }
    }
    for (final pattern in merchant.normalizationPatterns.where(
      (value) => value.status == MerchantMatchingStatus.active,
    )) {
      if (normalized.contains(pattern.normalizedPattern)) {
        evidence.add(
          _MerchantMatch(
            merchant: merchant,
            evidenceLength: pattern.normalizedPattern.length,
            kind: _MerchantMatchKind.normalizationPattern,
          ),
        );
      }
    }
    if (evidence.isNotEmpty) {
      evidence.sort(_MerchantMatch.compare);
      matches.add(evidence.first);
    }
  }
  if (matches.isEmpty) return null;
  matches.sort(_MerchantMatch.compare);
  return matches.first.merchant;
}

(CategoryId, CategoryId?)? consistentClassification(List<Transaction> values) {
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

/// A match is ranked by the evidence that matched the source text, not by the
/// merchant's canonical name. Longer evidence is more specific; the kind rank
/// only resolves equal-length matches, and the merchant ID makes ties stable.
enum _MerchantMatchKind {
  exactCanonical(5),
  exactAlias(4),
  canonicalPrefix(3),
  aliasPrefix(2),
  normalizationPattern(1);

  const _MerchantMatchKind(this.rank);
  final int rank;
}

final class _MerchantMatch {
  const _MerchantMatch({
    required this.merchant,
    required this.evidenceLength,
    required this.kind,
  });

  final Merchant merchant;
  final int evidenceLength;
  final _MerchantMatchKind kind;

  static int compare(_MerchantMatch left, _MerchantMatch right) {
    final evidence = right.evidenceLength.compareTo(left.evidenceLength);
    if (evidence != 0) return evidence;
    final kind = right.kind.rank.compareTo(left.kind.rank);
    if (kind != 0) return kind;
    return left.merchant.id.value.compareTo(right.merchant.id.value);
  }
}
