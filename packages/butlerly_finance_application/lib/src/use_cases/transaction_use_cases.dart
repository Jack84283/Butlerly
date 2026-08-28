import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

import '../commands/transaction_commands.dart';
import '../dto/review_item_dto.dart';
import '../dto/transaction_dto.dart';
import '../result/application_result.dart';

abstract interface class ApplicationClock {
  DateTime now();
}

final class SystemApplicationClock implements ApplicationClock {
  const SystemApplicationClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}

final class CreateTransaction {
  const CreateTransaction(this.repository, this.clock);

  final TransactionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    CreateTransactionCommand command,
  ) => runApplication('create transaction', () async {
    final transactionDate = command.transactionDate;
    if (transactionDate != null) {
      await assertNoDuplicateTransaction(
        repository,
        DuplicateTransactionCheckCommand(
          transactionDate: transactionDate,
          amount: command.money.amount.toString(),
          currency: command.money.currency.value,
          direction: command.direction,
        ),
      );
    }
    final now = clock.now();
    final transaction = Transaction(
      id: TransactionId(command.id),
      timing: command.timing,
      money: command.money,
      direction: command.direction,
      sourceType: TransactionSourceType.manual,
      description: command.description,
      rawCounterparty: command.rawCounterparty,
      sourceLanguage: command.sourceLanguage,
      notes: command.notes,
      externalReference: command.externalReference,
      paymentSourceId: _optional(command.paymentSourceId, PaymentSourceId.new),
      merchantId: _optional(command.merchantId, MerchantId.new),
      categoryId: _optional(command.categoryId, CategoryId.new),
      tagIds: command.tagIds.map(TagId.new).toList(growable: false),
      provenance: [
        Provenance(
          id: ProvenanceId(command.provenanceId),
          sourceType: ProvenanceSourceType.userEntry,
          capturedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
      transactionDate: command.transactionDate,
      timeZoneId: command.timeZoneId,
    );
    await repository.save(transaction);
    return TransactionDto.fromDomain(transaction);
  });
}

final class UpdateTransaction {
  const UpdateTransaction(this.repository, this.clock);

  final TransactionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    UpdateTransactionCommand command,
  ) async {
    final operation = 'update transaction';
    final existing = await _find(repository, command.id, operation);
    if (existing case ApplicationFailure<Transaction> failure) {
      return ApplicationFailure(failure.failure);
    }
    final current = (existing as ApplicationSuccess<Transaction>).value;
    return runApplication(operation, () async {
      final updated = Transaction(
        id: current.id,
        timing: command.timing,
        money: command.money,
        direction: command.direction,
        sourceType: current.sourceType,
        status: current.status,
        description: command.description,
        rawCounterparty: command.rawCounterparty,
        sourceLanguage: command.sourceLanguage,
        notes: command.notes,
        externalReference:
            command.externalReference ?? current.externalReference,
        paymentSourceId: !command.replacePaymentSource
            ? current.paymentSourceId
            : _optional(command.paymentSourceId, PaymentSourceId.new),
        merchantId: !command.replaceMerchant
            ? current.merchantId
            : _optional(command.merchantId, MerchantId.new),
        categoryId: !command.replaceCategory
            ? current.categoryId
            : _optional(command.categoryId, CategoryId.new),
        tagIds: command.replaceTags
            ? command.tagIds?.map(TagId.new).toList(growable: false) ?? const []
            : current.tagIds,
        provenance: current.provenance,
        reviewIssues: current.reviewIssues,
        normalizedMoney: command.money == current.money
            ? current.normalizedMoney
            : const [],
        createdAt: current.createdAt,
        updatedAt: clock.now(),
        transactionDate: command.transactionDate ?? current.transactionDate,
        timeZoneId: command.timeZoneId ?? current.timeZoneId,
      );
      await assertNoDuplicateTransaction(
        repository,
        DuplicateTransactionCheckCommand(
          transactionDate: updated.transactionDate!,
          amount: updated.money.amount.toString(),
          currency: updated.money.currency.value,
          direction: updated.direction,
          excludeTransactionId: updated.id.value,
        ),
      );
      await repository.save(updated);
      return TransactionDto.fromDomain(updated);
    });
  }
}

final class ImportTransaction {
  const ImportTransaction(this.repository, this.clock);

