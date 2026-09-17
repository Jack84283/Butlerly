import 'package:butlerly/app/theme/app_theme.dart';
import 'package:butlerly/design_system/components/butlerly_compact_section_selector.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('compact selector uses text buttons and reports selection', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ButlerlyCompactSectionSelector(
              labels: const ['All', 'Income', 'Expense', 'Archived'],
              selectedIndex: selected,
              onSelected: (value) => setState(() => selected = value),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('compact-section-selector'))).height,
      ButlerlySize.minimumTarget,
    );
    expect(find.byType(TextButton), findsNWidgets(4));
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('compact-section-semantics-0')),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('compact-section-semantics-2')),
          )
          .properties
          .selected,
      isFalse,
    );

    await tester.tap(find.byKey(const ValueKey('compact-section-2')));
    await tester.pump();
    expect(selected, 2);
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('compact-section-semantics-2')),
          )
          .properties
          .selected,
      isTrue,
    );
  });

  testWidgets('overflow indicators follow horizontal scroll position', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ButlerlyCompactSectionSelector(
            labels: const [
              'Categories',
              'Subcategories',
              'Tags',
              'Merchants',
              'Payment sources',
            ],
            selectedIndex: 0,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('compact-section-trailing-indicator')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compact-section-leading-indicator')),
      findsNothing,
    );

    await tester.drag(
      find.byKey(const ValueKey('compact-section-selector-scroll')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('compact-section-leading-indicator')),
      findsOneWidget,
    );
  });
}
