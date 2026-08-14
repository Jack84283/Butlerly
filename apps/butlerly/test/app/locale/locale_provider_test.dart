import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps stable IANA timezone identifiers', () {
    expect(
      canonicalTimeZoneId('America/Los_Angeles', countryCode: 'US'),
      'America/Los_Angeles',
    );
  });

  test('migrates daylight-saving abbreviations using device region', () {
    expect(
      canonicalTimeZoneId('PDT', countryCode: 'US'),
      'America/Los_Angeles',
    );
    expect(canonicalTimeZoneId('CST', countryCode: 'CN'), 'Asia/Shanghai');
  });

  test('uses UTC when an abbreviation cannot be resolved safely', () {
    expect(canonicalTimeZoneId('IST', countryCode: 'US'), 'UTC');
  });
}
