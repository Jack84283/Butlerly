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
    this.relatedIds = const [],
  });

  factory HelpGuideArticle.fromJson(Map<String, dynamic> json) =>
      HelpGuideArticle(
        id: json['id'] as String,
        title: json['title'] as String,
        part: json['part'] as String,
        body: json['body'] as String,
        relatedIds: (json['relatedIds'] as List<dynamic>? ?? const [])
            .cast<String>(),
      );

  final String id;
  final String title;
  final String part;
  final String body;
  final List<String> relatedIds;
}

class HelpFaqTranslation {
  const HelpFaqTranslation({required this.question, required this.answer});

  factory HelpFaqTranslation.fromJson(Map<String, dynamic> json) =>
      HelpFaqTranslation(
        question: json['question'] as String,
        answer: json['answer'] as String,
      );

  final String question;
  final String answer;
}

class HelpFaqEntry {
  const HelpFaqEntry({
    required this.id,
    required this.category,
    required this.keywords,
    required this.guideId,
    required this.translations,
  });

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

  final String id;
  final String category;
  final List<String> keywords;
  final String guideId;
  final Map<String, HelpFaqTranslation> translations;

  HelpFaqTranslation translation(String languageCode) =>
      translations[languageCode] ?? translations['en']!;
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
  HelpCatalog({
    required this.guide,
    required this.faqs,
    required this.localizedGuides,
  }) : _searchIndexes = _buildSearchIndexes(localizedGuides, faqs);

  /// Normalized once when the bundled catalog is loaded; never reprocess
  /// article bodies while the user types.
  final Map<String, _HelpSearchIndex> _searchIndexes;

  /// English reference edition, retained for backwards compatibility.
  final List<HelpGuideArticle> guide;
  final List<HelpFaqEntry> faqs;
  final Map<String, List<HelpGuideArticle>> localizedGuides;

  List<HelpGuideArticle> guideForLanguage(String languageCode) =>
      localizedGuides[languageCode] ?? guide;

