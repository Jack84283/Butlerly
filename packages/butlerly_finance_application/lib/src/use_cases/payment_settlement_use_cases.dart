import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../dto/payment_settlement_dto.dart';
import '../dto/transaction_dto.dart';
import '../result/application_result.dart';
import 'transaction_use_cases.dart';

final class SavePaymentSettlement {
  const SavePaymentSettlement(
    this.settlements,
    this.paymentSources,
    this.clock,
  );

  final PaymentSettlementRepository settlements;
  final PaymentSourceRepository paymentSources;
  final ApplicationClock clock;

  Future<ApplicationResult<PaymentSettlementDto>> call({
    required String id,
    required String paymentSourceId,
    required Money payment,
    required String paymentDate,
    required String periodStart,
    required String periodEnd,
    PaymentSettlementStatus status = PaymentSettlementStatus.open,
    String? fundingPaymentSourceId,
    Money? statementBalance,
    String? description,
    String? externalReference,
  }) => runApplication('save payment settlement', () async {
    final source = PaymentSourceId(paymentSourceId);
    if (await paymentSources.findById(source) == null) {
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'save payment settlement payment source',
      );
    }
    final fundingSource = fundingPaymentSourceId == null
        ? null
        : PaymentSourceId(fundingPaymentSourceId);
    if (fundingSource != null &&
        await paymentSources.findById(fundingSource) == null) {
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'save payment settlement funding source',
      );
    }

    final settlementId = PaymentSettlementId(id);
    final existing = await settlements.findById(settlementId);
    final now = clock.now();
    final value = PaymentSettlement(
      id: settlementId,
      paymentSourceId: source,
      fundingPaymentSourceId: fundingSource,
      payment: payment,
      paymentDate: paymentDate,
      periodStart: periodStart,
      periodEnd: periodEnd,
      statementBalance: statementBalance,
      status: status,
      description: description,
      externalReference: externalReference,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
    await settlements.save(value);
    return PaymentSettlementDto.fromDomain(value);
  });
}

final class ListPaymentSettlements {
  const ListPaymentSettlements(this.repository);

  final PaymentSettlementRepository repository;

  Future<ApplicationResult<List<PaymentSettlementDto>>> call() =>
      runApplication('list payment settlements', () async {
        final values = await repository.listAll();
        return List.unmodifiable(values.map(PaymentSettlementDto.fromDomain));
      });
}

final class GetPaymentSettlementDetail {
  const GetPaymentSettlementDetail(this.repository);

  final PaymentSettlementRepository repository;

  Future<ApplicationResult<PaymentSettlementDetailDto>> call(String id) =>
      runApplication('get payment settlement detail', () async {
        final settlement = await repository.findById(PaymentSettlementId(id));
        if (settlement == null) {
          throw const RepositoryException(
            RepositoryFailureCode.notFound,
            'get payment settlement detail',
          );
        }
        final transactions = await repository.listTransactions(settlement);
        return PaymentSettlementDetailDto(
          settlement: PaymentSettlementDto.fromDomain(settlement),
          transactions: List.unmodifiable(
            transactions.map(TransactionDto.fromDomain),
          ),
        );
      });
}

final class SetPaymentSettlementStatus {
  const SetPaymentSettlementStatus(this.repository, this.clock);

  final PaymentSettlementRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<PaymentSettlementDto>> call(
    String id,
    PaymentSettlementStatus status,
  ) => runApplication('set payment settlement status', () async {
    final settlementId = PaymentSettlementId(id);
    final current = await repository.findById(settlementId);
    if (current == null) {
      throw const RepositoryException(
        RepositoryFailureCode.notFound,
        'set payment settlement status',
      );
    }
    final updated = PaymentSettlement(
      id: current.id,
      paymentSourceId: current.paymentSourceId,
      fundingPaymentSourceId: current.fundingPaymentSourceId,
      payment: current.payment,
      paymentDate: current.paymentDate,
      periodStart: current.periodStart,
      periodEnd: current.periodEnd,
      statementBalance: current.statementBalance,
      status: status,
      description: current.description,
      externalReference: current.externalReference,
      createdAt: current.createdAt,
      updatedAt: clock.now(),
    );
    await repository.save(updated);
    return PaymentSettlementDto.fromDomain(updated);
  });
}

final class DeletePaymentSettlement {
  const DeletePaymentSettlement(this.repository);

  final PaymentSettlementRepository repository;

  Future<ApplicationResult<void>> call(String id) =>
      runApplication('delete payment settlement', () async {
        final settlementId = PaymentSettlementId(id);
        if (await repository.findById(settlementId) == null) {
          throw const RepositoryException(
            RepositoryFailureCode.notFound,
            'delete payment settlement',
          );
        }
        await repository.remove(settlementId);
      });
}
