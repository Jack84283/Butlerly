import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../dto/transaction_dto.dart';
import '../result/application_result.dart';
import 'transaction_use_cases.dart';

final class ReceiptTransactionCommand {
  const ReceiptTransactionCommand({required this.id, required this.provenanceId, required this.money, required this.transactionDate, required this.originalRepresentation, this.rawCounterparty, this.description, this.notes, this.merchantId, this.categoryId, this.paymentSourceId, this.tagIds = const []});
  final String id;
  final String provenanceId;
  final Money money;
  final String transactionDate;
  final String originalRepresentation;
  final String? rawCounterparty;
  final String? description;
  final String? notes;
  final String? merchantId;
  final String? categoryId;
  final String? paymentSourceId;
  final List<String> tagIds;
}

final class CreateReceiptTransaction {
  const CreateReceiptTransaction(this.repository, this.clock);
  final TransactionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(ReceiptTransactionCommand command) => runApplication('create receipt transaction', () async {
    final now = clock.now();
    final transaction = Transaction(
      id: TransactionId(command.id),
      timing: const UnknownTransactionTime(UnknownTransactionTimeReason.unknown),
      money: command.money,
      direction: TransactionDirection.expense,
      sourceType: TransactionSourceType.evidenceCapture,
      transactionDate: command.transactionDate,
      rawCounterparty: command.rawCounterparty,
      description: command.description,
      notes: command.notes,
      merchantId: command.merchantId == null ? null : MerchantId(command.merchantId!),
      categoryId: command.categoryId == null ? null : CategoryId(command.categoryId!),
      paymentSourceId: command.paymentSourceId == null ? null : PaymentSourceId(command.paymentSourceId!),
      tagIds: command.tagIds.map(TagId.new).toList(growable: false),
      provenance: [Provenance(id: ProvenanceId(command.provenanceId), sourceType: ProvenanceSourceType.scan, capturedAt: now, originalRepresentation: command.originalRepresentation)],
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(transaction);
    return TransactionDto.fromDomain(transaction);
  });
}
