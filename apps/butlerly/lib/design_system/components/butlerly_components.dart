import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_button.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_transaction_item.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

export 'butlerly_category_icon.dart';

class ButlerlyPage extends StatelessWidget {
  const ButlerlyPage({
    required this.children,
    this.title,
    this.subtitle,
    this.actions = const [],
    this.padding,
    this.controller,
    super.key,
  });

  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final EdgeInsets? padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.background,
    child: CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (title != null)
          SliverAppBar(
            pinned: true,
            title: Text(title!),
            actions: actions,
            backgroundColor: context.colors.background.withValues(alpha: 0.96),
          ),
        SliverPadding(
          padding:
              padding ??
              const EdgeInsets.fromLTRB(
                ButlerlySize.phoneGutter,
                ButlerlySpacing.standard,
                ButlerlySize.phoneGutter,
                ButlerlySpacing.large,
              ),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final extraWidth =
                  constraints.crossAxisExtent -
                  ButlerlySize.pageContentMaxWidth;
              final horizontalInset = extraWidth > 0 ? extraWidth / 2 : 0.0;
              return SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: horizontalInset),
                sliver: SliverList.list(
                  children: [
                    if (subtitle != null) ...[
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: ButlerlySpacing.section),
                    ],
                    ...children,
                  ],
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class ButlerlyCard extends StatelessWidget {
  const ButlerlyCard({
    required this.child,
    this.padding = const EdgeInsets.all(ButlerlySpacing.standard),
    this.onTap,
    this.semanticLabel,
    this.color,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color? color;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: onTap != null,
    label: semanticLabel,
    child: Card(
      color: color,
      child: InkWell(
        borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    ),
  );
}

class ButlerlySectionHeader extends StatelessWidget {
  const ButlerlySectionHeader({required this.title, this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: ButlerlySpacing.section,
      bottom: ButlerlySpacing.small,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

class ButlerlySeparatedList extends StatelessWidget {
  const ButlerlySeparatedList({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < children.length; index++) ...[
        children[index],
        if (index < children.length - 1)
          Divider(
            height: 1,
            indent: ButlerlySpacing.standard,
            endIndent: ButlerlySpacing.standard,
            color: context.colors.cardDivider,
          ),
      ],
    ],
  );
}

enum ButlerlyStatus { success, warning, error, info, neutral, review }

class ButlerlyStatusChip extends StatelessWidget {
  const ButlerlyStatusChip({
    required this.label,
    required this.status,
    this.icon,
    super.key,
  });

  final String label;
  final ButlerlyStatus status;
  final IconData? icon;

  Color _color(BuildContext context) => switch (status) {
    ButlerlyStatus.success => context.colors.success,
    ButlerlyStatus.warning => context.colors.warning,
    ButlerlyStatus.error => context.colors.error,
    ButlerlyStatus.info => context.colors.info,
    ButlerlyStatus.review => context.colors.review,
    ButlerlyStatus.neutral => context.colors.secondaryText,
  };

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return Semantics(
      label: label,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: ButlerlySize.minimumTarget,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: ButlerlySpacing.small,
          vertical: ButlerlySpacing.compact,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(ButlerlyRadius.full),
          border: Border.all(color: color.withValues(alpha: 0.65)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: color),
              const SizedBox(width: ButlerlySpacing.micro),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ButlerlyFilterButton extends StatelessWidget {
  const ButlerlyFilterButton({
    required this.label,
    required this.selected,
    required this.onPressed,
    super.key,
  });
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilterChip(
    selected: selected,
    avatar: const Icon(Icons.tune_rounded, size: 18),
    label: Text(label),
    onSelected: (_) => onPressed(),
  );
}

class ButlerlyCompactActionButton extends StatelessWidget {
  const ButlerlyCompactActionButton({
    required this.onPressed,
    required this.icon,
    required this.child,
    super.key,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    icon: Icon(icon, size: ButlerlySize.compactActionIconSize),
    label: child,
  );
}

/// Lightweight secondary text action for presentation-only affordances.
class ButlerlySecondaryTextAction extends StatelessWidget {
  const ButlerlySecondaryTextAction({
    required this.onPressed,
    required this.child,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: Theme.of(context).textButtonTheme.style?.copyWith(
      alignment: Alignment.centerLeft,
      foregroundColor: WidgetStatePropertyAll(context.colors.secondaryText),
    ),
    child: child,
  );
}

enum ButlerlyButtonBarAlignment { start, center, end }

enum ButlerlyButtonBarDensity { standard, compact }

enum ButlerlyButtonBarSpacing { standard, none }

class ButlerlyButtonBar extends StatelessWidget {
  const ButlerlyButtonBar({
    required this.children,
    this.alignment = ButlerlyButtonBarAlignment.start,
    this.density = ButlerlyButtonBarDensity.standard,
    this.spacing = ButlerlyButtonBarSpacing.standard,
    super.key,
  });

  final List<Widget> children;
  final ButlerlyButtonBarAlignment alignment;
  final ButlerlyButtonBarDensity density;
  final ButlerlyButtonBarSpacing spacing;

  WrapAlignment get _wrapAlignment => switch (alignment) {
    ButlerlyButtonBarAlignment.start => WrapAlignment.start,
    ButlerlyButtonBarAlignment.center => WrapAlignment.center,
    ButlerlyButtonBarAlignment.end => WrapAlignment.end,
  };

  @override
  Widget build(BuildContext context) {
    final bar = Padding(
      padding: EdgeInsets.only(
        top: spacing == ButlerlyButtonBarSpacing.standard
            ? ButlerlySpacing.standard
            : 0,
        bottom: spacing == ButlerlyButtonBarSpacing.standard
            ? ButlerlySpacing.standard
            : 0,
      ),
      child: Wrap(
        alignment: _wrapAlignment,
        spacing: ButlerlySpacing.compact,
        runSpacing: ButlerlySpacing.compact,
        children: children,
      ),
    );
    if (density == ButlerlyButtonBarDensity.standard) return bar;

    final theme = Theme.of(context);
    final compactPadding = const EdgeInsets.symmetric(
      horizontal: ButlerlyButtonTokens.compactHorizontalPadding,
      vertical: ButlerlyButtonTokens.compactVerticalPadding,
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: theme.filledButtonTheme.style?.copyWith(
            padding: WidgetStatePropertyAll(compactPadding),
            minimumSize: const WidgetStatePropertyAll(
              Size(
                ButlerlyButtonTokens.compactMinimumHeight,
                ButlerlyButtonTokens.compactVisualHeight,
              ),
            ),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: theme.outlinedButtonTheme.style?.copyWith(
            padding: WidgetStatePropertyAll(compactPadding),
            minimumSize: const WidgetStatePropertyAll(
              Size(
                ButlerlyButtonTokens.compactMinimumHeight,
                ButlerlyButtonTokens.compactVisualHeight,
              ),
            ),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: theme.textButtonTheme.style?.copyWith(
            padding: WidgetStatePropertyAll(compactPadding),
            minimumSize: const WidgetStatePropertyAll(
              Size(
                ButlerlyButtonTokens.compactMinimumHeight,
                ButlerlyButtonTokens.compactVisualHeight,
              ),
            ),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
      ),
      child: bar,
    );
  }
}

/// Semantic destructive action with the same geometry as the primary button.
/// The visual distinction is centralized here so screens provide only intent,
/// labels, icons, and callbacks.
class ButlerlyDestructiveButton extends StatelessWidget {
  const ButlerlyDestructiveButton({
    required this.onPressed,
    required this.child,
    this.icon,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = FilledButton.styleFrom(
      backgroundColor: colors.error,
      foregroundColor: Theme.of(context).colorScheme.onError,
      disabledBackgroundColor: colors.error.withValues(alpha: 0.35),
      disabledForegroundColor: Theme.of(
        context,
      ).colorScheme.onError.withValues(alpha: 0.7),
    );
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : FilledButton.icon(
            onPressed: onPressed,
            style: style,
            icon: icon!,
            label: child,
          );
  }
}

class ButlerlyTransactionList extends StatelessWidget {
  const ButlerlyTransactionList({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < children.length; index++) ...[
        children[index],
        if (index < children.length - 1)
          Divider(
            height: 1,
            indent: ButlerlyTransactionItemTokens.dividerInset,
            endIndent: ButlerlyTransactionItemTokens.dividerInset,
            thickness: ButlerlyTransactionItemTokens.dividerThickness,
            color: context.transactionItemDivider,
          ),
      ],
    ],
  );
}

class ButlerlyTransactionListItem extends StatelessWidget {
  const ButlerlyTransactionListItem({
    required this.title,
    required this.amount,
    required this.currency,
    this.subtitle,
    this.meta,
    this.isIncome = false,
    this.needsReview = false,
    this.possibleDuplicate = false,
    this.possibleDuplicateLabel,
    this.onPossibleDuplicateTap,
    this.selectionControl,
    this.onTap,
    this.showNavigationIndicator = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? meta;
  final String amount;
  final String currency;
  final bool isIncome;
  final bool needsReview;
  final bool possibleDuplicate;
  final String? possibleDuplicateLabel;
  final VoidCallback? onPossibleDuplicateTap;
  final Widget? selectionControl;
  final VoidCallback? onTap;
  final bool showNavigationIndicator;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label:
        '$title, $amount $currency${needsReview ? ', ${context.l10n.text('needsReview')}' : ''}'
        '${possibleDuplicate && possibleDuplicateLabel != null ? ', $possibleDuplicateLabel' : ''}',
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: ButlerlyTransactionItemTokens.minTouchHeight,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ButlerlyTransactionItemTokens.horizontalInset,
              ButlerlyTransactionItemTokens.topPadding,
              ButlerlyTransactionItemTokens.horizontalInset,
              ButlerlyTransactionItemTokens.bottomPadding,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      isIncome
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      semanticLabel: context.l10n.text(
                        isIncome ? 'income' : 'expense',
                      ),
                      size: ButlerlyTransactionItemTokens.directionIconSize,
                      color: context.transactionItemDirectionIcon(isIncome),
                    ),
                    const SizedBox(
                      width: ButlerlyTransactionItemTokens.headerSpacing,
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            '$amount $currency',
                            style: context.transactionItemAmount,
                            textHeightBehavior: ButlerlyTransactionItemTokens
                                .textHeightBehavior,
                          ),
                          if (needsReview || possibleDuplicate) ...[
                            const SizedBox(
                              width:
                                  ButlerlyTransactionItemTokens.headerSpacing,
                            ),
                            Tooltip(
                              message:
                                  possibleDuplicateLabel ??
                                  context.l10n.text('needsReview'),
                              child: Semantics(
                                container: true,
                                button: onPossibleDuplicateTap != null,
                                label:
                                    possibleDuplicateLabel ??
                                    context.l10n.text('needsReview'),
                                child: InkWell(
                                  onTap: onPossibleDuplicateTap,
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                      ButlerlySpacing.micro,
                                    ),
                                    child: Icon(
                                      Icons.warning_amber_rounded,
                                      size: ButlerlyTransactionItemTokens
                                          .warningIconSize,
                                      color: context.transactionItemWarningIcon,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (meta != null)
                      const SizedBox(
                        width: ButlerlyTransactionItemTokens.headerSpacing,
                      ),
                    if (meta != null)
                      Flexible(
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            meta!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: context.transactionItemDate,
                            textHeightBehavior: ButlerlyTransactionItemTokens
                                .textHeightBehavior,
                          ),
                        ),
                      ),
                    if (showNavigationIndicator) ...[
                      const SizedBox(
                        width: ButlerlyTransactionItemTokens.headerSpacing,
                      ),
                      ExcludeSemantics(
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size:
                              ButlerlyTransactionItemTokens.navigationIconSize,
                          color: context.transactionItemNavigationIcon,
                        ),
                      ),
                    ],
                    ?selectionControl,
                  ],
                ),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.transactionItemDescription,
                  textHeightBehavior:
                      ButlerlyTransactionItemTokens.textHeightBehavior,
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.transactionItemMetadata,
                    textHeightBehavior:
                        ButlerlyTransactionItemTokens.textHeightBehavior,
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Compact selection control for selectable transaction rows. The row itself
/// owns the accessible touch target, so the control does not inflate the
/// transaction header layout.
class ButlerlyTransactionSelectionControl<T> extends StatelessWidget {
  const ButlerlyTransactionSelectionControl({required this.value, super.key});

  final T value;

  @override
  Widget build(BuildContext context) => Radio<T>(
    value: value,
    materialTapTargetSize:
        ButlerlyTransactionItemTokens.selectionControlTapTargetSize,
    visualDensity: ButlerlyTransactionItemTokens.selectionControlDensity,
  );
}

/// Backwards-compatible name for callers not yet migrated to the common item.
class ButlerlyRecordRow extends ButlerlyTransactionListItem {
  const ButlerlyRecordRow({
    required super.title,
    required super.amount,
    required super.currency,
    super.subtitle,
    super.meta,
    super.isIncome,
    super.needsReview,
    super.possibleDuplicate,
    super.possibleDuplicateLabel,
    super.onPossibleDuplicateTap,
    super.selectionControl,
    super.onTap,
    super.showNavigationIndicator,
    super.key,
  });
}

/// Shared selection control for form fields backed by canonical values.
/// Labels are presentation-only; callers keep the selected ID/value unchanged.
class ButlerlySelectField<T> extends StatelessWidget {
  const ButlerlySelectField({
    required this.label,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.onCreate,
    this.createTooltip,
    this.onClear,
    this.clearTooltip,
    super.key,
  });

  final String label;
  final T? value;
  final List<DropdownMenuEntry<T>> entries;
  final ValueChanged<T?> onChanged;
  final VoidCallback? onCreate;
  final String? createTooltip;
  final VoidCallback? onClear;
  final String? clearTooltip;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => DropdownMenu<T>(
      initialSelection: value,
      width: constraints.maxWidth,
      menuHeight: 192,
      label: Text(label),
      trailingIcon: onCreate == null && onClear == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onCreate != null)
                  IconButton(
                    onPressed: onCreate,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: createTooltip,
                  ),
                if (onClear != null)
                  IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.clear),
                    tooltip: clearTooltip,
                  ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
      inputDecorationTheme: Theme.of(context).inputDecorationTheme,
      menuStyle: MenuStyle(
        minimumSize: WidgetStatePropertyAll(Size(constraints.maxWidth, 0)),
        maximumSize: WidgetStatePropertyAll(
          Size(constraints.maxWidth, double.infinity),
        ),
        backgroundColor: WidgetStatePropertyAll(
          Theme.of(context).colorScheme.surface,
        ),
      ),
      dropdownMenuEntries: entries,
      onSelected: onChanged,
    ),
  );
}

class ButlerlyEmptyState extends StatelessWidget {
  const ButlerlyEmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '$title. $message',
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ButlerlySize.stateContentWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.all(ButlerlySpacing.large),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: context.colors.secondaryText),
              const SizedBox(height: ButlerlySpacing.standard),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: ButlerlySpacing.compact),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: context.colors.secondaryText,
                ),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: ButlerlySpacing.section),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
              if (secondaryActionLabel != null)
                TextButton(
                  onPressed: onSecondaryAction,
                  child: Text(secondaryActionLabel!),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class ButlerlyErrorState extends StatelessWidget {
  const ButlerlyErrorState({
    required this.title,
    required this.message,
    required this.preserved,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String title;
  final String message;
  final String preserved;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => ButlerlyEmptyState(
    icon: Icons.error_outline_rounded,
    title: title,
    message: '$message\n$preserved',
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

class ButlerlyLoadingState extends StatelessWidget {
  const ButlerlyLoadingState({this.message, super.key});

  final String? message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: message,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(ButlerlySpacing.large),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (message != null) ...[
              const SizedBox(height: ButlerlySpacing.standard),
              Text(message!, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    ),
  );
}

class ButlerlyReviewCard extends StatelessWidget {
  const ButlerlyReviewCard({
    required this.title,
    required this.reason,
    required this.recommendation,
    required this.primaryLabel,
    required this.onPrimary,
    this.editLabel,
    this.dismissLabel,
    this.onEdit,
    this.onDismiss,
    super.key,
  });

  final String title;
  final String reason;
  final String recommendation;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? editLabel;
  final String? dismissLabel;
  final VoidCallback? onEdit;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.flag_outlined, color: context.colors.warning),
            const SizedBox(width: ButlerlySpacing.compact),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ],
        ),
        const SizedBox(height: ButlerlySpacing.small),
        Text(reason, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: ButlerlySpacing.small),
        Text(recommendation, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: ButlerlySpacing.standard),
        Wrap(
          spacing: ButlerlySpacing.compact,
          runSpacing: ButlerlySpacing.compact,
          children: [
            FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
            if (onEdit != null)
              OutlinedButton(
                onPressed: onEdit,
                child: Text(editLabel ?? context.l10n.text('edit')),
              ),
            if (onDismiss != null)
              TextButton(
                onPressed: onDismiss,
                child: Text(dismissLabel ?? context.l10n.text('dismiss')),
              ),
          ],
        ),
      ],
    ),
  );
}

class ButlerlySourcePreview extends StatelessWidget {
  const ButlerlySourcePreview({
    required this.title,
    required this.subtitle,
    this.onOpen,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    onTap: onOpen,
    semanticLabel: '$title, $subtitle',
    child: Row(
      children: [
        Container(
          width: ButlerlySize.sourcePreviewWidth,
          height: ButlerlySize.sourcePreviewHeight,
          decoration: BoxDecoration(
            color: context.colors.subtleSurface,
            borderRadius: BorderRadius.circular(ButlerlyRadius.small),
            border: Border.all(color: context.colors.border),
          ),
          child: Icon(
            Icons.receipt_long_outlined,
            color: context.colors.secondaryText,
          ),
        ),
        const SizedBox(width: ButlerlySpacing.standard),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: ButlerlySpacing.micro),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  );
}

class ButlerlyOfflineBanner extends StatelessWidget {
  const ButlerlyOfflineBanner({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: message,
    child: Container(
      padding: const EdgeInsets.all(ButlerlySpacing.small),
      decoration: BoxDecoration(
        color: context.colors.info.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ButlerlyRadius.standard),
        border: Border.all(color: context.colors.info.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: context.colors.info),
          const SizedBox(width: ButlerlySpacing.compact),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
