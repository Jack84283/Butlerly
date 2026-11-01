import 'package:butlerly/design_system/category/butlerly_category_identity.dart';
import 'package:butlerly/design_system/components/butlerly_category_icon.dart';
import 'package:butlerly/design_system/components/butlerly_content_surface.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:butlerly/design_system/theme/butlerly_button_palette.dart';
import 'package:butlerly/design_system/theme/butlerly_responsive_design_tokens.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_button.dart';
import 'package:butlerly/design_system/tokens/butlerly_category_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/design_system/tokens/butlerly_transaction_item.dart';
import 'package:butlerly/design_system/tokens/butlerly_typography.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

export 'butlerly_category_icon.dart';
export 'butlerly_content_surface.dart';

class ButlerlyPinnedPageSpacing {
  const ButlerlyPinnedPageSpacing({
    this.headerBottomGap = ButlerlySpacing.none,
    this.pinnedTopGap = ButlerlySpacing.none,
    this.pinnedBottomGap = ButlerlySpacing.none,
    this.bodyTopGap,
  });

  static const defaults = ButlerlyPinnedPageSpacing();

  static const primary = ButlerlyPinnedPageSpacing(
    headerBottomGap: ButlerlySpacing.pinnedPageHeaderBottomGap,
    pinnedTopGap: ButlerlySpacing.pinnedPageTopGap,
    pinnedBottomGap: ButlerlySpacing.pinnedPageBottomGap,
    bodyTopGap: ButlerlySpacing.pinnedPageBodyTopGap,
  );

  static const tightHeader = ButlerlyPinnedPageSpacing(
    headerBottomGap: ButlerlySpacing.none,
    pinnedTopGap: ButlerlySpacing.pinnedPageTopGap,
    pinnedBottomGap: ButlerlySpacing.pinnedPageBottomGap,
    bodyTopGap: ButlerlySpacing.pinnedPageBodyTopGap,
  );

  final double headerBottomGap;
  final double pinnedTopGap;
  final double pinnedBottomGap;
  final double? bodyTopGap;
}

class ButlerlyPage extends StatelessWidget {
  const ButlerlyPage({
    required this.children,
    this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.padding,
    this.controller,
    this.pinnedHeader,
    this.pinnedHeaderExtent = ButlerlySize.minimumTarget,
    this.pinnedSpacing = ButlerlyPinnedPageSpacing.defaults,
    this.onRefresh,
    this.refreshKey,
    this.fullWidth = false,
    super.key,
  });

  final String? title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;
  final List<Widget> children;
  final EdgeInsets? padding;
  final ScrollController? controller;
  final Widget? pinnedHeader;
  final double pinnedHeaderExtent;
  final ButlerlyPinnedPageSpacing pinnedSpacing;
  final RefreshCallback? onRefresh;
  final Key? refreshKey;

  /// Use the available page width instead of the standard readable-width cap.
  /// Only opt in from layouts designed for full-width content.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final contentPadding =
        padding ??
        EdgeInsets.fromLTRB(
          ButlerlySize.contentGutter,
          pinnedSpacing.bodyTopGap ?? ButlerlySpacing.standard,
          ButlerlySize.contentGutter,
          ButlerlySpacing.large,
        );
    final useCupertinoRefresh =
        onRefresh != null &&
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS;
    final toolbarHeight = title == null ? 0.0 : ButlerlySize.pageToolbarHeight;
    final appBarHeight =
        toolbarHeight +
        (title == null ? ButlerlySpacing.none : pinnedSpacing.headerBottomGap);
    final pinnedHeaderHeight = pinnedHeader == null
        ? ButlerlySpacing.none
        : pinnedHeaderExtent +
              pinnedSpacing.pinnedTopGap +
              pinnedSpacing.pinnedBottomGap;
    final refreshEdgeOffset = appBarHeight + pinnedHeaderHeight;

