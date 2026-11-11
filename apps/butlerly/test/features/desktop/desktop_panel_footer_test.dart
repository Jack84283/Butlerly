import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_gold_divider.dart';
import 'package:butlerly/design_system/components/butlerly_desktop_panel_footer.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop panel footer stays fixed while its body scrolls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var presses = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          appBar: AppBar(title: const Text('Detail')),
          body: ListView(
            key: const ValueKey('desktop-panel-scrolling-body'),
            children: const [
              SizedBox(height: 1400, child: Text('Long detail content')),
            ],
          ),
          bottomNavigationBar: ButlerlyDesktopPanelFooter(
            child: Align(
              alignment: Alignment.centerRight,
              heightFactor: 1,
              child: FilledButton(
                key: const ValueKey('desktop-panel-test-save'),
                onPressed: () => presses++,
                child: const Text('Save'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final footer = find.byType(ButlerlyDesktopPanelFooter);
    final save = find.byKey(const ValueKey('desktop-panel-test-save'));
    expect(footer, findsOneWidget);
    expect(save, findsOneWidget);
    final initialRect = tester.getRect(footer);
    expect(initialRect.bottom, closeTo(700, 1));
    expect(tester.getRect(save).bottom, lessThan(initialRect.bottom));
    final divider = find.descendant(
      of: footer,
      matching: find.byType(ButlerlyDesktopGoldDivider),
    );
    expect(divider, findsOneWidget);
    expect(tester.getSize(divider).height, ButlerlyGoldAccentTokens.thickness);
    expect(tester.getRect(divider).width, tester.getRect(footer).width);
    final stripes = find.descendant(
      of: divider,
      matching: find.byType(ColoredBox),
    );
    expect(stripes, findsNWidgets(2));
    expect(
      tester.widget<ColoredBox>(stripes.at(0)).color,
      ButlerlyGoldAccentTokens.deepGold,
    );
    expect(
      tester.widget<ColoredBox>(stripes.at(1)).color,
      ButlerlyGoldAccentTokens.lightGold,
    );
    expect(tester.getSize(stripes.at(0)).height, 1);
    expect(tester.getSize(stripes.at(1)).height, 1);

    await tester.drag(
      find.byKey(const ValueKey('desktop-panel-scrolling-body')),
      const Offset(0, -550),
    );
    await tester.pumpAndSettle();
    final afterScroll = tester.getRect(footer);
    expect(afterScroll.top, closeTo(initialRect.top, 0.1));
    expect(afterScroll.bottom, closeTo(initialRect.bottom, 0.1));

    await tester.tap(save);
    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });
}
