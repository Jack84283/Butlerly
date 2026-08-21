import 'dart:collection';

import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';
import '../value_objects/money.dart';
import '../value_objects/transaction_timing.dart';
import 'exchange_rate.dart';
import 'provenance.dart';
import 'review_issue.dart';

enum TransactionDirection { expense, income, transfer, refund, adjustment }

enum TransactionSourceType { manual, import, evidenceCapture, integration }

enum TransactionStatus { active, archived }

enum TransactionReviewState { clear, needsReview }

final class Transaction {
  Transaction({
    required this.id,
    required this.timing,
    required this.money,
    required this.direction,
    required this.sourceType,
    required List<Provenance> provenance,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.transactionDate,
    this.timeZoneId,
    this.status = TransactionStatus.active,
    this.description,
    this.rawCounterparty,
    this.sourceLanguage,
    this.notes,
    this.externalReference,
    this.paymentSourceId,
    this.merchantId,
    this.categoryId,
    List<TagId> tagIds = const [],
    List<ReviewIssue> reviewIssues = const [],
    List<NormalizedMoney> normalizedMoney = const [],
  }) : provenance = UnmodifiableListView(List.of(provenance)),
       tagIds = UnmodifiableListView(List.of(tagIds)),
       reviewIssues = UnmodifiableListView(List.of(reviewIssues)),
       normalizedMoney = UnmodifiableListView(List.of(normalizedMoney)),
       createdAt = createdAt.toUtc(),
       updatedAt = updatedAt.toUtc() {
    if (provenance.isEmpty) {
      invalid(
        code: DomainErrorCode.missingProvenance,
        field: 'provenance',
        message: 'A transaction requires at least one origin record.',
      );
    }
    if (this.updatedAt.isBefore(this.createdAt)) {
      invalid(
        code: DomainErrorCode.invalidTimestamp,
        field: 'updatedAt',
        message: 'A transaction cannot be updated before it is created.',
      );
    }
    for (final issue in reviewIssues) {
      if (issue.transactionId != id) {
        invalid(
          code: DomainErrorCode.relationshipMismatch,
          field: 'reviewIssues',
          message: 'Review issues must belong to their transaction.',
        );
      }
    }
    for (final normalized in normalizedMoney) {
      if (normalized.original != money) {
        invalid(
          code: DomainErrorCode.relationshipMismatch,
          field: 'normalizedMoney',
          message: 'Derived money must preserve the canonical original money.',
        );
      }
    }
  }

  final TransactionId id;
  final TransactionTiming timing;
  final Money money;
  final TransactionDirection direction;
  final TransactionSourceType sourceType;
  final TransactionStatus status;
  final String? description;
  final String? rawCounterparty;
  final String? sourceLanguage;
  final String? notes;

  /// Source-provided statement/notification identity, such as a bank
  /// transaction ID or a masked card/account reference.
  final String? externalReference;
  final PaymentSourceId? paymentSourceId;
  final MerchantId? merchantId;
  final CategoryId? categoryId;
  final List<TagId> tagIds;
  final List<Provenance> provenance;
  final List<ReviewIssue> reviewIssues;
  final List<NormalizedMoney> normalizedMoney;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// ISO-8601 financial calendar date, independent of device timezone.
  final String? transactionDate;

  /// IANA zone attached to a known exact event time, when supplied by source.
  final String? timeZoneId;

  TransactionReviewState get reviewState =>
      reviewIssues.any((issue) => issue.status == ReviewIssueStatus.active)
      ? TransactionReviewState.needsReview
      : TransactionReviewState.clear;

  Transaction assignMerchant(MerchantId? value, DateTime at) =>
      _copy(merchantId: value, replaceMerchant: true, updatedAt: at);

  Transaction assignCategory(CategoryId? value, DateTime at) =>
      _copy(categoryId: value, replaceCategory: true, updatedAt: at);

