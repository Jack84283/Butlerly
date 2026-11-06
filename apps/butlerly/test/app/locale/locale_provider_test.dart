import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('concurrent preference changes preserve independent fields', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(userPreferenceProvider.future);
    final controller = container.read(userPreferenceProvider.notifier);

    // These calls start before either previous save has completed.
    final disableSound = controller.saveChanges(
      transactionSaveSoundEnabled: false,
    );
    final switchLocale = controller.saveChanges(locale: 'zh');
    final updateName = controller.saveChanges(displayName: 'Butlerly');

    expect(await disableSound, isTrue);
    expect(await switchLocale, isTrue);
    expect(await updateName, isTrue);
    final saved = container.read(userPreferenceProvider).value!;
    expect(saved.transactionSaveSoundEnabled, isFalse);
    expect(saved.locale, 'zh');
    expect(saved.displayName, 'Butlerly');
  });

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
