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
      _AddActionCard(
        icon: Icons.add_card_outlined,
        title: context.l10n.text('addTransactionManually'),
        subtitle: context.l10n.text('addTransactionManuallySubtitle'),
        onTap: () => context.push('/transactions/add'),
      ),
      _AddActionCard(
        icon: Icons.receipt_long_outlined,
        title: context.l10n.text('addTransactionFromReceipt'),
        subtitle: context.l10n.text('addTransactionFromReceiptSubtitle'),
        onTap: () => context.push('/receipts/capture'),
      ),
      _AddActionCard(
        icon: Icons.document_scanner_outlined,
        title: context.l10n.text('addTransactionFromStatement'),
        subtitle: context.l10n.text('addTransactionFromStatementSubtitle'),
        onTap: () => context.push('/statements'),
      ),
      _AddActionCard(
        icon: Icons.file_open_outlined,
        title: context.l10n.text('addTransactionFromLocalFile'),
        subtitle: context.l10n.text('addTransactionFromLocalFileSubtitle'),
        onTap: () => context.push('/import-export'),
      ),
      _AddActionCard(
        icon: Icons.account_balance_wallet_outlined,
        title: context.l10n.text('paymentSources'),
        subtitle: context.l10n.text('paymentSourcesSubtitle'),
        onTap: () => context.push('/payment-sources'),
      ),
    ],
  );
}

class _AddActionCard extends StatelessWidget {
  const _AddActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
    child: ButlerlyCard(
      onTap: onTap,
      semanticLabel: '$title, $subtitle',
      child: Row(
        children: [
          Icon(icon, color: context.colors.interactive),
          const SizedBox(width: ButlerlySpacing.standard),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyLarge),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: ButlerlySpacing.small),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    ),
  );
}
