import '../errors/domain_error.dart';

enum StatementStatus { needsSource, ready, partial, archived }

enum StatementRowStatus {
  pending,
  deferred,
  skipped,
  saved,
  linked,
  unresolved,
}

enum StatementRowKind { purchase, refund, payment, fee, credit, other }

final class FinancialStatement {
  FinancialStatement({
    required this.id,
    required this.evidenceId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.paymentSourceId,
    this.institution,
    this.maskedAccountIdentifier,
    this.periodStart,
    this.periodEnd,
    this.statementDate,
    this.currency,
    this.openingBalance,
    this.closingBalance,
    this.originalFilename,
    this.rawTextReference,
    this.extractionMessage,
  }) {
    if (id.trim().isEmpty || evidenceId.trim().isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'statement',
        message: 'Statement identity is required.',
      );
    }
    if ((periodStart == null) != (periodEnd == null) ||
        (periodStart != null && periodEnd!.isBefore(periodStart!))) {
      invalid(
        code: DomainErrorCode.invalidRange,
        field: 'statementPeriod',
        message: 'Statement period must be a complete ordered range.',
      );
    }
  }

  final String id;
  final String evidenceId;
  final String? paymentSourceId;
  final StatementStatus status;
  final String? institution;
  final String? maskedAccountIdentifier;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? statementDate;
  final String? currency;
  final String? openingBalance;
  final String? closingBalance;
  final String? originalFilename;
  final String? rawTextReference;
  final String? extractionMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class StatementRow {
  StatementRow({
    required this.id,
    required this.statementId,
    required this.position,
    required this.originalText,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.transactionDate,
    this.postingDate,
    this.description,
    this.amount,
    this.currency,
    this.direction,
    this.kind = StatementRowKind.other,
    this.confidence,
    this.sourceContext,
    this.transactionId,
    this.merchantId,
    this.categoryId,
    this.subcategoryId,
    this.tagIds = const [],
    this.paymentSourceId,
    this.sourceReferenceId,
    this.reviewReason,
    this.dispositionReason,
  }) {
    if (id.trim().isEmpty ||
        statementId.trim().isEmpty ||
        originalText.trim().isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'statementRow',
        message: 'Statement row identity and source text are required.',
      );
    }
    if (position < 0 ||
        (confidence != null && (confidence! < 0 || confidence! > 1))) {
      invalid(
        code: DomainErrorCode.invalidRange,
        field: 'statementRow',
        message: 'Statement row position or confidence is invalid.',
      );
    }
    if ((status == StatementRowStatus.saved ||
            status == StatementRowStatus.linked) &&
        transactionId == null) {
      invalid(
        code: DomainErrorCode.invalidState,
        field: 'transactionId',
        message: 'Completed rows must reference a transaction.',
      );
    }
  }

  final String id;
  final String statementId;
  final int position;
  final String originalText;
  final DateTime? transactionDate;
  final DateTime? postingDate;
  final String? description;
  final String? amount;
  final String? currency;
  final String? direction;
  final StatementRowKind kind;
  final double? confidence;
  final String? sourceContext;
  final StatementRowStatus status;
  final String? transactionId;
  final String? merchantId;
  final String? categoryId;
  final String? subcategoryId;
  final List<String> tagIds;
  final String? paymentSourceId;
  final String? sourceReferenceId;
  final String? reviewReason;
  final String? dispositionReason;
  final DateTime createdAt;
  final DateTime updatedAt;
}
