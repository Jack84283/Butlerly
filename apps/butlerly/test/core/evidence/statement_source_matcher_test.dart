import 'package:butlerly/core/evidence/statement_source_matcher.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PaymentSource source(String id, {String? issuer}) => PaymentSource(
    id: PaymentSourceId(id),
    name: id,
    type: PaymentSourceType.card,
    lastFour: '1234',
    issuer: issuer,
  );

  test('matches one active source from a masked statement identifier', () {
    final expected = source('visa');

    expect(
      confidentlyMatchStatementSource(
        maskedAccountIdentifier: '••••1234',
        institution: null,
        sources: [expected],
      ),
      same(expected),
    );
  });

  test('does not silently choose an ambiguous source', () {
    expect(
      confidentlyMatchStatementSource(
        maskedAccountIdentifier: '••••1234',
        institution: null,
        sources: [source('one'), source('two')],
      ),
      isNull,
    );
  });

  test('uses institution evidence to disambiguate matching digits', () {
    final expected = source('one', issuer: 'Example Bank');

    expect(
      confidentlyMatchStatementSource(
        maskedAccountIdentifier: '••••1234',
        institution: 'example bank',
        sources: [
          expected,
          source('two', issuer: 'Other Bank'),
        ],
      ),
      same(expected),
    );
  });
}