  HelpGuideArticle? articleById(String id, {String languageCode = 'en'}) {
    for (final article in guideForLanguage(languageCode)) {
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

  // Bundled Help is immutable for an app version. Reuse one load across
  // page navigations so opening Help doesn't restart four asset reads.
  // Explicit custom bundles remain uncached for isolated tests.
  static Future<HelpCatalog>? _bundledCatalog;
  static HelpCatalog? _bundledCatalogValue;

  /// Loaded, immutable offline Help content, when available in memory.
  static HelpCatalog? get cachedBundle => _bundledCatalogValue;

  static Future<HelpCatalog> load({AssetBundle? bundle}) {
    if (bundle != null) return _readFrom(bundle);
    return _bundledCatalog ??= _readFrom(rootBundle).then(
      (catalog) {
        _bundledCatalogValue = catalog;
        return catalog;
      },
      onError: (Object error, StackTrace stack) {
        _bundledCatalog = null;
        _bundledCatalogValue = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  static Future<HelpCatalog> _readFrom(AssetBundle localBundle) async {
    final values = await Future.wait([
      localBundle.loadString('assets/help/guide_en.json'),
      localBundle.loadString('assets/help/guide_zh.json'),
      localBundle.loadString('assets/help/guide_es.json'),
      localBundle.loadString('assets/help/faq.json'),
    ]);
    List<HelpGuideArticle> decodeGuide(String value) {
      final data = jsonDecode(value) as Map<String, dynamic>;
      return (data['articles'] as List<dynamic>)
          .map(
            (entry) => HelpGuideArticle.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false);
    }

    final guides = <String, List<HelpGuideArticle>>{
      'en': decodeGuide(values[0]),
      'zh': decodeGuide(values[1]),
      'es': decodeGuide(values[2]),
    };
    final guide = guides['en']!;
    final faqData = jsonDecode(values[3]) as Map<String, dynamic>;
    final faqs = (faqData['faqs'] as List<dynamic>)
        .map((entry) => HelpFaqEntry.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
    final articleIds = guide.map((entry) => entry.id).toSet();
    final faqIds = faqs.map((entry) => entry.id).toSet();
    if (articleIds.length != guide.length ||
        faqIds.length != faqs.length ||
        guides.values.any(
          (localized) =>
              localized.length != guide.length ||
              localized.any(
                (article) =>
                    !articleIds.contains(article.id) ||
                    article.title.trim().isEmpty ||
                    article.body.trim().isEmpty,
              ) ||
              localized.map((article) => article.id).toSet().length !=
                  guide.length,
        ) ||
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
    return HelpCatalog(guide: guide, faqs: faqs, localizedGuides: guides);
  }

  /// Searches the precomputed in-memory index; never reads data over a network.
  /// FAQ question matches rank ahead of body matches and guide text.
  List<HelpSearchHit> search(String query, {String languageCode = 'en'}) {
    final locale = _searchIndexes.containsKey(languageCode)
        ? languageCode
        : 'en';
    final normalized = _helpIndexField(query, locale);
    final tokens = _helpQueryTerms(normalized, locale);
    if (tokens.isEmpty) return const [];

    final index = _searchIndexes[locale]!;
    final results = <HelpSearchHit>[];
    for (final entry in index.faqs) {
      if (!tokens.every(
        (token) =>
            entry.title.contains(token) ||
            entry.englishTitle.contains(token) ||
            entry.keywords.contains(token) ||
            entry.category.contains(token) ||
            entry.body.contains(token),
      )) {
        continue;
      }

      final score =
          (entry.title.contains(normalized) ? 120 : 0) +
          (entry.englishTitle.contains(normalized) ? 45 : 0) +
          (entry.keywords.contains(normalized) ? 40 : 0) +
          tokens.where(entry.title.contains).length * 25 +
          tokens.where(entry.keywords.contains).length * 12 +
          tokens.where(entry.body.contains).length * 2 +
          5;
      results.add(
        HelpSearchHit(
          id: entry.faq.id,
          title: entry.translation.question,
          snippet: entry.translation.answer,
          category: entry.faq.category,
          score: score,
          faq: entry.faq,
        ),
      );
    }

    for (final entry in index.articles) {
      if (!tokens.every(
        (token) => entry.title.contains(token) || entry.body.contains(token),
      )) {
        continue;
      }
      final score =
          (entry.title.contains(normalized) ? 65 : 0) +
          tokens.where(entry.title.contains).length * 14 +
          tokens.where(entry.body.contains).length;
      results.add(
        HelpSearchHit(
          id: entry.article.id,
          title: entry.article.title,
          snippet: entry.snippet,
          category: entry.article.part,
          score: score,
          article: entry.article,
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

/// A fixed search index for one locale. Only immutable bundled content is
/// indexed; user transactions and other private records are never inspected.
class _HelpSearchIndex {
  const _HelpSearchIndex({required this.faqs, required this.articles});

  final List<_IndexedHelpFaq> faqs;
  final List<_IndexedHelpArticle> articles;
}

class _IndexedHelpFaq {
  _IndexedHelpFaq(this.faq, String locale)
    : translation = faq.translation(locale),
      title = _helpIndexField(faq.translation(locale).question, locale),
      englishTitle = _helpIndexField(faq.translation('en').question, locale),
      keywords = _helpIndexField(faq.keywords.join(' '), locale),
      category = _helpIndexField(faq.category, locale),
      body = _helpIndexField(faq.translation(locale).answer, locale);

  final HelpFaqEntry faq;
  final HelpFaqTranslation translation;
  final String title;
  final String englishTitle;
  final String keywords;
  final String category;
  final String body;
}

class _IndexedHelpArticle {
  _IndexedHelpArticle(this.article, String locale)
    : title = _helpIndexField(article.title, locale),
      body = _helpIndexField(article.body, locale),
      snippet = article.body.replaceAll(RegExp(r'\s+'), ' ').trim();

  final HelpGuideArticle article;
  final String title;
  final String body;
  final String snippet;
}

Map<String, _HelpSearchIndex> _buildSearchIndexes(
  Map<String, List<HelpGuideArticle>> guides,
  List<HelpFaqEntry> faqs,
) {
  return {
    for (final locale in ['en', 'zh', 'es'])
      locale: _HelpSearchIndex(
        faqs: List.unmodifiable(
          faqs.map((faq) => _IndexedHelpFaq(faq, locale)),
        ),
        articles: List.unmodifiable(
          (guides[locale] ?? guides['en']!).map(
            (article) => _IndexedHelpArticle(article, locale),
          ),
        ),
      ),
  };
}

String _helpIndexField(String value, String locale) {
  final normalized = HelpCatalog._fold(value)
      .replaceAll(RegExp(r'[^a-z0-9\u3400-\u9fff\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (locale != 'es' || normalized.isEmpty) return normalized;
  return normalized.split(' ').map(_helpSpanishRoot).join(' ');
}

/// Small predictable Spanish inflection normalization for local Help only.
/// No online translation, user-data processing or external dependency.
String _helpSpanishRoot(String term) {
  if (term.length < 5) return term;
  for (final ending in [
    'aciones',
    'adores',
    'adoras',
    'acion',
    'mente',
    'ando',
    'iendo',
    'ados',
    'adas',
    'idos',
    'idas',
    'ando',
    'ando',
    'ar',
    'er',
    'ir',
    'os',
    'as',
    'es',
  ]) {
    if (term.endsWith(ending) && term.length - ending.length >= 4) {
      return term.substring(0, term.length - ending.length);
    }
  }
  if (term.endsWith('o') || term.endsWith('a') || term.endsWith('s')) {
    return term.substring(0, term.length - 1);
  }
  return term;
}

const _helpStopWords = <String>{
  'how',
  'do',
  'i',
  'a',
  'an',
  'the',
  'to',
  'my',
  'is',
  'are',
  'what',
  'does',
  'can',
  'for',
  'of',
  'where',
  'why',
  'and',
  'or',
  'me',
  'vs',
  'versus',
  'como',
  'puedo',
  'de',
  'la',
  'el',
  'una',
  'un',
  'los',
  'las',
  'que',
  'por',
  'en',
  'del',
  'para',
  'mi',
  'mis',
  'se',
  'es',
  'yo',
  'y',
  'o',
  'hago',
  'hacer',
};

/// The explicit vocabulary avoids treating a Chinese sentence with no spaces
/// as an impossible whole-string match. Unknown multi-character terms are
/// retained to avoid returning unrelated results.
const _helpChineseTerms = <String>[
  '支付来源',
  '找不到',
  '未分类',
  '重复交易',
  '银行卡',
  '加密',
  '备份',
  '密码',
  '忘记',
  '忘了',
  '丢失',
  '找回',
  '恢复',
  '还原',
  '合并',
  '替换',
  '数据',
  '删除',
  '导出',
  '交易',
  '记录',
  '重复',
  '金额',
  '商家',
  '收据',
  '账单',
  '同步',
  '云端',
  '云盘',
  '文件',
  '导入',
  '分类',
  '类别',
  '分析',
  '预算',
  '设置',
  '语言',
  '币种',
  '时区',
  '支付',
  '来源',
  '报表',
  '账户',
  '账号',
  '搜索',
  '帮助',
  '修改',
  '编辑',
  '添加',
  '查看',
  '确认',
  '离线',
  '联网',
  '网络',
  '购买',
  '错误',
  '失败',
  '问题',
  '安全',
  '导入',
  '存储',
];

const _helpChineseStopPhrases = <String>[
  '怎么办',
  '怎么样',
  '如何',
  '怎么',
  '怎样',
  '请问',
  '我想',
  '是否',
  '可以',
  '能够',
  '能否',
  '一下',
  '我的',
  '为什么',
  '什么',
  '无法',
  '不能',
  '请',
  '我',
  '吗',
  '呢',
  '的',
  '了',
  '是',
];

List<String> _helpQueryTerms(String normalized, String locale) {
  if (locale != 'zh') {
    return normalized
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty && !_helpStopWords.contains(token))
        .toSet()
        .toList(growable: false);
  }

  var remaining = normalized;
  for (final phrase in _helpChineseStopPhrases) {
    remaining = remaining.replaceAll(phrase, ' ');
  }
  final terms = <String>[];
  for (final match in RegExp(
    r'[\u3400-\u9fff]+|[a-z0-9]+',
  ).allMatches(remaining)) {
    final chunk = match.group(0)!;
    if (!RegExp(r'^[\u3400-\u9fff]').hasMatch(chunk)) {
      if (!_helpStopWords.contains(chunk)) terms.add(chunk);
      continue;
    }

    final unknown = StringBuffer();
    var offset = 0;
    void flushUnknown() {
      final residue = unknown.toString();
      if (residue.length >= 2) terms.add(residue);
      unknown.clear();
    }

    while (offset < chunk.length) {
      String? found;
      for (final word in _helpChineseTerms) {
        if (chunk.startsWith(word, offset) &&
            (found == null || word.length > found.length)) {
          found = word;
        }
      }
      if (found == null) {
        unknown.write(chunk[offset]);
        offset++;
      } else {
        flushUnknown();
        terms.add(switch (found) {
          '还原' || '找回' => '恢复',
          '云盘' => '云端',
          '忘了' => '忘记',
          _ => found,
        });
        offset += found.length;
      }
    }
    flushUnknown();
  }
  return terms.toSet().toList(growable: false);
}
