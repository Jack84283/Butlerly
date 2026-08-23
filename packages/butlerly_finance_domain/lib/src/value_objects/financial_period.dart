/// A calendar period interpreted in the user's persisted IANA timezone.
///
/// Financial transactions carry a business date. This type deliberately does
/// not derive or rewrite that date from the device timezone or a current clock.
final class FinancialPeriod {
  FinancialPeriod({
    required this.startDate,
    required this.endDate,
    required this.timeZoneId,
  }) : assert(!endDate.isBefore(startDate));

  factory FinancialPeriod.month({
    required int year,
    required int month,
    required String timeZoneId,
  }) {
    final start = DateTime(year, month);
    return FinancialPeriod(
      startDate: _dateOnly(start),
      endDate: _dateOnly(DateTime(year, month + 1, 0)),
      timeZoneId: timeZoneId,
    );
  }

  final DateTime startDate;
  final DateTime endDate;
  final String timeZoneId;

  bool contains(DateTime transactionDate) {
    final date = _dateOnly(transactionDate);
    return !date.isBefore(startDate) && !date.isAfter(endDate);
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
