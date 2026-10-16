import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('full-width page spans desktop body and pinned search', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyPage(
            title: 'Transactions',
            fullWidth: true,
            pinnedHeaderExtent: ButlerlySize.minimumTarget,
            pinnedHeader: const SizedBox(
              key: ValueKey('width-test-toolbar'),
              height: ButlerlySize.minimumTarget,
            ),
            children: const [
              SizedBox(key: ValueKey('width-test-content'), height: 40),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('width-test-toolbar'))).width,
      closeTo(1600 - 2 * ButlerlySize.contentGutter, 1),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('width-test-content'))).width,
      closeTo(1600 - 2 * ButlerlySize.contentGutter, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('standard page keeps readable-width content and toolbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyPage(
            title: 'Standard',
            pinnedHeaderExtent: ButlerlySize.minimumTarget,
            pinnedHeader: const SizedBox(
              key: ValueKey('width-test-toolbar'),
              height: ButlerlySize.minimumTarget,
            ),
            children: const [
              SizedBox(key: ValueKey('width-test-content'), height: 40),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byKey(const ValueKey('width-test-toolbar'))).width,
      closeTo(ButlerlySize.pageContentMaxWidth, 1),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('width-test-content'))).width,
      closeTo(ButlerlySize.pageContentMaxWidth, 1),
    );
    expect(tester.takeException(), isNull);
  });
}