  Transaction assignPaymentSource(PaymentSourceId? value, DateTime at) =>
      _copy(paymentSourceId: value, replacePaymentSource: true, updatedAt: at);

  Transaction addTag(TagId tagId, DateTime at) {
    if (tagIds.contains(tagId)) return this;
    return _copy(tagIds: [...tagIds, tagId], updatedAt: at);
  }

  Transaction removeTag(TagId tagId, DateTime at) =>
      _copy(tagIds: tagIds.where((id) => id != tagId).toList(), updatedAt: at);

  Transaction addReviewIssue(ReviewIssue issue, DateTime at) {
    if (issue.transactionId != id) {
      invalid(
        code: DomainErrorCode.relationshipMismatch,
        field: 'reviewIssue',
        message: 'A review issue cannot be attached to another transaction.',
      );
    }
    return _copy(reviewIssues: [...reviewIssues, issue], updatedAt: at);
  }

  Transaction resolveReviewIssue(ReviewIssueId id, DateTime at) =>
      _closeReviewIssue(id, at, (issue) => issue.resolve(at));

  Transaction dismissReviewIssue(ReviewIssueId id, DateTime at) =>
      _closeReviewIssue(id, at, (issue) => issue.dismiss(at));

  Transaction _closeReviewIssue(
    ReviewIssueId id,
    DateTime at,
    ReviewIssue Function(ReviewIssue) close,
  ) {
    var found = false;
    final updatedIssues = reviewIssues
        .map((issue) {
          if (issue.id != id) return issue;
          found = true;
          return close(issue);
        })
        .toList(growable: false);
    if (!found) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'reviewIssueId',
        message: 'The review issue does not belong to this transaction.',
      );
    }
    return _copy(reviewIssues: updatedIssues, updatedAt: at);
  }

  Transaction archive(DateTime at) =>
      _copy(status: TransactionStatus.archived, updatedAt: at);

  Transaction restore(DateTime at) =>
      _copy(status: TransactionStatus.active, updatedAt: at);

  Transaction addNormalizedMoney(NormalizedMoney value, DateTime at) {
    if (value.original != money) {
      invalid(
        code: DomainErrorCode.relationshipMismatch,
        field: 'normalizedMoney',
        message: 'Normalization cannot replace the original money.',
      );
    }
    return _copy(normalizedMoney: [...normalizedMoney, value], updatedAt: at);
  }

  Transaction _copy({
    TransactionStatus? status,
    PaymentSourceId? paymentSourceId,
    bool replacePaymentSource = false,
    MerchantId? merchantId,
    bool replaceMerchant = false,
    CategoryId? categoryId,
    bool replaceCategory = false,
    List<TagId>? tagIds,
    List<ReviewIssue>? reviewIssues,
    List<NormalizedMoney>? normalizedMoney,
    String? transactionDate,
    String? timeZoneId,
    String? externalReference,
    required DateTime updatedAt,
  }) => Transaction(
    id: id,
    timing: timing,
    money: money,
    direction: direction,
    sourceType: sourceType,
    status: status ?? this.status,
    description: description,
    rawCounterparty: rawCounterparty,
    sourceLanguage: sourceLanguage,
    notes: notes,
    externalReference: externalReference ?? this.externalReference,
    paymentSourceId: replacePaymentSource
        ? paymentSourceId
        : this.paymentSourceId,
    merchantId: replaceMerchant ? merchantId : this.merchantId,
    categoryId: replaceCategory ? categoryId : this.categoryId,
    tagIds: tagIds ?? this.tagIds,
    provenance: provenance,
    reviewIssues: reviewIssues ?? this.reviewIssues,
    normalizedMoney: normalizedMoney ?? this.normalizedMoney,
    createdAt: createdAt,
    updatedAt: updatedAt,
    transactionDate: transactionDate ?? this.transactionDate,
    timeZoneId: timeZoneId ?? this.timeZoneId,
  );
}
