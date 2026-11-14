import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:butlerly/features/help/data/help_catalog.dart';

/// Renders a bundled guide paragraph consistently in the full Help reader and
/// in a standalone setup/recovery overlay, without changing article contents.
Widget helpGuideSection(BuildContext context, String section) {
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

/// Local, typed links to related articles. No network access is required.
class HelpRelatedTopics extends StatelessWidget {
  const HelpRelatedTopics({
    required this.catalog,
    required this.article,
    required this.onOpen,
    super.key,
  });

  final HelpCatalog catalog;
  final HelpGuideArticle article;
  final ValueChanged<HelpGuideArticle> onOpen;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final targets = <HelpGuideArticle>[];
    for (final id in article.relatedIds.toSet()) {
      if (id == article.id) continue;
      final target = catalog.articleById(id, languageCode: language);
      if (target != null) targets.add(target);
    }
    if (targets.isEmpty) return const SizedBox.shrink();
    final heading = switch (language) {
      'zh' => '相关主题',
      'es' => 'Temas relacionados',
      _ => 'Related topics',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        Text(heading, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: ButlerlySpacing.small),
        Wrap(
          spacing: ButlerlySpacing.small,
          runSpacing: ButlerlySpacing.small,
          children: [
            for (final target in targets)
              ActionChip(
                key: ValueKey('help-related-${target.id}'),
                avatar: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: Text(target.title),
                onPressed: () => onOpen(target),
              ),
          ],
        ),
      ],
    );
  }
}