    final content = ButlerlyContentCanvas(
      canvasKey: const ValueKey('butlerly-page-canvas'),
      child: CustomScrollView(
        controller: controller,
        physics: useCupertinoRefresh
            ? const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              )
            : const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (title != null)
            SliverAppBar(
              pinned: true,
              toolbarHeight: toolbarHeight,
              title: Text(title!),
              leading: leading,
              actions: actions,
              bottom: pinnedSpacing.headerBottomGap > ButlerlySpacing.none
                  ? PreferredSize(
                      preferredSize: Size.fromHeight(
                        pinnedSpacing.headerBottomGap,
                      ),
                      child: SizedBox(height: pinnedSpacing.headerBottomGap),
                    )
                  : null,
              backgroundColor: context.colors.background,
            ),
          if (pinnedHeader != null)
            SliverPersistentHeader(
              pinned: true,
              delegate: _ButlerlyPinnedHeaderDelegate(
                child: pinnedHeader!,
                extent: pinnedHeaderExtent,
                topGap: pinnedSpacing.pinnedTopGap,
                bottomGap: pinnedSpacing.pinnedBottomGap,
                fullWidth: fullWidth,
              ),
            ),
          if (useCupertinoRefresh)
            CupertinoSliverRefreshControl(
              key: refreshKey,
              onRefresh: onRefresh,
            ),
          ButlerlySliverContentSurface(
            surfaceKey: const ValueKey('butlerly-page-content-surface'),
            surfaceHorizontalPadding: contentPadding.horizontal,
            fullWidth: fullWidth,
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverPadding(
                  padding: contentPadding,
                  sliver: SliverList.list(
                    key: const ValueKey('butlerly-page-content-sliver'),
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
                ),
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: SizedBox.shrink(
                    key: ValueKey('butlerly-page-content-filler'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onRefresh == null || useCupertinoRefresh) return content;

    return RefreshIndicator(
      key: refreshKey,
      onRefresh: onRefresh!,
      edgeOffset: refreshEdgeOffset,
      displacement:
          refreshEdgeOffset + ButlerlySize.refreshIndicatorDisplacement,
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      child: content,
    );
  }
}

class _ButlerlyPinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ButlerlyPinnedHeaderDelegate({
    required this.child,
    required this.extent,
    required this.topGap,
    required this.bottomGap,
    required this.fullWidth,
  });

  final Widget child;
  final double extent;
  final double topGap;
  final double bottomGap;
  final bool fullWidth;

  @override
  double get minExtent => extent + topGap + bottomGap;

  @override
  double get maxExtent => extent + topGap + bottomGap;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: context.colors.background,
    child: Padding(
      padding: EdgeInsets.only(top: topGap, bottom: bottomGap),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ButlerlySize.contentGutter,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: fullWidth
                  ? double.infinity
                  : ButlerlyLayout.contentMaxWidth(MediaQuery.sizeOf(context)),
            ),
            child: SizedBox(width: double.infinity, child: child),
          ),
        ),
      ),
    ),
  );

  @override
  bool shouldRebuild(covariant _ButlerlyPinnedHeaderDelegate oldDelegate) =>
      oldDelegate.child != child ||
      oldDelegate.extent != extent ||
      oldDelegate.topGap != topGap ||
      oldDelegate.bottomGap != bottomGap ||
      oldDelegate.fullWidth != fullWidth;
}

enum ButlerlyCardVariant { standard, dashboard }

class ButlerlyCard extends StatelessWidget {
  const ButlerlyCard({
    required this.child,
    this.padding = const EdgeInsets.all(ButlerlySpacing.cardPadding),
    this.onTap,
    this.semanticLabel,
    this.color,
    this.variant = ButlerlyCardVariant.standard,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final Color? color;
  final ButlerlyCardVariant variant;

  @override
  Widget build(BuildContext context) {
    final radius = ButlerlyRadius.card;
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticLabel,
      child: Card(
        color: color,
        child: Ink(
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Responsive title row shared by semantic cards across Butlerly surfaces.
class ButlerlyCardHeader extends StatelessWidget {
  const ButlerlyCardHeader({
    required this.title,
    this.subtitle,
    this.action,
    this.titleStyle,
    this.subtitleStyle,
    this.subtitleGap = ButlerlySpacing.micro,
    this.keepActionInlineAtCompactWidth = false,
    this.centerAction = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  /// Space between title and optional subtitle; defaults to existing styling.
  final double subtitleGap;
  final bool keepActionInlineAtCompactWidth;
  final bool centerAction;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          MediaQuery.textScalerOf(context).scale(14) > 20 ||
          (!keepActionInlineAtCompactWidth && constraints.maxWidth < 280) ||
          // Inactive branches can briefly receive a very narrow layout while
          // an adaptive route is being rebuilt. Keep the action reachable
          // without allowing the inline row to report a RenderFlex overflow.
          constraints.maxWidth < 160;
      final titleBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                titleStyle ??
                ButlerlyTypography.compactCardTitle(
                  Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
                ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: subtitleGap),
            Text(
              subtitle!,
              style:
                  subtitleStyle ??
                  ButlerlyTypography.cardSubtitle(
                    Theme.of(context).textTheme.bodySmall ?? const TextStyle(),
                  ),
            ),
          ],
        ],
      );
      if (action == null) return titleBlock;
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleBlock,
            const SizedBox(height: ButlerlySpacing.compact),
            Align(alignment: AlignmentDirectional.centerEnd, child: action),
          ],
        );
      }
      final inlineAction = centerAction
          ? Align(
              alignment: AlignmentDirectional.topEnd,
              widthFactor: 1,
              heightFactor: 1,
              child: action,
            )
          : action!;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: titleBlock),
          inlineAction,
        ],
      );
    },
  );
}

