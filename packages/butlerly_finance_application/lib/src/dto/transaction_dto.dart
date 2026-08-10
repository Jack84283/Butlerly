import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import 'provenance_dto.dart';
import 'normalized_money_dto.dart';

final class TransactionDto {
  const TransactionDto({
    required this.id,
    required this.amount,
    required this.currency,
    required this.direction,
    required this.status,
    required this.reviewState,
    required this.createdAt,
    required this.updatedAt,
    this.occurredAt,
    this.transactionDate,
    this.timeZoneId,
    this.description,
    this.rawCounterparty,
    this.sourceLanguage,
    this.notes,
    this.paymentSourceId,
    this.merchantId,
    this.categoryId,
    this.tagIds = const [],
    this.provenance = const [],
    this.normalizedMoney = const [],
  });

  final String id;
  final String amount;
  final String currency;
  final String direction;
  final String status;
  final String reviewState;
  final DateTime? occurredAt;
  final String? transactionDate;
  final String? timeZoneId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? description;
  final String? rawCounterparty;
  final String? sourceLanguage;
  final String? notes;
  final String? paymentSourceId;
  final String? merchantId;
  final String? categoryId;
  final List<String> tagIds;
  final List<ProvenanceDto> provenance;
  final List<NormalizedMoneyDto> normalizedMoney;

  factory TransactionDto.fromDomain(Transaction value) => TransactionDto(
    id: value.id.value,
    amount: value.money.amount.toString(),
    currency: value.money.currency.value,
    direction: value.direction.name,
    status: value.status.name,
    reviewState: value.reviewState.name,
    occurredAt: value.timing is KnownTransactionTime
        ? (value.timing as KnownTransactionTime).occurredAt
        : null,
    transactionDate: value.transactionDate,
    timeZoneId: value.timeZoneId,
    createdAt: value.createdAt,
    updatedAt: value.updatedAt,
    description: value.description,
    rawCounterparty: value.rawCounterparty,
    sourceLanguage: value.sourceLanguage,
    notes: value.notes,
    paymentSourceId: value.paymentSourceId?.value,
    merchantId: value.merchantId?.value,
    categoryId: value.categoryId?.value,
    tagIds: List.unmodifiable(value.tagIds.map((id) => id.value)),
    provenance: List.unmodifiable(
      value.provenance.map(ProvenanceDto.fromDomain),
    ),
    normalizedMoney: List.unmodifiable(
      value.normalizedMoney.map(NormalizedMoneyDto.fromDomain),
    ),
  );
}
