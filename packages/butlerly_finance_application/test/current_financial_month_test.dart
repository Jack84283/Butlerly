import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:test/test.dart';

void main() {
  test('financial date advances month before the device-local date', () {
    final instant = DateTime.parse('2026-08-31T16:30:00Z');

    expect(financialDateAt(instant, 'Asia/Shanghai'), DateTime.utc(2026, 9, 1));
  });

  test('financial date remains in prior month after UTC advances', () {
    final instant = DateTime.parse('2026-09-01T01:30:00Z');

    expect(
      financialDateAt(instant, 'America/Los_Angeles'),
      DateTime.utc(2026, 8, 31),
    );
  });
}
