import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/contextual_pages.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AddPage extends StatelessWidget {
  const AddPage({this.onLocalFileImport, super.key});

  final Future<void> Function(BuildContext context)? onLocalFileImport;

  @override
  Widget build(BuildContext context) => ButlerlyPage(
    title: context.l10n.text('add'),
    subtitle: context.l10n.text('addSubtitle'),
    children: [
      _AddActionGroup(
        actions: [
          _AddAction(
            icon: Icons.add_card_outlined,
            title: context.l10n.text('addTransactionManually'),
            subtitle: context.l10n.text('addTransactionManuallySubtitle'),
            onTap: () => context.push('/transactions/add'),
          ),
          _AddAction(
            icon: Icons.receipt_long_outlined,
            title: context.l10n.text('addTransactionFromReceipt'),
            subtitle: context.l10n.text('addTransactionFromReceiptSubtitle'),
            onTap: () => context.push('/receipts/capture'),
          ),
          _AddAction(
            icon: Icons.document_scanner_outlined,
            title: context.l10n.text('addTransactionFromStatement'),
            subtitle: context.l10n.text('addTransactionFromStatementSubtitle'),
            onTap: () => context.push('/statements'),
          ),
          _AddAction(
            icon: Icons.file_open_outlined,
            title: context.l10n.text('addTransactionFromLocalFile'),
            subtitle: context.l10n.text('addTransactionFromLocalFileSubtitle'),
            onTap: () => (onLocalFileImport ?? startLocalFileImport)(context),
          ),
        ],
      ),
      ButlerlySectionHeader(title: context.l10n.text('paymentSources')),
      _AddActionGroup(
        actions: [
          _AddAction(
            icon: Icons.account_balance_wallet_outlined,
            title: context.l10n.text('paymentSources'),
            subtitle: context.l10n.text('paymentSourcesSubtitle'),
            onTap: () => context.push('/payment-sources'),
          ),
        ],
      ),
      const SizedBox(height: ButlerlySpacing.structural),
    ],
  );
}

class _AddAction {
  const _AddAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _AddActionGroup extends StatelessWidget {
  const _AddActionGroup({required this.actions});

  final List<_AddAction> actions;

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.subtleSurface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
      side: BorderSide(color: context.colors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          _AddActionRow(action: actions[index]),
          if (index < actions.length - 1)
            Divider(
              height: 1,
              indent: 72,
              endIndent: ButlerlySpacing.standard,
              color: context.colors.cardDivider,
            ),
        ],
      ],
    ),
  );
}

class _AddActionRow extends StatelessWidget {
  const _AddActionRow({required this.action});

  final _AddAction action;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '${action.title}, ${action.subtitle}',
    child: InkWell(
      borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
      onTap: action.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ButlerlySpacing.standard,
          vertical: ButlerlySpacing.small,
        ),
        child: Row(
          children: [
            Container(
              width: ButlerlySize.preferredTarget,
              height: ButlerlySize.preferredTarget,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.selection,
              ),
              child: Icon(action.icon, color: context.colors.interactive),
            ),
            const SizedBox(width: ButlerlySpacing.standard),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: ButlerlySpacing.xxs),
                  Text(
                    action.subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: ButlerlySpacing.small),
            Icon(
              Icons.chevron_right_rounded,
              color: context.colors.tertiaryText,
            ),
          ],
        ),
      ),
    ),
  );
}
