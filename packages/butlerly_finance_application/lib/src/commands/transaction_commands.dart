import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class CreateTransactionCommand {
  const CreateTransactionCommand({
    required this.id,
    required this.provenanceId,
    required this.timing,
    required this.money,
    required this.direction,
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
  });

  final String id;
  final String provenanceId;
  final TransactionTiming timing;
  final Money money;
  final TransactionDirection direction;
  final String? transactionDate;
  final String? timeZoneId;
  final String? description;
  final String? rawCounterparty;
  final String? sourceLanguage;
  final String? notes;
  final String? paymentSourceId;
  final String? merchantId;
  final String? categoryId;
  final List<String> tagIds;
}

final class UpdateTransactionCommand {
  const UpdateTransactionCommand({
    required this.id,
    required this.timing,
    required this.money,
    required this.direction,
    this.transactionDate,
    this.timeZoneId,
    this.description,
    this.rawCounterparty,
    this.sourceLanguage,
    this.notes,
  });

  final String id;
  final TransactionTiming timing;
  final Money money;
  final TransactionDirection direction;
  final String? transactionDate;
  final String? timeZoneId;
  final String? description;
  final String? rawCounterparty;
  final String? sourceLanguage;
  final String? notes;
}

final class ListTransactionsQuery {
  const ListTransactionsQuery({
    this.text,
    this.from,
    this.to,
    this.categoryId,
    this.paymentSourceId,
    this.currency,
    this.direction,
    this.status,
    this.needsReview,
  });

  final String? text;
  final DateTime? from;
  final DateTime? to;
  final String? categoryId;
  final String? paymentSourceId;
  final String? currency;
  final TransactionDirection? direction;
  final TransactionStatus? status;
  final bool? needsReview;
}