/// Shared Add action for page headers on desktop and device layouts.
///
/// The filled 32px circular icon and trailing inset match Master Data's
/// established design. Hosts supply only the tooltip and action.
class ButlerlyHeaderAddButton extends StatelessWidget {
  const ButlerlyHeaderAddButton({
    required this.label,
    required this.onPressed,
    this.buttonKey,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(
      end: ButlerlySpacing.headerActionTrailing,
    ),
    child: IconButton.filled(
      key: buttonKey,
      tooltip: label,
      onPressed: onPressed,
      icon: const Icon(Icons.add),
      style: IconButton.styleFrom(
        backgroundColor: context.colors.interactive,
        foregroundColor: context.colors.interactive.computeLuminance() > 0.5
            ? context.colors.background
            : Colors.white,
        shape: const CircleBorder(),
        minimumSize: const Size.square(32),
        maximumSize: const Size.square(32),
      ),
    ),
  );
}

/// Compact icon action shared by desktop Master Data and Rules tables.
///
/// A 24px button with a 16px glyph uses the same density and spacing in
/// both tables. These controls are intentionally desktop-only; device rows
/// keep their normal touch targets.
class ButlerlyDesktopTableIconAction extends StatelessWidget {
  const ButlerlyDesktopTableIconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.buttonKey,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) => IconButton(
    key: buttonKey,
    constraints: const BoxConstraints.tightFor(width: 24, height: 24),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    iconSize: 16,
    tooltip: tooltip,
    icon: Icon(icon),
    onPressed: onPressed,
  );
}

/// Icon-only action without a filled surface or border in either theme.
///
/// Explicitly overrides the app-wide bordered text button theme while
/// preserving the standard 44px accessible touch target.
class ButlerlyTransparentIconButton extends StatelessWidget {
  const ButlerlyTransparentIconButton({
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.buttonKey,
    this.iconSize = ButlerlyButtonTokens.iconSize,
    this.alignment = Alignment.center,
    super.key,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Key? buttonKey;
  final double iconSize;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: semanticLabel,
    child: Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      child: TextButton(
        key: buttonKey,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: context.colors.secondaryText,
          disabledForegroundColor: context.colors.tertiaryText,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          side: BorderSide.none,
          alignment: alignment,
          fixedSize: const Size.square(ButlerlySize.minimumTarget),
          minimumSize: const Size.square(ButlerlySize.minimumTarget),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: SizedBox.square(
          dimension: ButlerlySize.minimumTarget,
          child: Align(
            alignment: alignment,
            child: Icon(icon, size: iconSize),
          ),
        ),
      ),
    ),
  );
}

