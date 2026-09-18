import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// Compact text-button section navigation shared by dense Butlerly pages.
///
/// The selector remains one horizontal row, scrolls when labels exceed the
/// available width, and exposes directional overflow indicators.
class ButlerlyCompactSectionSelector extends StatefulWidget {
  const ButlerlyCompactSectionSelector({
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  State<ButlerlyCompactSectionSelector> createState() =>
      _ButlerlyCompactSectionSelectorState();
}

class _ButlerlyCompactSectionSelectorState
    extends State<ButlerlyCompactSectionSelector> {
  final ScrollController _controller = ScrollController();
  bool _showLeading = false;
  bool _showTrailing = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncIndicators);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncIndicators());
  }

  @override
  void didUpdateWidget(covariant ButlerlyCompactSectionSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncIndicators());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_syncIndicators)
      ..dispose();
    super.dispose();
  }

  void _syncIndicators() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    final leading = position.pixels > 1;
    final trailing = position.maxScrollExtent - position.pixels > 1;
    if (leading == _showLeading && trailing == _showTrailing) return;
    setState(() {
      _showLeading = leading;
      _showTrailing = trailing;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      key: const ValueKey('compact-section-selector'),
      height: ButlerlySize.minimumTarget,
      child: Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (_) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _syncIndicators(),
              );
              return false;
            },
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                key: const ValueKey('compact-section-selector-scroll'),
                controller: _controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: ButlerlySpacing.micro,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < widget.labels.length; index++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ButlerlySpacing.xxs,
                          ),
                          child: Semantics(
                            key: ValueKey('compact-section-semantics-$index'),
                            selected: index == widget.selectedIndex,
                            child: TextButton(
                              key: ValueKey('compact-section-$index'),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(
                                  ButlerlySize.minimumTarget,
                                  ButlerlySize.minimumTarget,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: ButlerlySpacing.small,
                                ),
                                foregroundColor: index == widget.selectedIndex
                                    ? colors.primary
                                    : colors.onSurface,
                                backgroundColor: Colors.transparent,
                                shape: const StadiumBorder(),
                              ),
                              onPressed: () => widget.onSelected(index),
                              child: Text(
                                widget.labels[index],
                                maxLines: 1,
                                overflow: TextOverflow.fade,
                                softWrap: false,
                                style: TextStyle(
                                  fontWeight: index == widget.selectedIndex
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_showLeading)
            const PositionedDirectional(
              start: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: _OverflowIndicator(
                  key: ValueKey('compact-section-leading-indicator'),
                  icon: Icons.chevron_left,
                ),
              ),
            ),
          if (_showTrailing)
            const PositionedDirectional(
              end: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: _OverflowIndicator(
                  key: ValueKey('compact-section-trailing-indicator'),
                  icon: Icons.chevron_right,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverflowIndicator extends StatelessWidget {
  const _OverflowIndicator({required this.icon, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: ButlerlySize.minimumTarget,
    alignment: Alignment.center,
    color: Theme.of(context).colorScheme.surface.withValues(alpha: .92),
    child: Icon(icon, size: ButlerlySize.compactActionIconSize),
  );
}
