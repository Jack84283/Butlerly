import 'package:butlerly/app/router/app_router.dart';
import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('primary shell observer invokes its pop callback', (
    tester,
  ) async {
    final controller = PrimaryShellVisibilityController();
    var popCount = 0;
    final observer = PrimaryShellNavigatorObserver(
      branchIndex: 2,
      controller: controller,
      onPop: () => popCount++,
    );

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (detailContext) => Scaffold(
                    body: FilledButton(
                      onPressed: () => Navigator.of(detailContext).pop(),
                      child: const Text('Back'),
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(popCount, 1);
  });
}
