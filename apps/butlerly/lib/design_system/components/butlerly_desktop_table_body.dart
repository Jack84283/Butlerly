import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Shared desktop table structure. Hosts retain their exact column sizing,
/// cell widgets, row actions and existing outer/inner card hierarchy.
class ButlerlyDesktopTableBody extends StatelessWidget {
  const ButlerlyDesktopTableBody({
    required this.header,
    required this.rows,
    super.key,
  });

  final Widget header;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      header,
      const SizedBox(height: ButlerlyTableTokens.headerToRowsGap),
      ButlerlyDesktopTableDivider(),
      for (final row in rows) ...[row, ButlerlyDesktopTableDivider()],
    ],
  );
}

/// A shared divider including the line beneath the final table row.
class ButlerlyDesktopTableDivider extends StatelessWidget {
  const ButlerlyDesktopTableDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
    height: ButlerlyTableTokens.dividerThickness,
    thickness: ButlerlyTableTokens.dividerThickness,
    color: ButlerlyTableTokens.dividerColor(context),
  );
}
