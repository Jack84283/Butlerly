import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/help/data/help_catalog.dart';
import 'package:butlerly/features/help/presentation/help_copy.dart';
import 'package:butlerly/features/help/presentation/help_guide_section.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Three-pane Help workspace for wide viewports:
/// topic menu | guide/FAQ content list | selected detail.
/// All content is loaded from the local Help catalog.
class HelpDesktopWorkspace extends StatefulWidget {
  const HelpDesktopWorkspace({
    required this.catalog,
    this.articleId,
    super.key,
  });

  final HelpCatalog catalog;
  final String? articleId;

  @override
  State<HelpDesktopWorkspace> createState() => _HelpDesktopWorkspaceState();
}

class _HelpDesktopWorkspaceState extends State<HelpDesktopWorkspace> {
  final _searchController = TextEditingController();
  bool _showGuide = true;
  String? _category;
  String? _selectedId;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedId = widget.articleId;
  }

  @override
  void didUpdateWidget(covariant HelpDesktopWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.articleId != oldWidget.articleId) {
      _showGuide = true;
      _category = null;
      _selectedId = widget.articleId;
      _query = '';
      _searchController.clear();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectGuide({String? articleId}) {
    _searchController.clear();
    setState(() {
      _showGuide = true;
      _category = null;
      _query = '';
      _selectedId = articleId;
    });
  }

  void _selectCategory(String category) {
    _searchController.clear();
    setState(() {
      _showGuide = false;
      _category = category;
      _query = '';
      _selectedId = null;
    });
  }

  List<_HelpDesktopItem> _items(String language) {
    if (_query.trim().isNotEmpty) {
      return [
        for (final hit in widget.catalog.search(_query, languageCode: language))
          _HelpDesktopItem(
            id: hit.id,
            title: hit.title,
            subtitle: hit.snippet.replaceAll(RegExp(r'\s+'), ' ').trim(),
            article: hit.article,
            faq: hit.faq,
          ),
      ];
    }
    if (_showGuide) {
      return [
        for (final article in widget.catalog.guideForLanguage(language))
          _HelpDesktopItem(
            id: article.id,
            title: article.title,
            subtitle: article.part,
            article: article,
          ),
      ];
    }
    return [
      for (final faq in widget.catalog.faqs)
        if (_category == null || faq.category == _category)
          _HelpDesktopItem(
            id: faq.id,
            title: faq.translation(language).question,
            subtitle: HelpCopy.category(context, faq.category),
            faq: faq,
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final items = _items(language);
    _HelpDesktopItem? selected;
    for (final item in items) {
      if (item.id == _selectedId) {
        selected = item;
        break;
      }
    }
    if (selected == null && items.isNotEmpty) selected = items.first;
    final heading = _query.trim().isNotEmpty
        ? HelpCopy.text(context, 'search')
        : _showGuide
        ? HelpCopy.text(context, 'guide')
        : HelpCopy.category(context, _category ?? '');

    return Scaffold(
      key: const ValueKey('help-desktop-workspace'),
      appBar: AppBar(
        title: Text(HelpCopy.text(context, 'title')),
        leading: IconButton(
          tooltip: HelpCopy.text(context, 'back'),
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              context.go('/settings');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(ButlerlySpacing.small),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 228,
                child: Card(
                  key: const ValueKey('help-desktop-menu'),
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: ListView(
                    padding: const EdgeInsets.all(ButlerlySpacing.compact),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(ButlerlySpacing.small),
                        child: Text(
                          HelpCopy.text(context, 'topics'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      ListTile(
                        key: const ValueKey('help-desktop-menu-guide'),
                        leading: const Icon(Icons.menu_book_outlined),
                        title: Text(HelpCopy.text(context, 'guide')),
                        selected: _showGuide,
                        onTap: _selectGuide,
                      ),
                      const Divider(height: 1),
                      for (final category in widget.catalog.categories)
                        ListTile(
                          key: ValueKey('help-desktop-menu-$category'),
                          title: Text(HelpCopy.category(context, category)),
                          selected: !_showGuide && _category == category,
                          dense: true,
                          onTap: () => _selectCategory(category),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: ButlerlySpacing.small),
              Expanded(
                flex: 4,
                child: Card(
                  key: const ValueKey('help-desktop-content'),
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(ButlerlySpacing.standard),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              heading,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: ButlerlySpacing.small),
                            TextField(
                              key: const ValueKey('help-search'),
                              controller: _searchController,
                              onChanged: (value) =>
                                  setState(() => _query = value.trim()),
                              decoration: InputDecoration(
                                isDense: true,
                                labelText: HelpCopy.text(context, 'search'),
                                prefixIcon: const Icon(Icons.search_rounded),
                                border: const OutlineInputBorder(),
                                suffixIcon: _query.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: HelpCopy.text(
                                          context,
                                          'clear',
                                        ),
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _query = '');
                                        },
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: items.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(
                                    ButlerlySpacing.standard,
                                  ),
                                  child: Text(
                                    HelpCopy.text(context, 'noResults'),
                                  ),
                                ),
                              )
                            : ListView.builder(
                                key: const ValueKey('help-desktop-item-list'),
                                itemCount: items.length,
                                itemBuilder: (context, index) {
                                  final item = items[index];
                                  return ListTile(
                                    key: ValueKey(
                                      'help-desktop-item-${item.id}',
                                    ),
                                    title: Text(item.title),
                                    subtitle: Text(
                                      item.subtitle,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    selected: item.id == selected?.id,
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                    ),
                                    onTap: () =>
                                        setState(() => _selectedId = item.id),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: ButlerlySpacing.small),
              Expanded(
                flex: 6,
                child: Card(
                  key: const ValueKey('help-desktop-detail'),
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: _detail(context, selected, language),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detail(
    BuildContext context,
    _HelpDesktopItem? item,
    String language,
  ) {
    if (item == null) {
      return Center(child: Text(HelpCopy.text(context, 'noResults')));
    }
    final article = item.article;
    if (article != null) {
      return ListView(
        key: ValueKey('help-desktop-detail-${item.id}'),
        padding: const EdgeInsets.all(ButlerlySpacing.section),
        children: [
          Text(
            article.title,
            key: ValueKey('help-desktop-article-${article.id}'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: ButlerlySpacing.section),
          for (final section in article.body.split(RegExp(r'\n\s*\n')))
            if (section.trim().isNotEmpty) ...[
              helpGuideSection(context, section),
              const SizedBox(height: ButlerlySpacing.standard),
            ],
        ],
      );
    }
    final faq = item.faq!;
    final translation = faq.translation(language);
    return ListView(
      key: ValueKey('help-desktop-detail-${item.id}'),
      padding: const EdgeInsets.all(ButlerlySpacing.section),
      children: [
        Text(
          translation.question,
          key: ValueKey('help-desktop-faq-${faq.id}'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: ButlerlySpacing.section),
        SelectableText(translation.answer),
        const SizedBox(height: ButlerlySpacing.section),
        if (widget.catalog.articleById(faq.guideId, languageCode: language) !=
            null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('help-desktop-read-guide'),
              onPressed: () => _selectGuide(articleId: faq.guideId),
              icon: const Icon(Icons.menu_book_outlined),
              label: Text(HelpCopy.text(context, 'readMore')),
            ),
          ),
      ],
    );
  }
}

class _HelpDesktopItem {
  const _HelpDesktopItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.article,
    this.faq,
  });

  final String id;
  final String title;
  final String subtitle;
  final HelpGuideArticle? article;
  final HelpFaqEntry? faq;
}
