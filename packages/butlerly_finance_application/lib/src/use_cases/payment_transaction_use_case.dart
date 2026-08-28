import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../dto/transaction_dto.dart';
import '../result/application_result.dart';
import 'transaction_use_cases.dart';

final class PaymentTransactionCommand {
  const PaymentTransactionCommand({
    required this.id,
    required this.provenanceId,
    required this.money,
    required this.direction,
    required this.transactionDate,
    required this.originalRepresentation,
    required this.sourceId,
    this.description,
    this.paymentSourceId,
    this.externalReference,
    this.sourceType = TransactionSourceType.manual,
    this.provenanceSourceType = ProvenanceSourceType.userEntry,
  });

  final String id;
  final String provenanceId;
  final Money money;
  final TransactionDirection direction;
  final String transactionDate;
  final String originalRepresentation;
  final String sourceId;
  final String? description;
  final String? paymentSourceId;
  final String? externalReference;
  final TransactionSourceType sourceType;
  final ProvenanceSourceType provenanceSourceType;
}

final class CreatePaymentTransaction {
  const CreatePaymentTransaction(this.repository, this.clock);

  final TransactionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    PaymentTransactionCommand command,
  ) => runApplication('create payment transaction', () async {
    await assertNoDuplicateTransaction(
      repository,
      DuplicateTransactionCheckCommand(
        transactionDate: command.transactionDate,
        amount: command.money.amount.toString(),
        currency: command.money.currency.value,
        direction: command.direction,
      ),
    );
    final now = clock.now();
    final transaction = Transaction(
      id: TransactionId(command.id),
      timing: const UnknownTransactionTime(
        UnknownTransactionTimeReason.unknown,
      ),
      money: command.money,
      direction: command.direction,
      sourceType: command.sourceType,
      transactionDate: command.transactionDate,
      description: command.description,
      rawCounterparty: command.description,
      paymentSourceId: command.paymentSourceId == null
          ? null
          : PaymentSourceId(command.paymentSourceId!),
      externalReference: command.externalReference,
      provenance: [
        Provenance(
          id: ProvenanceId(command.provenanceId),
          sourceType: command.provenanceSourceType,
          capturedAt: now,
          sourceId: command.sourceId,
          originalRepresentation: command.originalRepresentation,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
    await repository.save(transaction);
    return TransactionDto.fromDomain(transaction);
  });
}