/// Shared compact outlined or transparent selector used by dashboard controls.
///
/// The selector keeps its visual treatment independent of the field's meaning
/// while callers provide the localized label and action. Its outer size is a
/// touch target while the bordered surface remains compact.
class ButlerlyCompactSelector extends StatelessWidget {
  const ButlerlyCompactSelector({
    required this.label,
    this.onPressed,
    this.semanticLabel,
    this.buttonKey,
    this.alignVisualEnd = false,
    this.denseSurface = false,
    this.transparent = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final Key? buttonKey;
  final bool alignVisualEnd;
  final bool denseSurface;
  final bool transparent;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    button: onPressed != null,
    enabled: onPressed != null,
    label: semanticLabel ?? label,
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: ButlerlyButtonTokens.iconTouchTarget,
      ),
      child: TextButton(
        key: buttonKey,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: transparent
              ? context.colors.secondaryText
              : context.colors.primaryText,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          minimumSize: const Size(
            ButlerlyButtonTokens.minimumWidth,
            ButlerlyButtonTokens.iconTouchTarget,
          ),
          side: BorderSide.none,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: SizedBox(
          height: alignVisualEnd ? ButlerlySize.minimumTarget : null,
          child: Align(
            alignment: alignVisualEnd
                ? AlignmentDirectional.topEnd
                : Alignment.topCenter,
            child: Ink(
              decoration: BoxDecoration(
                color: transparent
                    ? Colors.transparent
                    : context.colors.subtleSurface,
                border: Border.all(color: context.colors.border),
                borderRadius: BorderRadius.circular(ButlerlyRadius.pill),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ButlerlySpacing.compact,
                  vertical: denseSurface
                      ? ButlerlySpacing.none
                      : ButlerlySpacing.nanoSmall,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        softWrap: true,
                        textAlign: TextAlign.end,
                        style: ButlerlyTypography.cardAction(
                          Theme.of(context).textTheme.titleMedium ??
                              const TextStyle(),
                        ),
                      ),
                    ),
                    const SizedBox(width: ButlerlySpacing.micro),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: ButlerlyButtonTokens.iconSize,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shared container for chart content with a semantic title and consistent
/// title-to-visual spacing. Chart-specific geometry remains owned by the
/// visualization inside the card.
class ButlerlyVisualizationCard extends StatelessWidget {
  const ButlerlyVisualizationCard({
    required this.title,
    required this.child,
    this.semanticLabel,
    this.fillAvailableHeight = false,
    super.key,
  });

  final String title;
  final Widget child;
  final String? semanticLabel;

  /// Stretch the body beneath the header in a height-constrained card.
  /// Unbounded/mobile layouts continue to size naturally.
  final bool fillAvailableHeight;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    semanticLabel: semanticLabel ?? title,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final fill = fillAvailableHeight && constraints.hasBoundedHeight;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ButlerlyCardHeader(title: title),
            const SizedBox(height: ButlerlySpacing.small),
            if (fill) Expanded(child: child) else child,
          ],
        );
      },
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

class ButlerlyKeyValueRow extends StatelessWidget {
  const ButlerlyKeyValueRow({
    required this.label,
    required this.value,
    this.padding = const EdgeInsets.only(bottom: ButlerlySpacing.micro),
    super.key,
  }) : valueWidget = null;

  const ButlerlyKeyValueRow.widget({
    required this.label,
    required this.valueWidget,
    this.padding = const EdgeInsets.only(bottom: ButlerlySpacing.micro),
    super.key,
  }) : value = null;

  final String label;
  final String? value;
  final Widget? valueWidget;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: ButlerlySpacing.standard),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: valueWidget ?? Text(value!, textAlign: TextAlign.right),
          ),
        ),
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
  Widget build(BuildContext context) {
    final palette = ButlerlyButtonPalette.resolve(
      colors: context.colors,
      brightness: Theme.of(context).brightness,
    );
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: palette.compactFill,
        foregroundColor: palette.compactText,
        side: BorderSide(color: palette.compactBorder),
      ),
      icon: Icon(icon, size: ButlerlySize.compactActionIconSize),
      label: child,
    );
  }
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
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      side: const WidgetStatePropertyAll(BorderSide.none),
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
                ButlerlyButtonTokens.minimumWidth,
                ButlerlyButtonTokens.height,
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
                ButlerlyButtonTokens.minimumWidth,
                ButlerlyButtonTokens.height,
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
                ButlerlyButtonTokens.minimumWidth,
                ButlerlyButtonTokens.height,
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
    final palette = ButlerlyButtonPalette.resolve(
      colors: colors,
      brightness: Theme.of(context).brightness,
    );
    final style = FilledButton.styleFrom(
      backgroundColor: palette.destructiveFill,
      foregroundColor: palette.destructiveText,
      side: BorderSide(color: palette.destructiveBorder),
      disabledBackgroundColor: colors.error.withValues(alpha: 0.08),
      disabledForegroundColor: colors.tertiaryText,
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
            indent: context.designTokens.transactionGeometry.dividerInset,
            endIndent: context.designTokens.transactionGeometry.dividerInset,
            thickness:
                context.designTokens.transactionGeometry.dividerThickness,
            color: context.transactionItemDivider,
          ),
      ],
    ],
  );
}

