import 'dart:collection';

import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';
import 'transaction.dart';

final class TransactionRule {
  TransactionRule({
    required this.id,
    required String name,
    this.description,
    this.enabled = true,
    this.priority = 0,
    this.merchantId,
    this.categoryId,
    this.paymentSourceId,
    this.tagId,
    String? descriptionContains,
    String? rawCounterpartyContains,
    this.assignMerchantId,
    this.assignCategoryId,
    this.assignSubcategoryId,
    this.assignPaymentSourceId,
    this.assignTagId,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : name = _required(name, 'name'),
       descriptionContains = _optionalText(descriptionContains),
       rawCounterpartyContains = _optionalText(rawCounterpartyContains),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (!hasCondition) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'condition',
        message: 'A rule requires at least one matching condition.',
      );
    }
    if (!hasAction) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'action',
        message: 'A rule requires at least one assignment action.',
      );
    }
  }

  final TransactionRuleId id;
  final String name;
  final String? description;
  final bool enabled;
  final int priority;
  final MerchantId? merchantId;
  final CategoryId? categoryId;
  final PaymentSourceId? paymentSourceId;
  final TagId? tagId;
  final String? descriptionContains;
  final String? rawCounterpartyContains;
  final MerchantId? assignMerchantId;
  final CategoryId? assignCategoryId;
  final CategoryId? assignSubcategoryId;
  final PaymentSourceId? assignPaymentSourceId;
  final TagId? assignTagId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasCondition =>
      merchantId != null ||
      categoryId != null ||
      paymentSourceId != null ||
      tagId != null ||
      descriptionContains != null ||
      rawCounterpartyContains != null;

  bool get hasAction =>
      assignMerchantId != null ||
      assignCategoryId != null ||
      assignSubcategoryId != null ||
      assignPaymentSourceId != null ||
      assignTagId != null;

  bool matches(Transaction transaction) {
    if (!enabled ||
        (merchantId != null && transaction.merchantId != merchantId) ||
        (categoryId != null && transaction.categoryId != categoryId) ||
        (paymentSourceId != null &&
            transaction.paymentSourceId != paymentSourceId) ||
        (tagId != null && !transaction.tagIds.contains(tagId)) ||
        !_contains(transaction.description, descriptionContains) ||
        !_contains(transaction.rawCounterparty, rawCounterpartyContains)) {
      return false;
    }
    return true;
  }

  Transaction apply(Transaction transaction, DateTime at) {
    var result = transaction;
    if (assignMerchantId != null) {
      result = result.assignMerchant(assignMerchantId, at);
    }
    if (assignCategoryId != null) {
      result = result.assignCategory(assignCategoryId, at);
    }
    if (assignSubcategoryId != null) {
      result = result.assignSubcategory(assignSubcategoryId, at);
    }
    if (assignPaymentSourceId != null) {
      result = result.assignPaymentSource(assignPaymentSourceId, at);
    }
    final tagId = assignTagId;
    if (tagId != null) {
      result = result.addTag(tagId, at);
    }
    return result;
  }

  TransactionRule enable(DateTime at) => _copy(enabled: true, updatedAt: at);

  TransactionRule disable(DateTime at) => _copy(enabled: false, updatedAt: at);

  TransactionRule _copy({required bool enabled, required DateTime updatedAt}) =>
      TransactionRule(
        id: id,
        name: name,
        description: description,
        enabled: enabled,
        priority: priority,
        merchantId: merchantId,
        categoryId: categoryId,
        paymentSourceId: paymentSourceId,
        tagId: tagId,
        descriptionContains: descriptionContains,
        rawCounterpartyContains: rawCounterpartyContains,
        assignMerchantId: assignMerchantId,
        assignCategoryId: assignCategoryId,
        assignSubcategoryId: assignSubcategoryId,
        assignPaymentSourceId: assignPaymentSourceId,
        assignTagId: assignTagId,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  static String _required(String value, String field) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: field,
        message: '$field is required.',
      );
    }
    return normalized;
  }

  static String? _optionalText(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static bool _contains(String? value, String? expected) =>
      expected == null ||
      (value?.toLowerCase().contains(expected.toLowerCase()) ?? false);
}

UnmodifiableListView<TransactionRule> immutableRules(
  Iterable<TransactionRule> values,
) => UnmodifiableListView(List.of(values));
