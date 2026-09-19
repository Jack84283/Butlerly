import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test('mixed scales and signs retain exact decimal arithmetic', () {
    final left = DecimalValue.parse('9007199254740993.01');
    final right = DecimalValue.parse('0.009');
    expect(left.add(right).toString(), '9007199254740993.019');
    expect(left.subtract(right).toString(), '9007199254740993.001');
    expect(left.add(right).subtract(right), left);
    expect(
      DecimalValue.parse(
        '-1.20',
      ).multiply(DecimalValue.parse('0.5')).toString(),
      '-0.6',
    );
    expect(DecimalValue.parse('-1.20').abs().toString(), '1.2');
  });

  test('sums empty, zero, and mixed-scale inputs exactly', () {
    expect(DecimalValue.sum([]).isZero, isTrue);
    expect(
      DecimalValue.sum(
        ['1.01', '-1', '-0.009', '0.0001'].map(DecimalValue.parse),
      ).toString(),
      '0.0011',
    );
    expect(
      DecimalValue.sum(
        ['123.45', '-123.45'].map(DecimalValue.parse),
      ).toString(),
      '0',
    );
  });
}
