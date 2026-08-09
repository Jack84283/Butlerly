import '../errors/domain_error.dart';
import '../value_objects/domain_id.dart';
import 'provenance.dart';

enum SuggestionTarget {
  merchant,
  category,
  description,
  extraction,
  duplicate,
  other,
}

enum SuggestionStatus { proposed, accepted, rejected, expired }

enum SuggestionMethod { rule, localAi, externalAi, deterministic }

final class Suggestion {
  Suggestion({
    required this.id,
    required this.transactionId,
    required this.target,
    required String proposedValue,
    required this.method,
    required this.provenance,
    required DateTime createdAt,
    this.status = SuggestionStatus.proposed,
    this.confidence,
    this.rationale,
    this.provider,
    this.model,
    DateTime? decidedAt,
  }) : proposedValue = _requiredValue(proposedValue),
       createdAt = createdAt.toUtc(),
       decidedAt = decidedAt?.toUtc() {
    if (confidence != null && (confidence! < 0 || confidence! > 1)) {
      invalid(
        code: DomainErrorCode.invalidRange,
        field: 'confidence',
        message: 'Suggestion confidence must be between 0 and 1.',
      );
    }
    if (status == SuggestionStatus.proposed && decidedAt != null) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'decidedAt',
        message: 'A proposed suggestion cannot have a decision time.',
      );
    }
    if (status != SuggestionStatus.proposed && decidedAt == null) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'decidedAt',
        message: 'A decided suggestion requires a decision time.',
      );
    }
  }

  final SuggestionId id;
  final TransactionId transactionId;
  final SuggestionTarget target;
  final String proposedValue;
  final SuggestionMethod method;
  final SuggestionStatus status;
  final Provenance provenance;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final double? confidence;
  final String? rationale;
  final String? provider;
  final String? model;

  Suggestion accept(DateTime at) => _decide(SuggestionStatus.accepted, at);
  Suggestion reject(DateTime at) => _decide(SuggestionStatus.rejected, at);
  Suggestion expire(DateTime at) => _decide(SuggestionStatus.expired, at);

  Suggestion _decide(SuggestionStatus nextStatus, DateTime at) {
    if (status != SuggestionStatus.proposed) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'status',
        message: 'A suggestion can only be decided once.',
      );
    }
    return Suggestion(
      id: id,
      transactionId: transactionId,
      target: target,
      proposedValue: proposedValue,
      method: method,
      provenance: provenance,
      createdAt: createdAt,
      status: nextStatus,
      confidence: confidence,
      rationale: rationale,
      provider: provider,
      model: model,
      decidedAt: at,
    );
  }

  static String _requiredValue(String value) {
    if (value.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'proposedValue',
        message: 'A suggestion requires a proposed value.',
      );
    }
    return value;
  }
}
