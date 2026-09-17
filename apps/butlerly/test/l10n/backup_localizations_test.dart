import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('backup vocabulary is complete in every supported language', () {
    for (final locale in AppLocalizations.supportedLocales) {
      expect(
        missingBackupLocalizationKeysFor(locale.languageCode),
        isEmpty,
        reason: 'Missing backup copy for ${locale.languageCode}',
      );
    }
  });

  test('backup vocabulary resolves every English key in all locales', () {
    for (final locale in const [
      Locale('en'),
      Locale('es'),
      Locale('zh', 'CN'),
    ]) {
      final localizations = AppLocalizations(locale);
      for (final key in backupLocalizationKeys) {
        final value = localizations.backupText(key);
        expect(
          value,
          isNotEmpty,
          reason: '$key is empty for ${locale.languageCode}',
        );
        expect(value, isNot(key), reason: '$key fell back to the raw key');
      }
    }
  });
}