  final TransactionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    ImportTransactionCommand command,
  ) => runApplication('import transaction', () async {
    if (await repository.findById(TransactionId(command.id)) != null) {
      throw const RepositoryException(
        RepositoryFailureCode.constraint,
        'import duplicate transaction',
      );
    }
    final date = DateTime.tryParse(command.transactionDate);
    if (date == null ||
        command.transactionDate.length != 10 ||
        date.toIso8601String().substring(0, 10) != command.transactionDate) {
      throw const DomainValidationException(
        code: DomainErrorCode.invalidTimestamp,
        field: 'transactionDate',
        message: 'Imported business dates must use YYYY-MM-DD.',
      );
    }
    final now = clock.now();
    final transaction = Transaction(
      id: TransactionId(command.id),
      timing: command.occurredAtUtc == null
          ? const UnknownTransactionTime(UnknownTransactionTimeReason.unknown)
          : KnownTransactionTime(command.occurredAtUtc!),
      money: command.money,
      direction: command.direction,
      sourceType: TransactionSourceType.import,
      description: command.description,
      rawCounterparty: command.rawCounterparty,
      sourceLanguage: command.sourceLanguage,
      notes: command.notes,
      externalReference: command.externalReference,
      paymentSourceId: _optional(command.paymentSourceId, PaymentSourceId.new),
      provenance: [
        Provenance(
          id: ProvenanceId(command.provenanceId),
          sourceType: ProvenanceSourceType.import,
          capturedAt: now,
          sourceId: command.sourceId,
          originalRepresentation: command.originalRepresentation,
          sourceLanguage: command.sourceLanguage,
        ),
      ],
      createdAt: now,
      updatedAt: now,
      transactionDate: command.transactionDate,
      timeZoneId: command.timeZoneId,
    );
    await assertNoDuplicateTransaction(
      repository,
      DuplicateTransactionCheckCommand(
        transactionDate: transaction.transactionDate!,
        amount: transaction.money.amount.toString(),
        currency: transaction.money.currency.value,
        direction: transaction.direction,
      ),
    );
    await repository.save(transaction);
    return TransactionDto.fromDomain(transaction);
  });
}

final class GetTransaction {
  const GetTransaction(this.repository);

  final TransactionRepository repository;

  Future<ApplicationResult<TransactionDto>> call(String id) async {
    final result = await _find(repository, id, 'get transaction');
    return switch (result) {
      ApplicationSuccess<Transaction>(:final value) => ApplicationSuccess(
        TransactionDto.fromDomain(value),
      ),
      ApplicationFailure<Transaction>(:final failure) => ApplicationFailure(
        failure,
      ),
    };
  }
}

final class ListTransactions {
  const ListTransactions(this.repository);

  final TransactionRepository repository;

  Future<ApplicationResult<List<TransactionDto>>> call(
    ListTransactionsQuery query,
  ) => runApplication('list transactions', () async {
    if (query.from != null &&
        query.to != null &&
        query.from!.isAfter(query.to!)) {
      throw const DomainValidationException(
        code: DomainErrorCode.invalidRange,
        field: 'dateRange',
        message: 'The start of a date range cannot follow its end.',
      );
    }
    final values = await repository.query(
      TransactionRepositoryQuery(
        text: query.text,
        from: query.from,
        to: query.to,
        categoryId: _optional(query.categoryId, CategoryId.new),
        paymentSourceId: _optional(query.paymentSourceId, PaymentSourceId.new),
        currency: query.currency,
        direction: query.direction,
        status: query.status,
        needsReview: query.needsReview,
      ),
    );
    return List.unmodifiable(values.map(TransactionDto.fromDomain));
  });
}

final class ArchiveTransaction {
  const ArchiveTransaction(this.repository, this.clock);

  final TransactionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(String id) =>
      _mutate(repository, id, 'archive transaction', (value) {
        return value.archive(clock.now());
      });
}

final class RestoreTransaction {
  const RestoreTransaction(this.repository, this.clock);

  final TransactionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(String id) =>
      _mutate(repository, id, 'restore transaction', (value) {
        return value.restore(clock.now());
      });
}

final class DeleteTransactionPermanently {
  const DeleteTransactionPermanently(this.repository);

  final TransactionRepository repository;

  Future<ApplicationResult<void>> call(String id) async {
    final operation = 'delete transaction permanently';
    final existing = await _find(repository, id, operation);
    if (existing is ApplicationFailure<Transaction>) {
      return ApplicationFailure(existing.failure);
    }
    return runApplication(
      operation,
      () => repository.removePermanently(TransactionId(id)),
    );
  }
}

final class AssignMerchant {
  const AssignMerchant(this.repository, this.merchants, this.clock);

  final TransactionRepository repository;
  final MerchantRepository merchants;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    String transactionId,
    String? merchantId,
  ) async {
    if (merchantId != null &&
        await merchants.findById(MerchantId(merchantId)) == null) {
      return notFound('assign merchant');
    }
    return _mutate(repository, transactionId, 'assign merchant', (value) {
      return value.assignMerchant(
        merchantId == null ? null : MerchantId(merchantId),
        clock.now(),
      );
    });
  }
}

final class AssignCategory {
  const AssignCategory(this.repository, this.categories, this.clock);

  final TransactionRepository repository;
  final CategoryRepository categories;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    String transactionId,
    String? categoryId,
  ) async {
    if (categoryId != null &&
        await categories.findById(CategoryId(categoryId)) == null) {
      return notFound('assign category');
    }
    return _mutate(repository, transactionId, 'assign category', (value) {
      return value.assignCategory(
        categoryId == null ? null : CategoryId(categoryId),
        clock.now(),
      );
    });
  }
}

