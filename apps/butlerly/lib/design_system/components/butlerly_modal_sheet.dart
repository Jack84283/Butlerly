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
