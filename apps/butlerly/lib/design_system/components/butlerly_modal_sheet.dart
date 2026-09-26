import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

class ButlerlySheet extends StatelessWidget {
  const ButlerlySheet({
    required this.title,
    this.content,
    this.actions,
    super.key,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          DefaultTextStyle(
            style: Theme.of(context).textTheme.headlineMedium!,
            child: title!,
          ),
          const SizedBox(height: ButlerlySpacing.section),
        ],
        if (content != null)
          Flexible(child: SingleChildScrollView(child: content)),
        if (actions != null && actions!.isNotEmpty) ...[
          const SizedBox(height: ButlerlySpacing.section),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var index = 0; index < actions!.length; index++) ...[
                if (index > 0) const SizedBox(width: ButlerlySpacing.compact),
                actions![index],
              ],
            ],
          ),
        ],
      ],
    ),
  );
}

class ButlerlySelectionOption<T> {
  const ButlerlySelectionOption({required this.value, required this.child});

  final T value;
  final Widget child;
}

Future<T?> showButlerlyBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  useSafeArea: true,
  showDragHandle: true,
  constraints: BoxConstraints(
    maxHeight: MediaQuery.sizeOf(context).height * .9,
  ),
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.fromLTRB(
      ButlerlySpacing.modalHorizontal,
      0,
      ButlerlySpacing.modalHorizontal,
      MediaQuery.viewInsetsOf(sheetContext).bottom +
          ButlerlySpacing.modalBottom,
    ),
    child: SizedBox(
      width: double.infinity,
      child: Theme(
        data: Theme.of(sheetContext).copyWith(
          dialogTheme: Theme.of(
            sheetContext,
          ).dialogTheme.copyWith(insetPadding: EdgeInsets.zero),
        ),
        child: builder(sheetContext),
      ),
    ),
  ),
);

Future<DateTime?> showButlerlyDatePicker({
  required BuildContext context,
  required String title,
  required String cancelLabel,
  required String doneLabel,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  var selected = initialDate;
  return showButlerlyBottomSheet<DateTime>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (sheetContext, setSheetState) => ButlerlySheet(
        title: Text(title),
        content: CalendarDatePicker(
          initialDate: selected,
          firstDate: firstDate,
          lastDate: lastDate,
          onDateChanged: (value) => setSheetState(() => selected = value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(sheetContext, selected),
            child: Text(doneLabel),
          ),
        ],
      ),
    ),
  );
}

Future<T?> showButlerlySelectionSheet<T>({
  required BuildContext context,
  required String title,
  T? selectedValue,
  required List<ButlerlySelectionOption<T>> options,
}) => showButlerlyBottomSheet<T>(
  context: context,
  builder: (sheetContext) => ButlerlySheet(
    title: Text(title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: option.child,
            trailing: option.value == selectedValue
                ? Icon(
                    Icons.check_rounded,
                    color: Theme.of(sheetContext).colorScheme.primary,
                  )
                : null,
            onTap: () => Navigator.pop(sheetContext, option.value),
          ),
      ],
    ),
  ),
);

Future<bool?> showButlerlyConfirmationSheet({
  required BuildContext context,
  required String title,
  required String message,
  required String cancelLabel,
  required String confirmLabel,
  bool destructive = false,
}) => showButlerlyBottomSheet<bool>(
  context: context,
  builder: (sheetContext) => ButlerlySheet(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(sheetContext, false),
        child: Text(cancelLabel),
      ),
      FilledButton(
        style: destructive
            ? FilledButton.styleFrom(
                backgroundColor: Theme.of(sheetContext).colorScheme.error,
                foregroundColor: Theme.of(sheetContext).colorScheme.onError,
              )
            : null,
        onPressed: () => Navigator.pop(sheetContext, true),
        child: Text(confirmLabel),
      ),
    ],
  ),
);
