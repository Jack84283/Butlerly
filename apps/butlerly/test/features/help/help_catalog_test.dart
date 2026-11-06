import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/features/help/presentation/help_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled guide has all 25 chapters and locally linked FAQs', () async {
    final catalog = await HelpCatalog.load();
    expect(
      catalog.guide.where((item) => item.id.startsWith('ch-')),
      hasLength(25),
    );
    expect(
      catalog.guide.where((item) => item.id.startsWith('appendix-')),
      hasLength(4),
    );
    expect(catalog.faqs, hasLength(30));
    expect(catalog.articleById('ch-19'), isNotNull);
    final englishIds = catalog.guide.map((article) => article.id).toList();
    for (final locale in ['en', 'zh', 'es']) {
      final translated = catalog.guideForLanguage(locale);
      expect(translated.map((article) => article.id).toList(), englishIds);
      expect(
        translated.where((article) => article.id.startsWith('ch-')),
        hasLength(25),
      );
      expect(
        translated.where((article) => article.id.startsWith('appendix-')),
        hasLength(4),
      );
      expect(catalog.articleById('ch-19', languageCode: locale), isNotNull);
    }
    expect(
      catalog.articleById('ch-19', languageCode: 'zh')!.title,
      contains('恢复'),
    );
    expect(
      catalog.articleById('ch-19', languageCode: 'es')!.title,
      contains('RESTAURAR'),
    );
    for (final faq in catalog.faqs) {
      expect(catalog.articleById(faq.guideId), isNotNull);
      for (final language in ['en', 'zh', 'es']) {
        expect(faq.translations[language]?.question.isNotEmpty, isTrue);
        expect(faq.translations[language]?.answer.isNotEmpty, isTrue);
      }
    }
  });

  test('guide contains no developer-only issue or code references', () async {
    final catalog = await HelpCatalog.load();
    final guideText = ['en', 'zh', 'es']
        .expand((locale) => catalog.guideForLanguage(locale))
        .map((article) => article.title + article.body)
        .join('\n');
    expect(
      RegExp(
        r'Flutter|SQLite|GitHub|pull request|PR #|Issue #',
        caseSensitive: false,
      ).hasMatch(guideText),
      isFalse,
    );
  });

  test(
    'search finds backup, cloud, Chinese and Spanish answers offline',
    () async {
      final catalog = await HelpCatalog.load();
      expect(catalog.search('MERGE replace').first.id, 'FAQ-022');
      expect(
        catalog.search('加密备份', languageCode: 'zh').map((hit) => hit.id),
        contains('ch-18'),
      );
      expect(
        catalog.search('PRESUPUESTOS', languageCode: 'es').map((hit) => hit.id),
        contains('ch-15'),
      );
      expect(
        catalog.search('How do I restore a backup?').map((hit) => hit.id),
        contains('FAQ-022'),
      );
      expect(
        catalog.search('Google Drive').map((hit) => hit.id),
        contains('FAQ-009'),
      );
      expect(
        catalog.search('同步', languageCode: 'zh').map((hit) => hit.id),
        contains('FAQ-009'),
      );
      expect(
        catalog.search('sincronizar', languageCode: 'es').map((hit) => hit.id),
        contains('FAQ-009'),
      );
      expect(
        catalog.search('contrasena', languageCode: 'es').map((hit) => hit.id),
        contains('FAQ-023'),
      );
      expect(catalog.search('   '), isEmpty);
      expect(catalog.search('zzzzuniquenoresultsterm'), isEmpty);
    },
  );

  test('every Help presentation label has English, Chinese and Spanish', () {
    expect(HelpCopy.missingKeysFor('zh'), isEmpty);
    expect(HelpCopy.missingKeysFor('es'), isEmpty);
  });
}
