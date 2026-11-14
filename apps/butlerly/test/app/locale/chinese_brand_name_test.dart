import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/app_localizations_backup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const brand = '账房先生';
  const quotedBrand = '“账房先生”';

  test('Chinese brand is bare alone and quoted inside labels', () {
    const zh = AppLocalizations(Locale('zh', 'CN'));
    const en = AppLocalizations(Locale('en'));

    expect(zh.text('appName'), brand);
    expect(zh.text('about'), '关于 $quotedBrand');
    expect(zh.text('welcomeTitle'), '欢迎使用 $quotedBrand');
    expect(zh.text('builtin'), brand);
    for (final key in [
      'csvTemplateRequired',
      'financialProfileBody',
      'financialProfileIntroBody',
      'cannotEditBuiltin',
      'addSubtitle',
      'reviewEmptyBody',
      'restoreRefreshWarning',
      'possibleDuplicatesUnavailableBody',
      'exportScopeBody',
      'eraseAllTitle',
      'eraseComplete',
      'evidenceDeletionRecoveryBody',
    ]) {
      final value = zh.text(key);
      expect(value, contains(quotedBrand), reason: 'Untranslated $key');
      expect(value, isNot(contains('Butlerly')), reason: key);
      expect(
        value.replaceAll(quotedBrand, ''),
        isNot(contains('账房先生')),
        reason: 'Unquoted Chinese brand in $key',
      );
    }

    expect(en.text('appName'), 'Butlerly');
    expect(en.text('about'), 'About Butlerly');
  });

  test('Chinese backup and recovery messages use quoted brand', () {
    const zh = AppLocalizations(Locale('zh', 'CN'));
    const en = AppLocalizations(Locale('en'));
    for (final key in backupLocalizationKeys) {
      final value = zh.backupText(key);
      expect(value, isNot(contains('Butlerly')), reason: key);
      expect(
        value.replaceAll(quotedBrand, ''),
        isNot(contains('账房先生')),
        reason: 'Unquoted Chinese brand in $key',
      );
    }
    expect(zh.backupText('recoverButlerly'), '恢复 $quotedBrand');
    expect(en.backupText('recoverButlerly'), 'Recover Butlerly');
  });

  test('Chinese guide and FAQ never show English or unquoted brand', () async {
    final catalog = await HelpCatalog.load();
    final chineseText = [
      for (final article in catalog.guideForLanguage('zh'))
        '${article.title}\n${article.body}',
      for (final faq in catalog.faqs)
        '${faq.translations['zh']!.question}\n${faq.translations['zh']!.answer}',
    ].join('\n');

    expect(chineseText, contains(quotedBrand));
    expect(chineseText, isNot(contains('Butlerly')));
    expect(chineseText.replaceAll(quotedBrand, ''), isNot(contains('账房先生')));
    expect(catalog.articleById('guide.introduction')!.body, contains('Butlerly'));
  });
}
