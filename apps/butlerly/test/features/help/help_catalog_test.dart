import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/features/help/presentation/help_copy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bundled guide has nine chapters and no legacy duplicate articles',
    () async {
      final catalog = await HelpCatalog.load();
      final chapters = [
        'guide.introduction',
        'guide.getting-started',
        'guide.home',
        'guide.transactions',
        'guide.add',
        'guide.tools',
        'guide.more',
        'guide.help-reference',
        'guide.appendix',
      ];
      expect(catalog.guide.length, 51);
      expect(catalog.faqs.length, 30);
      final englishIds = catalog.guide.map((article) => article.id).toList();
      expect(englishIds.toSet().length, englishIds.length);
      expect(englishIds.where((id) => id.startsWith('ch-')), isEmpty);
      expect(englishIds.where((id) => id.startsWith('appendix-')), isEmpty);
      expect(englishIds.where((id) => id.startsWith('intro-')), isEmpty);
      for (final locale in ['en', 'zh', 'es']) {
        final translated = catalog.guideForLanguage(locale);
        expect(translated.map((article) => article.id).toList(), englishIds);
        for (final chapter in chapters) {
          expect(catalog.articleById(chapter, languageCode: locale), isNotNull);
        }
        expect(
          catalog
              .articleById('more.restore', languageCode: locale)!
              .body
              .length,
          greaterThan(500),
        );
        expect(
          catalog
              .articleById('guide.appendix', languageCode: locale)!
              .body
              .length,
          greaterThan(800),
        );
        for (final faq in catalog.faqs) {
          expect(
            catalog.articleById(faq.guideId, languageCode: locale),
            isNotNull,
          );
          expect(faq.translations[locale]?.question.isNotEmpty, isTrue);
          expect(faq.translations[locale]?.answer.isNotEmpty, isTrue);
        }
      }
    },
  );

  test(
    'screen-based topics have matching English Chinese and Spanish IDs',
    () async {
      final catalog = await HelpCatalog.load();
      final english = catalog.guide
          .where(
            (article) => RegExp(
              r'^(home|transactions|add|tools|more)\.',
            ).hasMatch(article.id),
          )
          .toList();
      expect(english.length, 42);
      final ids = english.map((article) => article.id).toSet();
      expect(ids.length, 42);
      for (final language in ['en', 'zh', 'es']) {
        for (final id in ids) {
          final article = catalog.articleById(id, languageCode: language);
          expect(article, isNotNull, reason: '$language: $id');
          expect(article!.title.trim(), isNotEmpty);
          expect(article.body.trim(), isNotEmpty);
        }
      }
      for (final language in ['en', 'zh', 'es']) {
        final export = catalog.articleById(
          'more.export',
          languageCode: language,
        );
        expect(export, isNotNull);
        expect(export!.body.trim(), isNotEmpty);
      }
      expect(catalog.articleById('guide.home'), isNotNull);
    },
  );

  test(
    'related topic IDs resolve in every locale without self-links',
    () async {
      final catalog = await HelpCatalog.load();
      for (final locale in ['en', 'zh', 'es']) {
        for (final article in catalog.guideForLanguage(locale)) {
          expect(article.relatedIds.toSet().length, article.relatedIds.length);
          expect(article.relatedIds, isNot(contains(article.id)));
          for (final id in article.relatedIds) {
            expect(
              catalog.articleById(id, languageCode: locale),
              isNotNull,
              reason: '$locale: ${article.id} → $id',
            );
          }
        }
      }
      expect(catalog.articleById('home.overview')!.relatedIds, isNotEmpty);
    },
  );

  test('guide text contains no references to deleted chapters', () async {
    final catalog = await HelpCatalog.load();
    final staleId = RegExp(r'\bch-\d+\b');
    final staleChapter = RegExp(
      r'(?:\bChapters?\s+(?:1[0-9]|2[0-9])\b|'
      r'\bcapítulo\s+(?:1[0-9]|2[0-9])\b|'
      r'第\s*(?:1[0-9]|2[0-9])\s*章)',
      caseSensitive: false,
    );
    for (final locale in ['en', 'zh', 'es']) {
      for (final article in catalog.guideForLanguage(locale)) {
        expect(
          staleId.hasMatch(article.body),
          isFalse,
          reason: '$locale: ${article.id}',
        );
        expect(
          staleChapter.hasMatch(article.body),
          isFalse,
          reason: '$locale: ${article.id}',
        );
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
        contains('more.backup'),
      );
      expect(
        catalog.search('PRESUPUESTOS', languageCode: 'es').map((hit) => hit.id),
        contains('tools.budgets'),
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

  test('natural-language Chinese and Spanish questions find answers', () async {
    final catalog = await HelpCatalog.load();
    for (final query in ['如何恢复备份', '备份和恢复']) {
      expect(
        catalog.search(query, languageCode: 'zh').map((hit) => hit.id),
        contains('FAQ-022'),
        reason: 'Chinese recovery query: $query',
      );
    }
    expect(
      catalog.search('忘记备份密码怎么办', languageCode: 'zh').map((hit) => hit.id),
      contains('FAQ-023'),
    );
    expect(
      catalog.search('同步云端文件', languageCode: 'zh').map((hit) => hit.id),
      contains('FAQ-009'),
    );
    expect(
      catalog
          .search('¿Cómo restauro una copia de seguridad?', languageCode: 'es')
          .map((hit) => hit.id),
      contains('FAQ-022'),
    );
    expect(
      catalog
          .search('¿Cómo importo archivos?', languageCode: 'es')
          .map((hit) => hit.id),
      contains('add.import'),
    );
    expect(
      catalog.search('contraseña', languageCode: 'es').map((hit) => hit.id),
      contains('FAQ-023'),
    );
    expect(catalog.search('如何', languageCode: 'zh'), isEmpty);
    expect(catalog.search('¿Cómo?', languageCode: 'es'), isEmpty);
  });

  test('repeated offline queries remain stable', () async {
    final catalog = await HelpCatalog.load();
    final previous = catalog
        .search('¿Cómo restauro una copia de seguridad?', languageCode: 'es')
        .map((hit) => hit.id)
        .toList();
    expect(previous, isNotEmpty);
    for (var attempt = 0; attempt < 20; attempt++) {
      expect(
        catalog
            .search(
              '¿Cómo restauro una copia de seguridad?',
              languageCode: 'es',
            )
            .map((hit) => hit.id)
            .toList(),
        previous,
      );
    }
  });

  test('every Help presentation label has English, Chinese and Spanish', () {
    expect(HelpCopy.missingKeysFor('zh'), isEmpty);
    expect(HelpCopy.missingKeysFor('es'), isEmpty);
  });
}