final class AssignPaymentSource {
  const AssignPaymentSource(this.repository, this.sources, this.clock);

  final TransactionRepository repository;
  final PaymentSourceRepository sources;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    String transactionId,
    String? paymentSourceId,
  ) async {
    if (paymentSourceId != null &&
        await sources.findById(PaymentSourceId(paymentSourceId)) == null) {
      return notFound('assign payment source');
    }
    return _mutate(repository, transactionId, 'assign payment source', (value) {
      return value.assignPaymentSource(
        paymentSourceId == null ? null : PaymentSourceId(paymentSourceId),
        clock.now(),
      );
    });
  }
}

final class AddTag {
  const AddTag(this.repository, this.tags, this.clock);

  final TransactionRepository repository;
  final TagRepository tags;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    String transactionId,
    String tagId,
  ) async {
    if (await tags.findById(TagId(tagId)) == null) {
      return notFound('add tag');
    }
    return _mutate(repository, transactionId, 'add tag', (value) {
      return value.addTag(TagId(tagId), clock.now());
    });
  }
}

final class RemoveTag {
  const RemoveTag(this.repository, this.clock);

  final TransactionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    String transactionId,
    String tagId,
  ) => _mutate(repository, transactionId, 'remove tag', (value) {
    return value.removeTag(TagId(tagId), clock.now());
  });
}

final class ListReviewItems {
  const ListReviewItems(this.repository);

  final TransactionRepository repository;

  Future<ApplicationResult<List<ReviewItemDto>>> call() =>
      runApplication('list review items', () async {
        final transactions = await repository.query(
          const TransactionRepositoryQuery(needsReview: true),
        );
        return List.unmodifiable(
          transactions.expand(
            (transaction) => transaction.reviewIssues
                .where((issue) => issue.status == ReviewIssueStatus.active)
                .map((issue) => ReviewItemDto.fromDomain(transaction, issue)),
          ),
        );
      });
}

final class ResolveReviewIssue {
  const ResolveReviewIssue(this.repository, this.clock);

  final TransactionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    String transactionId,
    String issueId,
  ) => _mutate(repository, transactionId, 'resolve review issue', (value) {
    return value.resolveReviewIssue(ReviewIssueId(issueId), clock.now());
  });
}

final class DismissReviewIssue {
  const DismissReviewIssue(this.repository, this.clock);

  final TransactionRepository repository;
  final ApplicationClock clock;

  Future<ApplicationResult<TransactionDto>> call(
    String transactionId,
    String issueId,
  ) => _mutate(repository, transactionId, 'dismiss review issue', (value) {
    return value.dismissReviewIssue(ReviewIssueId(issueId), clock.now());
  });
}

final class AttachEvidence {
  const AttachEvidence(this.transactions, this.evidence);

  final TransactionRepository transactions;
  final EvidenceRepository evidence;

  Future<ApplicationResult<void>> call({
    required String linkId,
    required String transactionId,
    required String evidenceId,
    required DateTime createdAt,
  }) async {
    const operation = 'attach evidence';
    if (await transactions.findById(TransactionId(transactionId)) == null ||
        await evidence.findById(EvidenceId(evidenceId)) == null) {
      return notFound(operation);
    }
    return runApplication(
      operation,
      () => evidence.link(
        AttachmentLink(
          id: AttachmentLinkId(linkId),
          transactionId: TransactionId(transactionId),
          evidenceId: EvidenceId(evidenceId),
          createdAt: createdAt,
        ),
      ),
    );
  }
}

final class ListEvidenceForTransaction {
  const ListEvidenceForTransaction(this.evidence);

  final EvidenceRepository evidence;

  Future<ApplicationResult<List<EvidenceItem>>> call(String transactionId) =>
      runApplication('list transaction evidence', () async {
        return List.unmodifiable(
          await evidence.listForTransaction(TransactionId(transactionId)),
        );
      });
}

Future<ApplicationResult<TransactionDto>> _mutate(
  TransactionRepository repository,
  String id,
  String operation,
  Transaction Function(Transaction) change,
) async {
  final found = await _find(repository, id, operation);
  if (found case ApplicationFailure<Transaction> failure) {
    return ApplicationFailure(failure.failure);
  }
  return runApplication(operation, () async {
    final updated = change((found as ApplicationSuccess<Transaction>).value);
    await repository.save(updated);
    return TransactionDto.fromDomain(updated);
  });
}

Future<ApplicationResult<Transaction>> _find(
  TransactionRepository repository,
  String id,
  String operation,
) => runApplication(operation, () async {
  final value = await repository.findById(TransactionId(id));
  if (value == null) {
    throw RepositoryException(RepositoryFailureCode.notFound, operation);
  }
  return value;
});

T? _optional<T>(String? value, T Function(String) create) {
  if (value == null) return null;
  return create(value);
}
