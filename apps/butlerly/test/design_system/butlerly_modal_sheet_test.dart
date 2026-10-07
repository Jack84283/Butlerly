import 'dart:io';

import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production presentation code has no direct popup APIs', () {
    final offenders = <String>[];
    final productionRoot = Directory('lib');
    for (final entity in productionRoot.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('butlerly_modal_sheet.dart')) continue;
      final source = entity.readAsStringSync();
      for (final api in [
        'showModalBottomSheet',
        'showDialog',
        'AlertDialog',
        'SimpleDialog',
        'showDatePicker',
        'showTimePicker',
        'PopupMenuButton',
        'showMenu',
      ]) {
        if (source.contains(api)) offenders.add('${entity.path}: $api');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  testWidgets('date picker uses a bottom sheet and returns selected date', (
    tester,
  ) async {
    DateTime? selectedDate;
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _testApp(
        FilledButton(
          onPressed: () async {
            selectedDate = await showButlerlyDatePicker(
              context: tester.element(find.byKey(const ValueKey('open-date'))),
              title: 'Select date',
              cancelLabel: 'Cancel',
              doneLabel: 'Done',
              initialDate: DateTime(2026, 9, 15),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
          },
          key: const ValueKey('open-date'),
          child: const Text('Open date'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-date')));
    await tester.pumpAndSettle();

    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('20').last);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(selectedDate, DateTime(2026, 9, 20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('date picker cancellation leaves the value unchanged', (
    tester,
  ) async {
    DateTime? selectedDate;
    await tester.pumpWidget(
      _testApp(
        FilledButton(
          onPressed: () async {
            selectedDate = await showButlerlyDatePicker(
              context: tester.element(find.byKey(const ValueKey('open-date'))),
              title: 'Select date',
              cancelLabel: 'Cancel',
              doneLabel: 'Done',
              initialDate: DateTime(2026, 9, 15),
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
          },
          key: const ValueKey('open-date'),
          child: const Text('Open date'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(selectedDate, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long bottom-sheet content scrolls to its final action', (
    tester,
  ) async {
    var closed = false;
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _testApp(
        FilledButton(
          onPressed: () async {
            await showButlerlyBottomSheet<void>(
              context: tester.element(
                find.byKey(const ValueKey('open-long-sheet')),
              ),
              builder: (context) => ButlerlySheet(
                title: const Text('Long form'),
                content: Column(
                  children: [
                    for (var index = 0; index < 18; index++)
                      ListTile(title: Text('Field $index')),
                  ],
                ),
                actions: [
                  TextButton(
                    key: const ValueKey('long-sheet-save'),
                    onPressed: () {
                      closed = true;
                      Navigator.pop(context);
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            );
          },
          key: const ValueKey('open-long-sheet'),
          child: const Text('Open long sheet'),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-long-sheet')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final finalField = find.text('Field 17');
    await tester.scrollUntilVisible(
      finalField,
      200,
      scrollable: find.byType(Scrollable),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('long-sheet-save')));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('long-sheet-save')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sheet width follows the responsive content body and centers', (
    tester,
  ) async {
    for (final size in const [
      Size(390, 844),
      Size(800, 800),
      Size(1200, 800),
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _testApp(
          FilledButton(
            key: const ValueKey('open-width-sheet'),
            onPressed: () => showButlerlyBottomSheet<void>(
              context: tester.element(
                find.byKey(const ValueKey('open-width-sheet')),
              ),
              builder: (_) => const ButlerlySheet(
                title: Text('Width contract'),
                content: Text('Content'),
              ),
            ),
            child: const Text('Open width sheet'),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('open-width-sheet')));
      await tester.pumpAndSettle();

      final sheet = tester.getRect(
        find.byKey(const ValueKey('butlerly-bottom-sheet-surface')),
      );
      final expectedWidth = size.width < ButlerlyLayout.contentMaxWidth(size)
          ? size.width
          : ButlerlyLayout.contentMaxWidth(size);
      expect(sheet.width, closeTo(expectedWidth, 0.1));
      expect(sheet.center.dx, closeTo(size.width / 2, 0.1));

      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
    }
  });

  testWidgets('selection and confirmation sheets share outer geometry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(
        Column(
          children: [
            FilledButton(
              key: const ValueKey('open-shared-selection'),
              onPressed: () => showButlerlySelectionSheet<String>(
                context: tester.element(
                  find.byKey(const ValueKey('open-shared-selection')),
                ),
                title: 'Choose one',
                options: const [
                  ButlerlySelectionOption(value: 'one', child: Text('One')),
                ],
              ),
              child: const Text('Selection'),
            ),
            FilledButton(
              key: const ValueKey('open-shared-confirmation'),
              onPressed: () => showButlerlyConfirmationSheet(
                context: tester.element(
                  find.byKey(const ValueKey('open-shared-confirmation')),
                ),
                title: 'Confirm',
                message: 'Message',
                cancelLabel: 'Cancel',
                confirmLabel: 'Confirm',
              ),
              child: const Text('Confirmation'),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-shared-selection')));
    await tester.pumpAndSettle();
    final selectionSheet = tester.getRect(
      find.byKey(const ValueKey('butlerly-bottom-sheet-surface')),
    );
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-shared-confirmation')));
    await tester.pumpAndSettle();
    final confirmationSheet = tester.getRect(
      find.byKey(const ValueKey('butlerly-bottom-sheet-surface')),
    );
    expect(confirmationSheet.width, selectionSheet.width);
    expect(confirmationSheet.left, selectionSheet.left);
    expect(confirmationSheet.center.dx, selectionSheet.center.dx);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('selection and confirmation sheets return user choices', (
    tester,
  ) async {
    Object? selection;
    bool? confirmed;
    await tester.pumpWidget(
      _testApp(
        Column(
          children: [
            FilledButton(
              key: const ValueKey('open-selection'),
              onPressed: () async {
                selection = await showButlerlySelectionSheet<String>(
                  context: tester.element(
                    find.byKey(const ValueKey('open-selection')),
                  ),
                  title: 'Choose one',
                  selectedValue: 'first',
                  options: const [
                    ButlerlySelectionOption(
                      value: 'first',
                      child: Text('First'),
                    ),
                    ButlerlySelectionOption(
                      value: 'second',
                      child: Text('Second'),
                    ),
                  ],
                );
              },
              child: const Text('Open selection'),
            ),
            FilledButton(
              key: const ValueKey('open-confirmation'),
              onPressed: () async {
                confirmed = await showButlerlyConfirmationSheet(
                  context: tester.element(
                    find.byKey(const ValueKey('open-confirmation')),
                  ),
                  title: 'Delete item?',
                  message: 'This cannot be undone.',
                  cancelLabel: 'Cancel',
                  confirmLabel: 'Delete',
                );
              },
              child: const Text('Open confirmation'),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-selection')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Second'));
    await tester.pumpAndSettle();
    expect(selection, 'second');

    await tester.tap(find.byKey(const ValueKey('open-confirmation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('form sheet keeps actions above the keyboard inset', (
    tester,
  ) async {
    const size = Size(800, 800);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      _testApp(
        FilledButton(
          key: const ValueKey('open-keyboard-sheet'),
          onPressed: () => showButlerlyBottomSheet<void>(
            context: tester.element(
              find.byKey(const ValueKey('open-keyboard-sheet')),
            ),
            builder: (_) => ButlerlySheet(
              title: const Text('Form'),
              content: const TextField(key: ValueKey('sheet-field')),
              actions: [
                FilledButton(
                  key: const ValueKey('sheet-action'),
                  onPressed: () {},
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
          child: const Text('Open keyboard sheet'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-keyboard-sheet')));
    await tester.pumpAndSettle();

    final surface = tester.getRect(
      find.byKey(const ValueKey('butlerly-bottom-sheet-surface')),
    );
    final action = tester.getRect(find.byKey(const ValueKey('sheet-action')));
    expect(surface.width, ButlerlySize.pageContentMaxWidth);
    expect(action.bottom, lessThanOrEqualTo(size.height - 280 + 1));
  });

  testWidgets('selection sheet keeps the same structure in light and dark modes', (
    tester,
  ) async {
    Future<void> verify(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                key: const ValueKey('open-themed-selection'),
                onPressed: () => showButlerlySelectionSheet<String>(
                  context: context,
                  title: 'Choose one',
                  selectedValue: 'two',
                  options: const [
                    ButlerlySelectionOption(value: 'one', child: Text('One')),
                    ButlerlySelectionOption(value: 'two', child: Text('Two')),
                  ],
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-themed-selection')));
      await tester.pumpAndSettle();

      Finder choiceInk(String label) => find.descendant(
        of: find.ancestor(
          of: find.text(label),
          matching: find.byType(ButlerlySheetChoiceTile),
        ),
        matching: find.byWidgetPredicate(
          (widget) => widget is Ink && widget.decoration is BoxDecoration,
        ),
      );
      final oneTile = tester.widget<Ink>(choiceInk('One'));
      final twoTile = tester.widget<Ink>(choiceInk('Two'));
      final oneDecoration = oneTile.decoration! as BoxDecoration;
      final twoDecoration = twoTile.decoration! as BoxDecoration;
      expect(oneDecoration.border, isNotNull);
      expect(twoDecoration.border, isNotNull);
      expect(oneDecoration.borderRadius, twoDecoration.borderRadius);
      expect(oneDecoration.color, isNot(equals(twoDecoration.color)));
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);

      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
    }

    await verify(ThemeData.light(useMaterial3: true));
    await verify(ThemeData.dark(useMaterial3: true));
  });
}

Widget _testApp(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);
