import 'dart:io';

import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
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
}

Widget _testApp(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);
