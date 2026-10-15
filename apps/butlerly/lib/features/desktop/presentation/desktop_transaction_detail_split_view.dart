import 'dart:math' as math;

import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:flutter/material.dart';

/// Keeps an existing results page mounted while showing the *existing*
/// TransactionDetailPage to its right. Both regions scroll independently.
class DesktopTransactionDetailSplitView extends StatelessWidget {
  const DesktopTransactionDetailSplitView({
    required this.results,
    this.detail,
    super.key,
  });

  final Widget results;
  final Widget? detail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final panelWidth = math.min(
        520.0,
        math.max(350.0, constraints.maxWidth * 0.36),
      );
      return Row(
        children: [
          Expanded(child: results),
          if (detail case final selected?) ...[
            VerticalDivider(width: 1, thickness: 1, color: context.colors.cardDivider),
            SizedBox(
              key: const ValueKey('desktop-transaction-detail-panel'),
              width: panelWidth,
              child: selected,
            ),
          ],
        ],
      );
    },
  );
}
