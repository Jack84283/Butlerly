import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

/// Returns a source only when statement evidence identifies one active source.
PaymentSource? confidentlyMatchStatementSource({
  required String? maskedAccountIdentifier,
  required String? institution,
  required Iterable<PaymentSource> sources,
}) {
  final lastFour = RegExp(
    r'(\d{4})$',
  ).firstMatch(maskedAccountIdentifier ?? '')?.group(1);
  if (lastFour == null) return null;
  final normalizedInstitution = institution?.trim().toLowerCase();
  final identifierMatches = sources
      .where(
        (source) =>
            source.status == PaymentSourceStatus.active &&
            source.lastFour == lastFour,
      )
      .toList(growable: false);
  if (identifierMatches.length == 1) return identifierMatches.single;
  if (normalizedInstitution == null || normalizedInstitution.isEmpty) {
    return null;
  }
  final issuerMatches = identifierMatches
      .where(
        (source) =>
            source.issuer?.trim().toLowerCase() == normalizedInstitution,
      )
      .toList(growable: false);
  return issuerMatches.length == 1 ? issuerMatches.single : null;
}
