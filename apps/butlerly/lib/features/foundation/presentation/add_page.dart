import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AddPage extends StatelessWidget {
  const AddPage({super.key});

  @override
  Widget build(BuildContext context) => ButlerlyPage(
    title: context.l10n.text('add'),
    children: [
      ButlerlyCard(
        padding: EdgeInsets.zero,
        child: ButlerlySeparatedList(
          children: [
            _AddAction(
              icon: Icons.add_card_outlined,
              label: context.l10n.text('addTransaction'),
              onTap: () => context.push('/transactions/add'),
            ),
            _AddAction(
              icon: Icons.receipt_long_outlined,
              label: context.l10n.text('scanReceipt'),
              onTap: () => context.push('/receipts/capture'),
            ),
            _AddAction(
              icon: Icons.document_scanner_outlined,
              label: context.l10n.text('scanStatement'),
              onTap: () => context.push('/statements'),
            ),
            _AddAction(
              icon: Icons.account_balance_wallet_outlined,
              label: context.l10n.text('paymentSources'),
              onTap: () => context.push('/payment-sources'),
            ),
          ],
        ),
      ),
    ],
  );
}

class _AddAction extends StatelessWidget {
  const _AddAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: ButlerlySize.preferredTarget,
    leading: Icon(icon, color: context.colors.interactive),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: onTap,
  );
}