/// Canonical category badge used by transaction rows and other record surfaces.
///
/// The badge intentionally uses the full category label, a compact text role,
/// and the category's brighter identity color. It may wrap when necessary
/// rather than truncating the category name.
class ButlerlyCategoryBadge extends StatelessWidget {
  const ButlerlyCategoryBadge({
    required this.label,
    this.categoryId,
    this.customColorId,
    super.key,
  });

  final String label;
  final String? categoryId;
  final ButlerlyCategoryColorId? customColorId;

  @override
  Widget build(BuildContext context) {
    final identity = categoryId == null
        ? null
        : ButlerlyCategoryIdentity.forBuiltInId(categoryId!) ??
              (customColorId == null
                  ? null
                  : ButlerlyCategoryIdentity.custom(
                      categoryId: categoryId!,
                      categoryColorId: customColorId!,
                    ));
    final categoryColor = identity == null
        ? ButlerlyChartColors.category(categoryId ?? label)
        : ButlerlyCategoryColors.color(identity.categoryColorId);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final backgroundOpacity = dark
        ? ButlerlyTransactionItemTokens.categoryBadgeBackgroundOpacityDark
        : ButlerlyTransactionItemTokens.categoryBadgeBackgroundOpacityLight;
    final borderOpacity = dark
        ? ButlerlyTransactionItemTokens.categoryBadgeBorderOpacityDark
        : ButlerlyTransactionItemTokens.categoryBadgeBorderOpacityLight;
    final badgeBackground = categoryColor.withValues(alpha: backgroundOpacity);
    final compositedBackground = Color.alphaBlend(
      badgeBackground,
      context.colors.cardSurface,
    );
    var foreground = categoryColor;
    for (final candidate in [
      context.colors.primaryText,
      Colors.white,
      Colors.black,
    ]) {
      if (_contrastRatio(candidate, compositedBackground) >
          _contrastRatio(foreground, compositedBackground)) {
        foreground = candidate;
      }
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: badgeBackground,
        border: Border.all(
          color: categoryColor.withValues(alpha: borderOpacity),
        ),
        borderRadius: BorderRadius.circular(ButlerlyRadius.full),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal:
              context.designTokens.transactionGeometry.badgeHorizontalPadding,
          vertical:
              context.designTokens.transactionGeometry.badgeVerticalPadding,
        ),
        child: Text(
          label,
          softWrap: true,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: foreground,
            fontSize: context.designTokens.transactionTypography.badge,
            height: context.designTokens.transactionTypography.badgeLineHeight,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

enum ButlerlyTransactionRowVariant { standard, dashboard }

class ButlerlyTransactionListItem extends StatelessWidget {
  const ButlerlyTransactionListItem({
    required this.title,
    required this.amount,
    required this.currency,
    this.subtitle,
    this.meta,
    this.categoryId,
    this.categoryColorId,
    this.categoryLabel,
    this.subcategoryLabel,
    this.paymentSource,
    this.paymentSourceMark,
    this.tags = const [],
    this.supportingContent,
    this.showDate = false,
    this.isIncome = false,
    this.needsReview = false,
    this.possibleDuplicate = false,
    this.possibleDuplicateLabel,
    this.onPossibleDuplicateTap,
    this.selectionControl,
    this.onTap,
    this.showNavigationIndicator = false,
    this.showCategoryPill = false,
    this.amountIncludesCurrency = false,
    this.compactSpacing = false,
    this.variant = ButlerlyTransactionRowVariant.standard,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? meta;
  final String? categoryId;
  final ButlerlyCategoryColorId? categoryColorId;
  final String? categoryLabel;
  final String? subcategoryLabel;
  final String? paymentSource;
  final String? paymentSourceMark;
  final List<String> tags;
  final Widget? supportingContent;
  final bool showDate;
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
  final bool showCategoryPill;
  final bool amountIncludesCurrency;
  final bool compactSpacing;
  final ButlerlyTransactionRowVariant variant;

  EdgeInsets _rowPadding(BuildContext context) => EdgeInsets.fromLTRB(
    context.designTokens.transactionGeometry.horizontalInset,
    compactSpacing
        ? context.designTokens.transactionGeometry.compactFirstRowTopPadding
        : context.designTokens.transactionGeometry.verticalPadding,
    context.designTokens.transactionGeometry.horizontalInset,
    context.designTokens.transactionGeometry.verticalPadding,
  );

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label:
        '$title, ${amountIncludesCurrency ? (isIncome ? '+' : '-') : '$amount $currency'}${amountIncludesCurrency ? amount : ''}${_semanticClassification.isEmpty ? '' : ', $_semanticClassification'}'
        '${needsReview ? ', ${context.l10n.text('needsReview')}' : ''}'
        '${possibleDuplicate && possibleDuplicateLabel != null ? ', $possibleDuplicateLabel' : ''}',
    child:
        categoryLabel != null ||
            categoryId != null ||
            paymentSource != null ||
            tags.isNotEmpty
        ? _buildCanonical(context)
        : _buildLegacy(context),
  );

  String get _semanticClassification {
    final values = <String>[];
    if (categoryLabel?.trim().isNotEmpty == true) {
      values.add(categoryLabel!.trim());
    }
    if (subcategoryLabel?.trim().isNotEmpty == true) {
      values.add(subcategoryLabel!.trim());
    }
    if (variant == ButlerlyTransactionRowVariant.dashboard &&
        paymentSource?.trim().isNotEmpty == true) {
      values.add(paymentSource!.trim());
    }
    if (showDate && meta?.trim().isNotEmpty == true) {
      values.add(meta!.trim());
    }
    return values.join(', ');
  }

  Widget _buildCanonical(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: context.designTokens.transactionGeometry.minimumRowHeight,
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: _rowPadding(context),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: ButlerlyTransactionItemTokens.categoryIconLeadingInset,
                  top: ButlerlyTransactionItemTokens.leadingIconTopInset,
                ),
                child: categoryId != null
                    ? ButlerlyCategoryIcon(
                        key: const Key('transaction-leading-icon'),
                        categoryId: categoryId!,
                        customColorId: categoryColorId,
                        semanticLabel: categoryLabel,
                        containerSize:
                            ButlerlyTransactionItemTokens.leadingIconSize,
                        glyphSize:
                            ButlerlyTransactionItemTokens.leadingIconGlyphSize,
                      )
                    : const _NeutralTransactionIcon(),
              ),
              const SizedBox(
                width: ButlerlyTransactionItemTokens.leadingToContentSpacing,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_dashboardReflows(context))
                      _dashboardHeader(context)
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _titleInHeader(context)),
                          const SizedBox(
                            width: ButlerlyTransactionItemTokens
                                .titleAmountSpacing,
                          ),
                          Flexible(
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: _signedAmount(context),
                            ),
                          ),
                          if (showNavigationIndicator)
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: ButlerlySpacing.compact,
                              ),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: context.colors.tertiaryText,
                              ),
                            ),
                        ],
                      ),
                    if (showCategoryPill &&
                        categoryLabel?.trim().isNotEmpty == true)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: ButlerlyTransactionItemTokens.headerSpacing,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _categoryPill(),
                        ),
                      ),
                    if (_hasMetadata) ...[
                      const SizedBox(
                        height: ButlerlyTransactionItemTokens.headerSpacing,
                      ),
                      _metadataText(context),
                    ],
                    if (showDate && meta != null)
                      Padding(
                        padding: EdgeInsets.only(
                          top:
                              _hasMetadata ||
                                  (showCategoryPill &&
                                      categoryLabel?.trim().isNotEmpty == true)
                              ? ButlerlyTransactionItemTokens.metadataSpacing
                              : ButlerlyTransactionItemTokens.headerSpacing,
                        ),
                        child: Text(
                          meta!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.start,
                          style: context.transactionItemDate,
                        ),
                      ),
                    if (_visibleTags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: ButlerlyTransactionItemTokens.metadataSpacing,
                        ),
                        child: Text(
                          _visibleTags.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.transactionItemMetadata,
                        ),
                      ),
                    if (supportingContent case final content?)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: ButlerlySpacing.compact,
                        ),
                        child: content,
                      )
                    else if (variant !=
                            ButlerlyTransactionRowVariant.dashboard &&
                        (needsReview || possibleDuplicate))
                      _duplicateWarning(context),
                  ],
                ),
              ),
              ?selectionControl,
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildLegacy(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minHeight: context.designTokens.transactionGeometry.minimumRowHeight,
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: _rowPadding(context),
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
                          amountIncludesCurrency
                              ? '${isIncome ? '+' : '-'}$amount'
                              : '$amount $currency',
                          style: context.transactionItemAmount,
                          textHeightBehavior:
                              ButlerlyTransactionItemTokens.textHeightBehavior,
                        ),
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
                          textHeightBehavior:
                              ButlerlyTransactionItemTokens.textHeightBehavior,
                        ),
                      ),
                    ),
                  if (showNavigationIndicator)
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: context.colors.tertiaryText,
                    ),
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
              if (variant != ButlerlyTransactionRowVariant.dashboard &&
                  (needsReview || possibleDuplicate))
                _duplicateWarning(context),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _title(BuildContext context) => Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.transactionItemDescription,
    textHeightBehavior: ButlerlyTransactionItemTokens.textHeightBehavior,
  );

  bool _dashboardReflows(BuildContext context) =>
      variant == ButlerlyTransactionRowVariant.dashboard &&
      MediaQuery.textScalerOf(context).scale(14) > 20;

  Widget _titleInHeader(BuildContext context) => _title(context);

  Widget _dashboardHeader(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _titleInHeader(context),
      const SizedBox(height: ButlerlySpacing.micro),
      Row(
        children: [
          Flexible(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: _signedAmount(context),
            ),
          ),
          if (showNavigationIndicator) _navigationIndicator(context),
        ],
      ),
    ],
  );

  Widget _navigationIndicator(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: ButlerlySpacing.compact),
    child: Icon(
      Icons.chevron_right_rounded,
      size: 20,
      color: context.colors.tertiaryText,
    ),
  );

  Widget _categoryPill() => ButlerlyCategoryBadge(
    categoryId: categoryId,
    customColorId: categoryColorId,
    label: categoryLabel!,
  );

  Widget _metadataText(BuildContext context) {
    final categoryDetails = _categoryMetadataParts.join(' · ');
    final sourceLabel = paymentSource?.trim();
    final hasSource = sourceLabel != null && sourceLabel.isNotEmpty;

    if (context.designTokens.mode == ButlerlyLayoutMode.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (categoryDetails.isNotEmpty)
            _metadataLabel(context, categoryDetails),
          if (hasSource)
            Padding(
              padding: EdgeInsets.only(
                top: categoryDetails.isEmpty
                    ? ButlerlySpacing.none
                    : ButlerlyTransactionItemTokens.metadataSpacing,
              ),
              child: _paymentSourceLine(context, sourceLabel),
            ),
        ],
      );
    }

    return Row(
      children: [
        if (categoryDetails.isNotEmpty)
          Flexible(
            child: _metadataLabel(
              context,
              hasSource ? '$categoryDetails ·' : categoryDetails,
            ),
          ),
        if (hasSource) ...[
          if (categoryDetails.isNotEmpty)
            const SizedBox(width: ButlerlySpacing.micro),
          Flexible(child: _paymentSourceLine(context, sourceLabel)),
        ],
      ],
    );
  }

  Widget _metadataLabel(BuildContext context, String label) => Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: context.transactionItemMetadata,
    textHeightBehavior: ButlerlyTransactionItemTokens.textHeightBehavior,
  );

  Widget _paymentSourceLine(BuildContext context, String label) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final icon = ButlerlyPaymentMarkIcon(
            mark: paymentSourceMark ?? 'other',
            size: 18,
          );
          if (constraints.hasBoundedWidth && constraints.maxWidth <= 18) {
            return SizedBox(
              key: const ValueKey('transaction-row-payment-source'),
              width: 18,
              height: 18,
              child: icon,
            );
          }
          return Row(
            key: const ValueKey('transaction-row-payment-source'),
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(width: ButlerlySpacing.micro),
              Flexible(child: _metadataLabel(context, label)),
            ],
          );
        },
      );

  Widget _signedAmount(BuildContext context) => Text(
    amountIncludesCurrency
        ? '${isIncome ? '+' : '-'}$amount'
        : '${isIncome ? '+' : '−'}$amount $currency',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: TextAlign.end,
    style: context.transactionItemAmount.copyWith(
      color: isIncome
          ? context.colors.success
          : variant == ButlerlyTransactionRowVariant.dashboard
          ? context.colors.error
          : null,
    ),
    textHeightBehavior: ButlerlyTransactionItemTokens.textHeightBehavior,
  );

  List<String> get _categoryMetadataParts => [
    if (!showCategoryPill &&
        categoryLabel != null &&
        categoryLabel!.trim().isNotEmpty)
      categoryLabel!.trim(),
    if (subcategoryLabel case final value?
        when value.trim().isNotEmpty && value.trim() != categoryLabel?.trim())
      value.trim(),
  ];

  bool get _hasMetadata =>
      _categoryMetadataParts.isNotEmpty ||
      paymentSource?.trim().isNotEmpty == true;

  List<String> get _visibleTags =>
      tags.where((value) => value.trim().isNotEmpty).toList(growable: false);

  Widget _duplicateWarning(BuildContext context) {
    final label = possibleDuplicate
        ? possibleDuplicateLabel ?? context.l10n.text('possibleDuplicate')
        : context.l10n.text('needsReview');
    return Padding(
      padding: const EdgeInsets.only(top: ButlerlySpacing.compact),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        button: onPossibleDuplicateTap != null,
        label: label,
        child: InkWell(
          onTap: onPossibleDuplicateTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: ButlerlyTransactionItemTokens.warningIconSize,
                  color: context.transactionItemWarningIcon,
                ),
              ),
              const SizedBox(width: ButlerlySpacing.micro),
              Flexible(
                child: ExcludeSemantics(
                  child: Text(label, style: context.transactionItemMetadata),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeutralTransactionIcon extends StatelessWidget {
  const _NeutralTransactionIcon();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    key: const Key('transaction-leading-icon'),
    dimension: ButlerlyTransactionItemTokens.leadingIconSize,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.subtleSurface,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.receipt_long_outlined,
        size: ButlerlyTransactionItemTokens.leadingIconGlyphSize,
        color: context.colors.secondaryText,
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
    super.categoryId,
    super.categoryColorId,
    super.categoryLabel,
    super.subcategoryLabel,
    super.paymentSource,
    super.paymentSourceMark,
    super.tags,
    super.supportingContent,
    super.showDate,
    super.isIncome,
    super.needsReview,
    super.possibleDuplicate,
    super.possibleDuplicateLabel,
    super.onPossibleDuplicateTap,
    super.selectionControl,
    super.onTap,
    super.showNavigationIndicator,
    super.showCategoryPill,
    super.amountIncludesCurrency,
    super.compactSpacing,
    super.variant,
    super.key,
  });
}

/// Shared selection control for form fields backed by canonical values.
/// Labels are presentation-only; callers keep the selected ID/value unchanged.
class ButlerlySelectField<T> extends StatefulWidget {
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
  State<ButlerlySelectField<T>> createState() => _ButlerlySelectFieldState<T>();
}

class _ButlerlySelectFieldState<T> extends State<ButlerlySelectField<T>> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _labelFor(widget.value, widget.entries),
    );
  }

  @override
  void didUpdateWidget(covariant ButlerlySelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldLabel = _labelFor(oldWidget.value, oldWidget.entries);
    final newLabel = _labelFor(widget.value, widget.entries);
    if (oldWidget.value != widget.value || oldLabel != newLabel) {
      _controller.value = TextEditingValue(
        text: newLabel,
        selection: TextSelection.collapsed(offset: newLabel.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _labelFor(T? value, List<DropdownMenuEntry<T>> entries) {
    if (value == null) return '';
    for (final entry in entries) {
      if (entry.value == value) return entry.label;
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => DropdownMenu<T>(
      controller: _controller,
      initialSelection: widget.value,
      width: constraints.maxWidth,
      menuHeight: 192,
      label: Text(widget.label),
      trailingIcon: widget.onCreate == null && widget.onClear == null
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onCreate != null)
                  IconButton(
                    onPressed: widget.onCreate,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: widget.createTooltip,
                  ),
                if (widget.onClear != null)
                  IconButton(
                    onPressed: widget.onClear,
                    icon: const Icon(Icons.clear),
                    tooltip: widget.clearTooltip,
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
        backgroundColor: WidgetStatePropertyAll(context.colors.cardSurface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(
              Radius.circular(ButlerlyRadius.card),
            ),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: ButlerlySpacing.micro),
        ),
      ),
      dropdownMenuEntries: [
        for (final entry in widget.entries)
          DropdownMenuEntry<T>(
            value: entry.value,
            label: entry.label,
            labelWidget: entry.labelWidget,
            leadingIcon: entry.leadingIcon,
            trailingIcon: entry.trailingIcon,
            enabled: entry.enabled,
            style: (entry.style ?? const ButtonStyle()).copyWith(
              side: const WidgetStatePropertyAll(BorderSide.none),
              shape: const WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(
                    Radius.circular(ButlerlyRadius.standard),
                  ),
                ),
              ),
            ),
          ),
      ],
      onSelected: widget.onChanged,
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
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
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
