import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/features/foundation/presentation/transactions_page.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:flutter/material.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  late Future<List<ReviewItemDto>> _items;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _items = _load();
  }

  Future<List<ReviewItemDto>> _load() async {
    final finance = _finance;
    if (finance == null) return const [];
    final result = await finance.listReviewItems();
    return switch (result) {
      ApplicationSuccess<List<ReviewItemDto>>(:final value) => value,
      ApplicationFailure<List<ReviewItemDto>>() => throw StateError(
        'Review items could not be loaded.',
      ),
    };
  }

  void _refresh() {
    final reloaded = _load();
    setState(() {
      _items = reloaded;
    });
  }

  Future<void> _close(ReviewItemDto item, {required bool dismiss}) async {
    final finance = _finance;
    if (finance == null) return;
    final result = dismiss
        ? await finance.dismissReviewIssue(item.transactionId, item.issueId)
        : await finance.resolveReviewIssue(item.transactionId, item.issueId);
    if (!mounted) return;
    if (result is ApplicationFailure<TransactionDto>) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The review issue could not be updated. Try again.'),
        ),
      );
      return;
    }
    _refresh();
  }

  Future<void> _openTransaction(ReviewItemDto item) async {
    final finance = _finance;
    if (finance == null) return;
    final result = await finance.getTransaction(item.transactionId);
    if (!mounted) return;
    if (result case ApplicationSuccess<TransactionDto>(:final value)) {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) =>
              TransactionDetailPage(finance: finance, transaction: value),
        ),
      );
      if (changed == true) _refresh();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The transaction could not be opened.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_finance == null) {
      return const _ReviewMessage(
        icon: Icons.fact_check_outlined,
        title: 'Nothing needs review right now.',
        message:
            'Review becomes available when local transaction storage is available.',
      );
    }
    return FutureBuilder<List<ReviewItemDto>>(
      future: _items,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _ReviewMessage(
            icon: Icons.error_outline,
            title: 'Review items could not be loaded',
            message: 'Your local records were not changed. Try again.',
            actionLabel: 'Try again',
            onAction: _refresh,
          );
        }
        final items = snapshot.requireData;
        if (items.isEmpty) {
          return const _ReviewMessage(
            icon: Icons.fact_check_outlined,
            title: 'Nothing needs review right now.',
            message:
                'Butlerly will show incomplete, uncertain, or conflicting records here without changing them automatically.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          itemCount: items.length + 1,
          separatorBuilder: (_, index) => index == 0
              ? const SizedBox(height: 12)
              : const Divider(height: 1),
          itemBuilder: (context, index) {
            if (index == 0) {
              return Text(
                'Review',
                style: Theme.of(context).textTheme.headlineMedium,
              );
            }
            final item = items[index - 1];
            return ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: Text(item.description ?? 'Untitled transaction'),
              subtitle: Text(item.detail ?? _reasonLabel(item.reason)),
              trailing: PopupMenuButton<_ReviewAction>(
                onSelected: (action) =>
                    _close(item, dismiss: action == _ReviewAction.dismiss),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _ReviewAction.resolve,
                    child: Text('Resolve review issue'),
                  ),
                  PopupMenuItem(
                    value: _ReviewAction.dismiss,
                    child: Text('Dismiss review issue'),
                  ),
                ],
              ),
              onTap: () => _openTransaction(item),
            );
          },
        );
      },
    );
  }
}

enum _ReviewAction { resolve, dismiss }

String _reasonLabel(String value) => switch (value) {
  'incomplete' => 'Incomplete transaction',
  'uncertain' => 'Uncertain transaction',
  'conflict' => 'Conflicting transaction details',
  'duplicateCandidate' => 'Possible duplicate',
  _ => 'Review needed',
};

class _ReviewMessage extends StatelessWidget {
  const _ReviewMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 20),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (actionLabel != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    ),
  );
}
