import 'currency_code.dart';
import 'decimal_value.dart';

final class Money {
  const Money({required this.amount, required this.currency});

  final DecimalValue amount;
  final CurrencyCode currency;

  @override
  bool operator ==(Object other) =>
      other is Money && other.amount == amount && other.currency == currency;

  @override
  int get hashCode => Object.hash(amount, currency);

  @override
  String toString() => '$amount $currency';
}
