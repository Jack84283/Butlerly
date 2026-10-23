import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

/// Shared desktop presentation shell for every wide viewport, including iPad.
/// Kept separate from the legacy WidePrimaryShell implementation.
class DesktopPrimaryShell extends StatefulWidget {
  const DesktopPrimaryShell({
    required this.body,
    required this.currentIndex,
    required this.onSelected,
    super.key,
  });

  final Widget body;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<String> onMoreSectionSelected;

  @override
  State<DesktopPrimaryShell> createState() => _DesktopPrimaryShellState();
}

class _DesktopPrimaryShellState extends State<DesktopPrimaryShell> {
  // Preserve expansion preference across viewport changes.
  bool _expandedAtWideWidths = true;
  bool _expandedAtNarrowWidths = false;

  @override
  Widget build(BuildContext context) {
    // At tablet and narrow desktop widths, keep the rail compact by default.
    // A fully expanded 248px rail would leave too little space for the content.
    final narrow =
        MediaQuery.sizeOf(context).width < ButlerlySize.wideBreakpoint;
    final expanded = narrow ? _expandedAtNarrowWidths : _expandedAtWideWidths;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Row(
          children: [
            _WidePrimaryNavigation(
              key: const ValueKey('primary-wide-navigation'),
              expanded: expanded,
              currentIndex: widget.currentIndex,
              onToggleExpanded: () => setState(() {
                if (narrow) {
                  _expandedAtNarrowWidths = !expanded;
                } else {
                  _expandedAtWideWidths = !expanded;
                }
              }),
              onParentSelected: widget.onSelected,
            ),
            Expanded(
              child: ColoredBox(
                key: const ValueKey('primary-wide-body-surface'),
                color: context.colors.background,
                child: SafeArea(bottom: false, child: widget.body),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WidePrimaryNavigation extends StatelessWidget {
  const _WidePrimaryNavigation({
    super.key,
    required this.expanded,
    required this.currentIndex,
    required this.onToggleExpanded,
    required this.onParentSelected,
    required this.onMoreSectionSelected,
  });

  final bool expanded;
  final int currentIndex;
  final VoidCallback onToggleExpanded;
  final ValueChanged<int> onParentSelected;

  bool _selected(int branchIndex) => currentIndex == branchIndex;

  @override
  Widget build(BuildContext context) => Container(
    // Switch widths atomically: animating a 248px menu inside a 72px rail
    // overflows while transitioning across responsive breakpoints.
    width: expanded
        ? ButlerlySize.wideNavigationExpandedWidth
        : ButlerlySize.wideNavigationCollapsedWidth,
    decoration: BoxDecoration(
      color: context.colors.surface,
      border: Border(right: BorderSide(color: context.colors.cardDivider)),
    ),
    child: SafeArea(
      bottom: false,
      child: Column(
        children: [
          _WideBrand(expanded: expanded),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                ButlerlySpacing.compact,
                ButlerlySpacing.none,
                ButlerlySpacing.compact,
                ButlerlySize.wideNavigationItemHeight + ButlerlySpacing.large,
              ),
              child: expanded
                  ? _expandedMenu(context)
                  : _collapsedMenu(context),
            ),
          ),
          _WideCollapseButton(expanded: expanded, onPressed: onToggleExpanded),
        ],
      ),
    ),
  );

  Widget _expandedMenu(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _WideTopLevelItem(
        semanticKey: const ValueKey('wide-home-navigation'),
        icon: Icons.home_rounded,
        label: context.l10n.text('home'),
        selected: _selected(0),
        onTap: () => onParentSelected(0),
      ),
      _WideTopLevelItem(
        icon: Icons.format_list_bulleted_rounded,
        label: context.l10n.text('transactions'),
        selected: _selected(1),
        onTap: () => onParentSelected(1),
      ),
      _WideTopLevelItem(
        semanticKey: const ValueKey('wide-add-navigation'),
        icon: Icons.add_rounded,
        label: context.l10n.text('add'),
        selected: _selected(2),
        onTap: () => onParentSelected(2),
      ),
      _WideTopLevelItem(
        semanticKey: const ValueKey('wide-tools-navigation'),
        icon: Icons.bar_chart_rounded,
        label: context.l10n.text('tools'),
        selected: _selected(3),
        onTap: () => onParentSelected(3),
      ),
      _WideTopLevelItem(
        semanticKey: const ValueKey('wide-more-navigation'),
        icon: Icons.settings_outlined,
        label: context.l10n.text('more'),
        selected: _selected(4),
        onTap: () => onParentSelected(4),
      ),
    ],
  );

  Widget _collapsedMenu(BuildContext context) => Column(
    children: [
      _WideCollapsedItem(
        key: const ValueKey('wide-collapsed-home'),
        icon: Icons.home_rounded,
        label: context.l10n.text('home'),
        selected: _selected(0),
        onTap: (_) => onParentSelected(0),
      ),
      _WideCollapsedItem(
        key: const ValueKey('wide-collapsed-transactions'),
        icon: Icons.format_list_bulleted_rounded,
        label: context.l10n.text('transactions'),
        selected: _selected(1),
        onTap: (_) => onParentSelected(1),
      ),
      _WideCollapsedItem(
        key: const ValueKey('wide-collapsed-add'),
        icon: Icons.add_rounded,
        label: context.l10n.text('add'),
        selected: _selected(2),
        onTap: (_) => onParentSelected(2),
      ),
      _WideCollapsedItem(
        key: const ValueKey('wide-collapsed-tools'),
        icon: Icons.bar_chart_rounded,
        label: context.l10n.text('tools'),
        selected: _selected(3),
        onTap: (_) => onParentSelected(3),
      ),
      _WideCollapsedItem(
        key: const ValueKey('wide-collapsed-more'),
        icon: Icons.settings_outlined,
        label: context.l10n.text('more'),
        selected: _selected(4),
        onTap: (_) => onParentSelected(4),
      ),
    ],
  );


}

class _WideBrand extends StatelessWidget {
  const _WideBrand({required this.expanded});
  final bool expanded;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(ButlerlySpacing.standard),
    child: Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.brand,
            borderRadius: BorderRadius.circular(ButlerlyRadius.small),
          ),
          child: const SizedBox(
            width: ButlerlySize.wideNavigationBrandSize,
            height: ButlerlySize.wideNavigationBrandSize,
            child: Icon(
              Icons.shield_outlined,
              color: Colors.white,
              size: ButlerlySize.standardIcon,
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(width: ButlerlySpacing.compact),
          Expanded(
            child: Text(
              context.l10n.text('appName'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ],
    ),
  );
}

class _WideTopLevelItem extends StatelessWidget {
  const _WideTopLevelItem({
    this.semanticKey,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Key? semanticKey;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _WideNavigationSurface(
    selected: selected,
    child: Semantics(
      key: semanticKey,
      button: true,
      container: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: ButlerlySize.wideNavigationItemHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ButlerlySpacing.compact,
            ),
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: ButlerlySpacing.compact),
                Expanded(child: Text(label)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _WideCollapsedItem extends StatelessWidget {
  const _WideCollapsedItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final ValueChanged<BuildContext> onTap;

  @override
  Widget build(BuildContext context) => Builder(
    builder: (itemContext) => Semantics(
      button: true,
      selected: selected,
      label: label,
      child: _WideNavigationSurface(
        selected: selected,
        child: IconButton(
          tooltip: label,
          onPressed: () => onTap(itemContext),
          icon: Icon(icon),
        ),
      ),
    ),
  );
}

class _WideCollapseButton extends StatelessWidget {
  const _WideCollapseButton({required this.expanded, required this.onPressed});
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      expanded
          ? Icons.keyboard_double_arrow_left_rounded
          : Icons.keyboard_double_arrow_right_rounded,
    );
    return Padding(
      padding: const EdgeInsets.all(ButlerlySpacing.compact),
      child: expanded
          ? SizedBox(
              width: double.infinity,
              height: ButlerlySize.wideNavigationItemHeight,
              child: OutlinedButton.icon(
                onPressed: onPressed,
                icon: icon,
                label: Text(context.l10n.text('collapse')),
              ),
            )
          : IconButton(
              tooltip: context.l10n.text('expand'),
              onPressed: onPressed,
              icon: icon,
            ),
    );
  }
}

class _WideNavigationSurface extends StatelessWidget {
  const _WideNavigationSurface({required this.selected, required this.child});
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? context.colors.selection : Colors.transparent,
        borderRadius: BorderRadius.circular(ButlerlyRadius.control),
      ),
      child: IconTheme(
        data: IconThemeData(
          color: selected
              ? context.colors.interactive
              : context.colors.secondaryText,
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            color: selected
                ? context.colors.interactive
                : context.colors.primaryText,
          ),
          child: child,
        ),
      ),
    ),
  );
}

