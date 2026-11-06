import 'dart:convert';

import 'package:flutter/services.dart';

/// All Help content is packaged with Butlerly and read from local assets.
/// Search and navigation never use an HTTP client or an external provider.
class HelpGuideArticle {
  const HelpGuideArticle({
    required this.id,
    required this.title,
    required this.part,
    required this.body,
  });

  final String id;
  final String title;
  final String part;
  final String body;

  factory HelpGuideArticle.fromJson(Map<String, dynamic> json) =>
      HelpGuideArticle(
        id: json['id'] as String,
        title: json['title'] as String,
        part: json['part'] as String,
        body: json['body'] as String,
      );
}

class HelpFaqTranslation {
  const HelpFaqTranslation({required this.question, required this.answer});

  final String question;
  final String answer;

  factory HelpFaqTranslation.fromJson(Map<String, dynamic> json) =>
      HelpFaqTranslation(
        question: json['question'] as String,
        answer: json['answer'] as String,
      );
}

class HelpFaqEntry {
  const HelpFaqEntry({
    required this.id,
    required this.category,
    required this.keywords,
    required this.guideId,
    required this.translations,
  });

  final String id;
  final String category;
  final List<String> keywords;
  final String guideId;
  final Map<String, HelpFaqTranslation> translations;

  HelpFaqTranslation translation(String languageCode) =>
      translations[languageCode] ?? translations['en']!;

  factory HelpFaqEntry.fromJson(Map<String, dynamic> json) {
    final rawTranslations = json['translations'] as Map<String, dynamic>;
    return HelpFaqEntry(
      id: json['id'] as String,
      category: json['category'] as String,
      keywords: (json['keywords'] as List<dynamic>).cast<String>(),
      guideId: json['guideId'] as String,
      translations: rawTranslations.map(
        (key, value) => MapEntry(
          key,
          HelpFaqTranslation.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }
}

class HelpSearchHit {
  const HelpSearchHit({
    required this.id,
    required this.title,
    required this.snippet,
    required this.category,
    required this.score,
    this.faq,
    this.article,
  });

  final String id;
  final String title;
  final String snippet;
  final String category;
  final int score;
  final HelpFaqEntry? faq;
  final HelpGuideArticle? article;

  bool get isFaq => faq != null;
}

class HelpCatalog {
  const HelpCatalog({required this.guide, required this.faqs});

  final List<HelpGuideArticle> guide;
  final List<HelpFaqEntry> faqs;

  HelpGuideArticle? articleById(String id) {
    for (final article in guide) {
      if (article.id == id) return article;
    }
    return null;
  }

  HelpFaqEntry? faqById(String id) {
    for (final faq in faqs) {
      if (faq.id == id) return faq;
    }
    return null;
  }

  List<String> get categories {
    final result = <String>[];
    for (final item in faqs) {
      if (!result.contains(item.category)) result.add(item.category);
    }
    return result;
  }

  static Future<HelpCatalog> load({AssetBundle? bundle}) async {
    final localBundle = bundle ?? rootBundle;
    final values = await Future.wait([
      localBundle.loadString('assets/help/guide_en.json'),
      localBundle.loadString('assets/help/faq.json'),
    ]);
    final guideData = jsonDecode(values[0]) as Map<String, dynamic>;
    final faqData = jsonDecode(values[1]) as Map<String, dynamic>;
    final guide = (guideData['articles'] as List<dynamic>)
        .map(
          (entry) => HelpGuideArticle.fromJson(entry as Map<String, dynamic>),
        )
        .toList(growable: false);
    final faqs = (faqData['faqs'] as List<dynamic>)
        .map((entry) => HelpFaqEntry.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
    final articleIds = guide.map((entry) => entry.id).toSet();
    final faqIds = faqs.map((entry) => entry.id).toSet();
    if (articleIds.length != guide.length ||
        faqIds.length != faqs.length ||
        faqs.any(
          (faq) =>
              !articleIds.contains(faq.guideId) ||
              !{'en', 'zh', 'es'}.every(
                (locale) =>
                    faq.translations[locale]?.question.isNotEmpty == true &&
                    faq.translations[locale]?.answer.isNotEmpty == true,
              ),
        )) {
      throw const FormatException('Invalid bundled Help references or locales');
    }
    return HelpCatalog(guide: guide, faqs: faqs);
  }

  /// Search is deterministic, locale-aware, and performed in memory.
  /// FAQ titles rank ahead of keyword matches, which rank ahead of bodies.
  List<HelpSearchHit> search(String query, {String languageCode = 'en'}) {
    final normalized = _fold(query).trim();
    if (normalized.isEmpty) return const [];
    final tokens = normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    final results = <HelpSearchHit>[];

    for (final faq in faqs) {
      final translated = faq.translation(languageCode);
      final title = _fold(translated.question);
      final englishTitle = _fold(faq.translation('en').question);
      final keywords = _fold(faq.keywords.join(' '));
      final category = _fold(faq.category);
      final body = _fold(translated.answer);
      if (!tokens.every(
        (token) =>
            title.contains(token) ||
            englishTitle.contains(token) ||
            keywords.contains(token) ||
            category.contains(token) ||
            body.contains(token),
      )) {
        continue;
      }
      final score =
          (title.contains(normalized) ? 120 : 0) +
          (englishTitle.contains(normalized) ? 45 : 0) +
          (keywords.contains(normalized) ? 40 : 0) +
          tokens.where(title.contains).length * 25 +
          tokens.where(keywords.contains).length * 12 +
          tokens.where(body.contains).length * 2 +
          5;
      results.add(
        HelpSearchHit(
          id: faq.id,
          title: translated.question,
          snippet: translated.answer,
          category: faq.category,
          score: score,
          faq: faq,
        ),
      );
    }

    for (final article in guide) {
      final title = _fold(article.title);
      final body = _fold(article.body);
      if (!tokens.every(
        (token) => title.contains(token) || body.contains(token),
      )) {
        continue;
      }
      final score =
          (title.contains(normalized) ? 65 : 0) +
          tokens.where(title.contains).length * 14 +
          tokens.where(body.contains).length;
      results.add(
        HelpSearchHit(
          id: article.id,
          title: article.title,
          snippet: article.body.replaceAll(RegExp(r'\s+'), ' ').trim(),
          category: article.part,
          score: score,
          article: article,
        ),
      );
    }

    results.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      if (a.isFaq != b.isFaq) return a.isFaq ? -1 : 1;
      return a.id.compareTo(b.id);
    });
    return results;
  }

  static String _fold(String value) {
    var text = value.toLowerCase();
    const marks = <String, String>{
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ñ': 'n',
      'ç': 'c',
    };
    for (final mark in marks.entries) {
      text = text.replaceAll(mark.key, mark.value);
    }
    return text;
  }
}
