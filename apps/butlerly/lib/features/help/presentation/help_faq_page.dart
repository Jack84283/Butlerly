import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/features/help/presentation/help_copy.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Bundled, fully offline Help. No user queries or records leave the device.
class HelpFaqPage extends StatefulWidget {
  const HelpFaqPage({super.key});

  @override
  State<HelpFaqPage> createState() => _HelpFaqPageState();
}

class _HelpFaqPageState extends State<HelpFaqPage> {
  final TextEditingController _searchController = TextEditingController();
  late Future<HelpCatalog> _catalog = HelpCatalog.load();
  String? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openHelp(HelpCatalog catalog, HelpSearchHit hit) {
    if (hit.faq != null) {
      _openFaq(context, catalog, hit.faq!);
    } else if (hit.article != null) {
      _openArticle(context, hit.article!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim();
    return Material(
      type: MaterialType.transparency,
      child: FutureBuilder<HelpCatalog>(
        future: _catalog,
        builder: (context, snapshot) {
          final catalog = snapshot.data;
          return ButlerlyPage(
            title: HelpCopy.text(context, 'title'),
            subtitle: HelpCopy.text(context, 'subtitle'),
            leading: _helpBackButton(context),
            children: [
              TextField(
                key: const ValueKey('help-search'),
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: HelpCopy.text(context, 'search'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: const OutlineInputBorder(),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: HelpCopy.text(context, 'clear'),
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: ButlerlySpacing.section),
              if (snapshot.hasError) ...[
                ButlerlyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(HelpCopy.text(context, 'loadFailed')),
                      TextButton(
                        onPressed: () {
                          setState(() => _catalog = HelpCatalog.load());
                        },
                        child: Text(HelpCopy.text(context, 'retry')),
                      ),
                    ],
                  ),
                ),
              ] else if (catalog == null) ...[
                const Center(child: CircularProgressIndicator()),
              ] else ...[
                if (query.isNotEmpty)
                  ..._searchResults(context, catalog, query)
                else
                  ..._browseContent(context, catalog),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _searchResults(
    BuildContext context,
    HelpCatalog catalog,
    String query,
  ) {
    final language = Localizations.localeOf(context).languageCode;
    final hits = catalog.search(query, languageCode: language);
    if (hits.isEmpty) {
      return [
        ButlerlyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                HelpCopy.text(context, 'noResults'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: ButlerlySpacing.small),
              Text(HelpCopy.text(context, 'noResultsBody')),
              const SizedBox(height: ButlerlySpacing.small),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
                child: Text(HelpCopy.text(context, 'all')),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (final hit in hits)
        Padding(
          padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
          child: ButlerlyCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              key: ValueKey('help-hit-${hit.id}'),
              leading: Icon(
                hit.isFaq
                    ? Icons.help_outline_rounded
                    : Icons.menu_book_outlined,
              ),
              title: Text(hit.title),
              subtitle: Text(
                _hitSummary(context, hit),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openHelp(catalog, hit),
            ),
          ),
        ),
    ];
  }

  List<Widget> _browseContent(BuildContext context, HelpCatalog catalog) {
    final selected = _selectedCategory;
    final faqs = selected == null
        ? catalog.faqs
              .where(
                (faq) => const {
                  'FAQ-022',
                  'FAQ-021',
                  'FAQ-009',
                  'FAQ-015',
                  'FAQ-012',
                }.contains(faq.id),
              )
              .toList(growable: false)
        : catalog.faqs
              .where((faq) => faq.category == selected)
              .toList(growable: false);
    final language = Localizations.localeOf(context).languageCode;
    return [
      ButlerlyCard(
        child: ListTile(
          key: const ValueKey('help-full-guide'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(HelpCopy.text(context, 'fullGuide')),
          subtitle: Text(HelpCopy.text(context, 'guideSubtitle')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Material(
                type: MaterialType.transparency,
                child: HelpGuideIndexPage(catalog: catalog),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: ButlerlySpacing.section),
      _heading(context, HelpCopy.text(context, 'topics')),
      const SizedBox(height: ButlerlySpacing.small),
      Wrap(
        spacing: ButlerlySpacing.small,
        runSpacing: ButlerlySpacing.small,
        children: [
          ChoiceChip(
            label: Text(HelpCopy.text(context, 'all')),
            selected: selected == null,
            onSelected: (_) => setState(() => _selectedCategory = null),
          ),
          for (final category in catalog.categories)
            ChoiceChip(
              label: Text(HelpCopy.category(context, category)),
              selected: selected == category,
              onSelected: (_) => setState(() => _selectedCategory = category),
            ),
        ],
      ),
      const SizedBox(height: ButlerlySpacing.section),
      _heading(
        context,
        selected == null
            ? HelpCopy.text(context, 'popular')
            : HelpCopy.category(context, selected),
      ),
      const SizedBox(height: ButlerlySpacing.small),
      ButlerlyCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < faqs.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                key: ValueKey('help-faq-${faqs[i].id}'),
                title: Text(faqs[i].translation(language).question),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openFaq(context, catalog, faqs[i]),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: ButlerlySpacing.section),
    ];
  }
}

String _hitSummary(BuildContext context, HelpSearchHit hit) {
  final type = hit.isFaq
      ? HelpCopy.category(context, hit.category)
      : HelpCopy.text(context, 'guideArticle');
  return '$type • ${_preview(hit.snippet)}';
}

String _preview(String body) {
  final flattened = body
      .replaceAll(RegExp(r'##\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return flattened.length > 190 ? '${flattened.substring(0, 190)}…' : flattened;
}

Widget _heading(BuildContext context, String text) =>
    Text(text, style: Theme.of(context).textTheme.titleMedium);

Widget _helpBackButton(BuildContext context) => IconButton(
  tooltip: HelpCopy.text(context, 'back'),
  icon: const Icon(Icons.arrow_back_rounded),
  onPressed: () {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/settings');
    }
  },
);

void _openFaq(BuildContext context, HelpCatalog catalog, HelpFaqEntry faq) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Material(
        type: MaterialType.transparency,
        child: HelpFaqDetailPage(catalog: catalog, faq: faq),
      ),
    ),
  );
}

void _openArticle(BuildContext context, HelpGuideArticle article) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Material(
        type: MaterialType.transparency,
        child: HelpGuideArticlePage(article: article),
      ),
    ),
  );
}

class HelpFaqDetailPage extends StatelessWidget {
  const HelpFaqDetailPage({
    required this.catalog,
    required this.faq,
    super.key,
  });

  final HelpCatalog catalog;
  final HelpFaqEntry faq;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final translation = faq.translation(language);
    final linked = catalog.articleById(faq.guideId, languageCode: language);
    return ButlerlyPage(
      title: HelpCopy.text(context, 'faq'),
      subtitle: HelpCopy.category(context, faq.category),
      leading: _helpBackButton(context),
      children: [
        Text(
          translation.question,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: ButlerlySpacing.section),
        SelectableText(translation.answer),
        if (linked != null) ...[
          const SizedBox(height: ButlerlySpacing.section),
          OutlinedButton.icon(
            key: const ValueKey('help-read-guide'),
            onPressed: () => _openArticle(context, linked),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(HelpCopy.text(context, 'readMore')),
          ),
        ],
      ],
    );
  }
}

class HelpGuideIndexPage extends StatelessWidget {
  const HelpGuideIndexPage({required this.catalog, super.key});

  final HelpCatalog catalog;

  @override
  Widget build(BuildContext context) {
    String? part;
    final language = Localizations.localeOf(context).languageCode;
    final widgets = <Widget>[];
    for (final article in catalog.guideForLanguage(language)) {
      if (part != article.part) {
        part = article.part;
        widgets.add(_heading(context, article.part));
        widgets.add(const SizedBox(height: ButlerlySpacing.small));
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
          child: ButlerlyCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              key: ValueKey('help-article-${article.id}'),
              title: Text(article.title),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _openArticle(context, article),
            ),
          ),
        ),
      );
    }
    return ButlerlyPage(
      title: HelpCopy.text(context, 'guide'),
      leading: _helpBackButton(context),
      children: widgets,
    );
  }
}

class HelpGuideArticlePage extends StatelessWidget {
  const HelpGuideArticlePage({required this.article, super.key});

  final HelpGuideArticle article;

  @override
  Widget build(BuildContext context) {
    final sections = article.body
        .split(RegExp(r'\n\s*\n'))
        .where((section) => section.trim().isNotEmpty);
    return ButlerlyPage(
      title: HelpCopy.text(context, 'guide'),
      leading: _helpBackButton(context),
      children: [
        Text(article.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: ButlerlySpacing.section),
        for (final section in sections) ...[
          _guideSection(context, section),
          const SizedBox(height: ButlerlySpacing.standard),
        ],
      ],
    );
  }
}

Widget _guideSection(BuildContext context, String section) {
  final text = section.trim();
  if (!text.startsWith('## ')) return SelectableText(text);
  final breakAt = text.indexOf('\n');
  if (breakAt == -1) {
    return Text(
      text.substring(3),
      style: Theme.of(context).textTheme.titleMedium,
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text.substring(3, breakAt),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: ButlerlySpacing.small),
      SelectableText(text.substring(breakAt + 1).trim()),
    ],
  );
}
