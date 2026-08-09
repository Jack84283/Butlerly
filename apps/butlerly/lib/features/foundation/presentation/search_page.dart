import 'package:flutter/material.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('Search', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 16),
      const SearchBar(
        leading: Icon(Icons.search),
        hintText: 'Search transactions and evidence',
      ),
      const SizedBox(height: 28),
      const Center(
        child: Text(
          'Search stays on this device and opens the original transaction record.',
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}
