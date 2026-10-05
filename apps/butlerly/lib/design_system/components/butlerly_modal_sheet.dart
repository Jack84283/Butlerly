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
          const SizedBox(height: ButlerlySheetTokens.titleContentGap),
        ],
        if (content != null)
          Flexible(child: SingleChildScrollView(child: content)),
        if (actions != null && actions!.isNotEmpty) ...[
          const SizedBox(height: ButlerlySheetTokens.contentActionsGap),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: ButlerlySheetTokens.actionGap,
            runSpacing: ButlerlySheetTokens.actionGap,
            children: actions!,
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
  Color? surfaceColor,
}) {
  final viewport = MediaQuery.sizeOf(context);
  final maxHeight = viewport.height * ButlerlySheetTokens.maxHeightFactor;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    showDragHandle: false,
    constraints: BoxConstraints(maxHeight: maxHeight),
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final bottomSheetTheme = theme.bottomSheetTheme;
      final resolvedSurfaceColor =
          surfaceColor ??
          bottomSheetTheme.modalBackgroundColor ??
          bottomSheetTheme.backgroundColor ??
          theme.colorScheme.surface;
      final shape =
          bottomSheetTheme.shape ??
          const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(ButlerlyRadius.sheet),
            ),
          );
      return Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ButlerlyLayout.contentMaxWidth(viewport),
            maxHeight: maxHeight,
          ),
          child: Material(
            key: const ValueKey('butlerly-bottom-sheet-surface'),
            color: resolvedSurfaceColor,
            elevation:
                bottomSheetTheme.elevation ?? ButlerlyElevation.bottomSheet,
            surfaceTintColor:
                bottomSheetTheme.surfaceTintColor ?? Colors.transparent,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: ButlerlySheetTokens.dragHandleVerticalPadding,
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: .4,
                      ),
                      borderRadius: BorderRadius.circular(
                        ButlerlySheetTokens.dragHandleHeight,
                      ),
                    ),
                    child: const SizedBox(
                      width: ButlerlySheetTokens.dragHandleWidth,
                      height: ButlerlySheetTokens.dragHandleHeight,
                    ),
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      ButlerlySheetTokens.horizontalPadding,
                      0,
                      ButlerlySheetTokens.horizontalPadding,
                      MediaQuery.viewInsetsOf(sheetContext).bottom +
                          ButlerlySheetTokens.bottomPadding,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Theme(
                        data: theme.copyWith(
                          dialogTheme: theme.dialogTheme.copyWith(
                            insetPadding: EdgeInsets.zero,
                          ),
                        ),
                        child: builder(sheetContext),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ButlerlyMenuEntry<T> {
  const ButlerlyMenuEntry({
    required this.label,
    this.value,
    this.isDivider = false,
  });

  const ButlerlyMenuEntry.divider()
    : label = '',
      value = null,
      isDivider = true;

  final String label;
  final T? value;
  final bool isDivider;
}

Future<T?> openButlerlyAnchoredMenu<T>({
  required BuildContext context,
  required RelativeRect position,
  required List<ButlerlyMenuEntry<T>> entries,
}) => showMenu<T>(
  context: context,
  position: position,
  items: [
    for (final entry in entries)
      if (entry.isDivider)
        const PopupMenuDivider()
      else
        PopupMenuItem<T>(value: entry.value, child: Text(entry.label)),
  ],
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
