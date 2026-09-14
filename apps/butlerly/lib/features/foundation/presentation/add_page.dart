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
  Widget build(BuildContext context) => ButlerlyPage(
    title: context.l10n.text('add'),
    subtitle: context.l10n.text('addSubtitle'),
    children: [
      ButlerlyActionGroup(
        actions: [
          ButlerlyActionItem(
            icon: Icons.add_card_outlined,
            title: context.l10n.text('addTransactionManually'),
            subtitle: context.l10n.text('addTransactionManuallySubtitle'),
            onTap: () => context.push('/transactions/add'),
          ),
          ButlerlyActionItem(
            icon: Icons.receipt_long_outlined,
            title: context.l10n.text('addTransactionFromReceipt'),
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
            title: context.l10n.text('addTransactionFromLocalFile'),
            subtitle: context.l10n.text('addTransactionFromLocalFileSubtitle'),
            onTap: () => (onLocalFileImport ?? startLocalFileImport)(context),
          ),
        ],
      ),
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
      const SizedBox(height: ButlerlySpacing.structural),
    ],
  );
}
