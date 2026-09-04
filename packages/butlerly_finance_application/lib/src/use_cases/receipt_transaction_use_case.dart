import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../dto/transaction_dto.dart';
import '../result/application_result.dart';
import 'transaction_use_cases.dart';
import 'classification_use_cases.dart';

final class ReceiptTransactionCommand {
  const ReceiptTransactionCommand({
    required this.id,
    required this.provenanceId,
    required this.money,
    required this.transactionDate,
    required this.originalRepresentation,
    this.rawCounterparty,
    this.description,
    this.notes,
    this.merchantId,
    this.categoryId,
    this.paymentSourceId,
    this.tagIds = const [],
  });

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
  const CreateReceiptTransaction(
    this.repository,
    this.clock, {
    this.classifier,
  });

  final TransactionRepository repository;
  final ApplicationClock clock;
  final ProposeTransactionClassification? classifier;

  Future<ApplicationResult<TransactionDto>> call(
    ReceiptTransactionCommand command,
  ) {
    return runApplication('create receipt transaction', () async {
      final existing = await repository.findById(TransactionId(command.id));
      if (existing != null) return TransactionDto.fromDomain(existing);
      final now = clock.now();
      final proposal = classifier == null
          ? null
          : await classifier!.call(
              merchantId: command.merchantId == null
                  ? null
                  : MerchantId(command.merchantId!),
              description: command.description ?? command.rawCounterparty,
              excludeTransactionId: TransactionId(command.id),
            );
      final resolvedMerchantId =
          command.merchantId == null &&
              proposal is ApplicationSuccess<ClassificationProposal>
          ? proposal.value.merchantId?.value
          : command.merchantId;
      final transaction = Transaction(
        id: TransactionId(command.id),
        timing: const UnknownTransactionTime(
          UnknownTransactionTimeReason.unknown,
        ),
        money: command.money,
        direction: TransactionDirection.expense,
        sourceType: TransactionSourceType.evidenceCapture,
        transactionDate: command.transactionDate,
        rawCounterparty: command.rawCounterparty,
        description: command.description,
        notes: command.notes,
        merchantId: resolvedMerchantId == null
            ? null
            : MerchantId(resolvedMerchantId),
        categoryId: command.categoryId == null
            ? null
            : CategoryId(command.categoryId!),
        paymentSourceId: command.paymentSourceId == null
            ? null
            : PaymentSourceId(command.paymentSourceId!),
        tagIds: command.tagIds.map(TagId.new).toList(growable: false),
        provenance: [
          Provenance(
            id: ProvenanceId(command.provenanceId),
            sourceType: ProvenanceSourceType.scan,
            capturedAt: now,
            originalRepresentation: command.originalRepresentation,
          ),
        ],
        createdAt: now,
        updatedAt: now,
      );
      await repository.save(transaction);
      final dto = TransactionDto.fromDomain(transaction);
      return TransactionDto(
        id: dto.id,
        amount: dto.amount,
        currency: dto.currency,
        direction: dto.direction,
        status: dto.status,
        reviewState: dto.reviewState,
        occurredAt: dto.occurredAt,
        transactionDate: dto.transactionDate,
        timeZoneId: dto.timeZoneId,
        createdAt: dto.createdAt,
        updatedAt: dto.updatedAt,
        description: dto.description,
        rawCounterparty: dto.rawCounterparty,
        sourceLanguage: dto.sourceLanguage,
        notes: dto.notes,
        externalReference: dto.externalReference,
        paymentSourceId: dto.paymentSourceId,
        merchantId: dto.merchantId,
        categoryId: dto.categoryId,
        tagIds: dto.tagIds,
        provenance: dto.provenance,
        normalizedMoney: dto.normalizedMoney,
        classificationProposal:
            proposal is ApplicationSuccess<ClassificationProposal>
            ? proposal.value
            : null,
      );
    });
  }
}
