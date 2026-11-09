import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

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
