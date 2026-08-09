import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        _HomeHeader(),
        SizedBox(height: 24),
        _ActionPanel(),
        SizedBox(height: 24),
        _EmptyHomeState(),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Home', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const Text('Your private financial record, stored on this device.'),
    ],
  );
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start with a record',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('Add your first transaction when you are ready.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => context.go('/transactions'),
            icon: const Icon(Icons.add),
            label: const Text('Add transaction'),
          ),
        ],
      ),
    ),
  );
}

class _EmptyHomeState extends StatelessWidget {
  const _EmptyHomeState();

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.inbox_outlined, size: 40),
          const SizedBox(height: 12),
          Text(
            'Nothing needs attention',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Transactions and review items will appear here as you add records.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
