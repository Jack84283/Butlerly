import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/contextual_pages.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AddPage extends StatelessWidget {
  const AddPage({this.onLocalFileImport, super.key});

  final Future<void> Function(BuildContext context)? onLocalFileImport;

  @override
  Widget build(BuildContext context) {
    final layoutMode = effectiveButlerlyLayoutMode(
      context,
      MediaQuery.sizeOf(context).width,
    );
    final desktop = layoutMode == ButlerlyLayoutMode.wide;
    final actions = <ButlerlyActionItem>[
      ButlerlyActionItem(
        icon: Icons.add_card_outlined,
        title: context.l10n.text('addTransactionManually'),
        subtitle: context.l10n.text('addTransactionManuallySubtitle'),
        onTap: () => context.push('/transactions/add'),
      ),
      ButlerlyActionItem(
        icon: Icons.receipt_long_outlined,
        title: context.l10n.text(
          desktop ? 'desktopAddFromReceipt' : 'addTransactionFromReceipt',
        ),
        subtitle: context.l10n.text('addTransactionFromReceiptSubtitle'),
        onTap: () => context.push('/receipts/capture'),
      ),
      ButlerlyActionItem(
        icon: Icons.document_scanner_outlined,
        title: context.l10n.text('addTransactionFromStatement'),
        subtitle: context.l10n.text('addTransactionFromStatementSubtitle'),
        onTap: () => context.push('/statements'),
      ),
      ButlerlyActionItem(
        icon: Icons.file_open_outlined,
        title: context.l10n.text(
          desktop ? 'desktopImportLocalFile' : 'addTransactionFromLocalFile',
        ),
        subtitle: context.l10n.text('addTransactionFromLocalFileSubtitle'),
        onTap: () => (onLocalFileImport ?? startLocalFileImport)(context),
      ),
    ];
    final createPaymentSource = ButlerlyActionItem(
      icon: Icons.account_balance_wallet_outlined,
      title: context.l10n.text('addPaymentSource'),
      subtitle: context.l10n.text('paymentSourcesSubtitle'),
      onTap: () => context.push('/payment-sources?create=true'),
    );

    return ButlerlyPage(
      title: context.l10n.text('add'),
      subtitle: context.l10n.text('addSubtitle'),
      fullWidth: desktop,
      children: [
        if (desktop)
          LayoutBuilder(
            key: const ValueKey('desktop-add-actions'),
            builder: (context, constraints) {
              const gap = ButlerlySpacing.cardGap;
              final columns = constraints.maxWidth >= 1100 ? 3 : 2;
              final tileWidth =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final action in [...actions, createPaymentSource])
                    SizedBox(
                      width: tileWidth,
                      child: _DesktopAddActionCard(action: action),
                    ),
                ],
              );
            },
          )
        else ...[
          ButlerlyActionGroup(actions: actions),
          ButlerlySectionHeader(title: context.l10n.text('paymentSources')),
          ButlerlyActionGroup(
            actions: [
              ButlerlyActionItem(
                icon: Icons.account_balance_wallet_outlined,
                title: context.l10n.text('paymentSources'),
                subtitle: context.l10n.text('paymentSourcesSubtitle'),
                onTap: () => context.push('/payment-sources'),
              ),
            ],
          ),
        ],
        const SizedBox(height: ButlerlySpacing.structural),
      ],
    );
  }
}

class _DesktopAddActionCard extends StatelessWidget {
  const _DesktopAddActionCard({required this.action});

  final ButlerlyActionItem action;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    onTap: action.onTap,
    semanticLabel: action.title,
    child: SizedBox(
      height: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ButlerlyActionIcon(icon: action.icon),
              const Spacer(),
              const Icon(Icons.arrow_forward_rounded),
            ],
          ),
          const Spacer(),
          Text(
            action.title,
            style: Theme.of(context).textTheme.titleMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: ButlerlySpacing.micro),
          Text(
            action.subtitle,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
  );
}
