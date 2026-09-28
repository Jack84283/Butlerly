import 'dart:math' as math;

import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/contextual_pages.dart';
import 'package:butlerly/features/tools/presentation/tools_navigation.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WidePrimaryShell extends StatefulWidget {
  const WidePrimaryShell({
    required this.body,
    required this.currentIndex,
    required this.onSelected,
    required this.onMoreSectionSelected,
    super.key,
  });

  final Widget body;
  final int currentIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<String> onMoreSectionSelected;

  @override
  State<WidePrimaryShell> createState() => _WidePrimaryShellState();
}

class _WidePrimaryShellState extends State<WidePrimaryShell> {
  final _moreNavigationKey = GlobalKey();
  bool _expanded = true;
  bool _addExpanded = true;
  bool _toolsExpanded = true;
  bool _moreExpanded = true;
  bool _moreVisibilityScheduled = false;

  void _selectParent(int branchIndex) {
    if (branchIndex == 4) {
      setState(() => _moreExpanded = true);
    }
    widget.onSelected(branchIndex);
  }

  void _ensureMoreVisible() {
    if (!_expanded || widget.currentIndex != 4 || _moreVisibilityScheduled) {
      return;
    }
    _moreVisibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _moreVisibilityScheduled = false;
      final targetContext = _moreNavigationKey.currentContext;
      if (!mounted || targetContext == null) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.0,
        duration: ButlerlyMotion.responsive(context, ButlerlyMotion.fast),
      );
    });
  }

  Future<void> _navigate(String route) async {
    if (!mounted) return;
    await context.push(route);
  }

  Future<void> _import() => startLocalFileImport(context);

  @override
  Widget build(BuildContext context) {
    _ensureMoreVisible();
    return Scaffold(
      body: Row(
        children: [
          _WidePrimaryNavigation(
            key: const ValueKey('primary-wide-navigation'),
            expanded: _expanded,
            addExpanded: _addExpanded,
            toolsExpanded: _toolsExpanded,
            moreExpanded: _moreExpanded,
            currentIndex: widget.currentIndex,
            onToggleExpanded: () => setState(() => _expanded = !_expanded),
            onToggleAdd: () => setState(() => _addExpanded = !_addExpanded),
            onToggleTools: () =>
                setState(() => _toolsExpanded = !_toolsExpanded),
            onToggleMore: () => setState(() => _moreExpanded = !_moreExpanded),
            moreNavigationKey: _moreNavigationKey,
            onParentSelected: _selectParent,
            onMoreSectionSelected: widget.onMoreSectionSelected,
            onNavigate: _navigate,
            onImport: _import,
          ),
          Expanded(
            child: SafeArea(
              bottom: false,
              child: ColoredBox(
                key: const ValueKey('primary-wide-body-surface'),
                color: context.colors.subtleSurface,
                child: _wideBody(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideBody(BuildContext context) {
    if (widget.currentIndex != 0) return widget.body;

    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = ButlerlySpacing.large;
        final width = math.min(
          constraints.maxWidth - (padding * 2),
          ButlerlySize.pageContentMaxWidth + (ButlerlySize.contentGutter * 2),
        );
        final height = math.max(0.0, constraints.maxHeight - (padding * 2));
        return Padding(
          padding: const EdgeInsets.all(padding),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              key: const ValueKey('primary-wide-home-floating-surface'),
              width: width,
              height: height,
              child: Material(
                color: context.colors.background,
                elevation: ButlerlyElevation.floating,
                borderRadius: BorderRadius.circular(ButlerlyRadius.large),
                clipBehavior: Clip.antiAlias,
                child: widget.body,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WidePrimaryNavigation extends StatelessWidget {
  const _WidePrimaryNavigation({
    super.key,
    required this.expanded,
    required this.addExpanded,
    required this.toolsExpanded,
    required this.moreExpanded,
    required this.currentIndex,
    required this.onToggleExpanded,
    required this.onToggleAdd,
    required this.onToggleTools,
    required this.onToggleMore,
    required this.moreNavigationKey,
    required this.onParentSelected,
    required this.onMoreSectionSelected,
    required this.onNavigate,
    required this.onImport,
  });

  final bool expanded;
  final bool addExpanded;
  final bool toolsExpanded;
  final bool moreExpanded;
  final int currentIndex;
  final VoidCallback onToggleExpanded;
  final VoidCallback onToggleAdd;
  final VoidCallback onToggleTools;
  final VoidCallback onToggleMore;
  final GlobalKey moreNavigationKey;
  final ValueChanged<int> onParentSelected;
  final ValueChanged<String> onMoreSectionSelected;
  final ValueChanged<String> onNavigate;
  final Future<void> Function() onImport;

  bool _selected(int branchIndex) => currentIndex == branchIndex;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: ButlerlyMotion.responsive(context, ButlerlyMotion.standard),
    curve: ButlerlyMotion.curve,
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
        icon: Icons.format_list_bulleted_rounded,
        label: context.l10n.text('transactions'),
        selected: _selected(1),
        onTap: () => onParentSelected(1),
      ),
      _WideGroup(
        semanticKey: const ValueKey('wide-add-navigation'),
        label: context.l10n.text('add'),
        icon: Icons.add_rounded,
        selected: _selected(2),
        expanded: addExpanded,
        onTap: () => onParentSelected(2),
        onToggle: onToggleAdd,
        children: [
          _WideChildItem(
            icon: Icons.add_card_outlined,
            label: context.l10n.text('addTransactionManually'),
            onTap: () => onNavigate('/transactions/add'),
          ),
          _WideChildItem(
            icon: Icons.receipt_long_outlined,
            label: context.l10n.text('addTransactionFromReceipt'),
            onTap: () => onNavigate('/receipts/capture'),
          ),
          _WideChildItem(
            icon: Icons.document_scanner_outlined,
            label: context.l10n.text('addTransactionFromStatement'),
            onTap: () => onNavigate('/statements'),
          ),
          _WideChildItem(
            icon: Icons.file_open_outlined,
            label: context.l10n.text('addTransactionFromLocalFile'),
            onTap: () {
              onImport();
            },
          ),
          const Divider(height: ButlerlySpacing.standard),
          _WideChildItem(
            icon: Icons.account_balance_wallet_outlined,
            label: context.l10n.text('paymentSources'),
            onTap: () => onNavigate('/payment-sources'),
          ),
        ],
      ),
      _WideGroup(
        semanticKey: const ValueKey('wide-tools-navigation'),
        label: context.l10n.text('tools'),
        icon: Icons.bar_chart_rounded,
        selected: _selected(3),
        expanded: toolsExpanded,
        onTap: () => onParentSelected(3),
        onToggle: onToggleTools,
        children: [
          for (final tool in toolNavigationItems(context))
            _WideChildItem(
              icon: tool.icon,
              label: tool.title,
              onTap: () => onNavigate(tool.route),
            ),
        ],
      ),
      _WideGroup(
        key: moreNavigationKey,
        semanticKey: const ValueKey('wide-more-navigation'),
        label: context.l10n.text('more'),
        icon: Icons.more_horiz_rounded,
        selected: _selected(4),
        expanded: moreExpanded,
        onTap: () => onParentSelected(4),
        onToggle: onToggleMore,
        children: [
          _WideChildItem(
            icon: Icons.privacy_tip_outlined,
            label: context.l10n.text('privacyAndData'),
            onTap: () => onNavigate('/privacy-data'),
          ),
          _WideChildItem(
            icon: Icons.auto_awesome_outlined,
            label: context.l10n.text('assistant'),
            onTap: () => onNavigate('/assistant'),
          ),
          _WideChildItem(
            icon: Icons.info_outline_rounded,
            label: context.l10n.text('about'),
            onTap: () => onMoreSectionSelected('about'),
          ),
        ],
      ),
    ],
  );

  Widget _collapsedMenu(BuildContext context) => Column(
    children: [
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
        onTap: (itemContext) => _openMenu(itemContext, [
          _WidePopupAction.parent(context.l10n.text('add'), 2),
          _WidePopupAction.route(
            context.l10n.text('addTransactionManually'),
            '/transactions/add',
          ),
          _WidePopupAction.route(
            context.l10n.text('addTransactionFromReceipt'),
            '/receipts/capture',
          ),
          _WidePopupAction.route(
            context.l10n.text('addTransactionFromStatement'),
            '/statements',
          ),
          _WidePopupAction.importFile(
            context.l10n.text('addTransactionFromLocalFile'),
          ),
          const _WidePopupAction.divider(),
          _WidePopupAction.route(
            context.l10n.text('paymentSources'),
            '/payment-sources',
          ),
        ]),
      ),
      _WideCollapsedItem(
        key: const ValueKey('wide-collapsed-tools'),
        icon: Icons.bar_chart_rounded,
        label: context.l10n.text('tools'),
        selected: _selected(3),
        onTap: (itemContext) => _openMenu(itemContext, [
          _WidePopupAction.parent(context.l10n.text('tools'), 3),
          for (final tool in toolNavigationItems(context))
            _WidePopupAction.route(tool.title, tool.route),
        ]),
      ),
      _WideCollapsedItem(
        key: const ValueKey('wide-collapsed-more'),
        icon: Icons.more_horiz_rounded,
        label: context.l10n.text('more'),
        selected: _selected(4),
        onTap: (itemContext) => _openMenu(itemContext, [
          _WidePopupAction.parent(context.l10n.text('more'), 4),
          _WidePopupAction.route(
            context.l10n.text('privacyAndData'),
            '/privacy-data',
          ),
          _WidePopupAction.route(context.l10n.text('assistant'), '/assistant'),
          _WidePopupAction.moreSection(context.l10n.text('about'), 'about'),
        ]),
      ),
    ],
  );

  Future<void> _openMenu(
    BuildContext itemContext,
    List<_WidePopupAction> actions,
  ) async {
    final itemBox = itemContext.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(itemContext).overlay!;
    final overlayBox = overlay.context.findRenderObject()! as RenderBox;
    final itemTopLeft = itemBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final itemBottomRight = itemBox.localToGlobal(
      itemBox.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    );
    final itemRect = Rect.fromPoints(itemTopLeft, itemBottomRight);
    final selected = await openButlerlyAnchoredMenu<_WidePopupAction>(
      context: itemContext,
      position: RelativeRect.fromLTRB(
        itemRect.right,
        itemRect.top,
        overlayBox.size.width - itemRect.right,
        overlayBox.size.height - itemRect.bottom,
      ),
      entries: [
        for (final action in actions)
          action.isDivider
              ? const ButlerlyMenuEntry<_WidePopupAction>.divider()
              : ButlerlyMenuEntry(value: action, label: action.label),
      ],
    );
    if (!itemContext.mounted || selected == null) return;
    switch (selected.kind) {
      case _WidePopupActionKind.parent:
        onParentSelected(selected.branchIndex!);
      case _WidePopupActionKind.route:
        onNavigate(selected.route!);
      case _WidePopupActionKind.moreSection:
        onMoreSectionSelected(selected.section!);
      case _WidePopupActionKind.importFile:
        await onImport();
      case _WidePopupActionKind.divider:
        break;
    }
  }
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
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _WideNavigationSurface(
    selected: selected,
    child: Semantics(
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

class _WideGroup extends StatelessWidget {
  const _WideGroup({
    super.key,
    this.semanticKey,
    required this.label,
    required this.icon,
    required this.selected,
    required this.expanded,
    required this.onTap,
    required this.onToggle,
    required this.children,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final List<Widget> children;
  final Key? semanticKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _WideNavigationSurface(
        selected: selected,
        child: Row(
          children: [
            Expanded(
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
            ),
            IconButton(
              tooltip: expanded
                  ? '${context.l10n.text('collapse')} $label'
                  : '${context.l10n.text('expand')} $label',
              onPressed: onToggle,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
              ),
            ),
          ],
        ),
      ),
      if (expanded)
        Padding(
          padding: const EdgeInsets.only(left: ButlerlySpacing.standard),
          child: Column(children: children),
        ),
    ],
  );
}

class _WideChildItem extends StatelessWidget {
  const _WideChildItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    container: true,
    label: label,
    onTap: onTap,
    child: SizedBox(
      height: ButlerlySize.wideNavigationItemHeight,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ButlerlySpacing.compact,
          ),
          child: Row(
            children: [
              Icon(icon, size: ButlerlySize.standardIcon),
              const SizedBox(width: ButlerlySpacing.compact),
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
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

enum _WidePopupActionKind { parent, route, moreSection, importFile, divider }

class _WidePopupAction {
  const _WidePopupAction._({
    required this.kind,
    required this.label,
    this.branchIndex,
    this.route,
    this.section,
  });

  const _WidePopupAction.parent(String label, int branchIndex)
    : this._(
        kind: _WidePopupActionKind.parent,
        label: label,
        branchIndex: branchIndex,
      );

  const _WidePopupAction.route(String label, String route)
    : this._(kind: _WidePopupActionKind.route, label: label, route: route);

  const _WidePopupAction.moreSection(String label, String section)
    : this._(
        kind: _WidePopupActionKind.moreSection,
        label: label,
        section: section,
      );

  const _WidePopupAction.importFile(String label)
    : this._(kind: _WidePopupActionKind.importFile, label: label);

  const _WidePopupAction.divider()
    : this._(kind: _WidePopupActionKind.divider, label: '');

  final _WidePopupActionKind kind;
  final String label;
  final int? branchIndex;
  final String? route;
  final String? section;

  bool get isDivider => kind == _WidePopupActionKind.divider;
}
