import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:flutter/material.dart';

/// The approved frameless 258 abacus mark. The artwork is transparent and
/// shared by launch, Home, More, and Legal & Licenses in every layout mode.
class ButlerlyBrandIcon extends StatelessWidget {
  const ButlerlyBrandIcon({super.key, this.size = 32, this.semanticLabel});

  static const assetPath =
      'assets/branding/butlerly_258_abacus_transparent.png';

  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Image.asset(
    assetPath,
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    semanticLabel: semanticLabel,
    excludeFromSemantics: semanticLabel == null,
  );
}

/// One responsive brand header for Compact and Medium Home. Desktop's
/// navigation brand uses the same [ButlerlyBrandIcon].
class ButlerlyBrandTitle extends StatelessWidget {
  const ButlerlyBrandTitle({
    required this.name,
    super.key,
    this.iconSize = 28,
    this.gap = 8,
    this.textStyle,
  });

  final String name;
  final double iconSize;
  final double gap;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 18;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ButlerlyBrandIcon(size: iconSize),
        SizedBox(width: gap),
        Flexible(
          child: Text(
            name,
            maxLines: largeText ? null : 1,
            overflow: largeText ? TextOverflow.visible : TextOverflow.ellipsis,
            softWrap: largeText,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

/// A shared identity row using the *bundled* app version (never a hard-coded
/// release number or a value in the finance database).
class ButlerlyBrandVersionTile extends StatelessWidget {
  const ButlerlyBrandVersionTile({
    required this.appName,
    required this.versionLabel,
    required this.version,
    this.centered = false,
    super.key,
  });

  final String appName;
  final String versionLabel;
  final Future<String> version;
  final bool centered;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: centered
        ? Padding(
            padding: const EdgeInsets.symmetric(
              vertical: ButlerlySpacing.small,
            ),
            child: Column(
              key: const ValueKey('butlerly-brand-version-tile'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const Center(child: ButlerlyBrandIcon(size: 44)),
                const SizedBox(height: 8),
                Text(
                  appName,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                FutureBuilder<String>(
                  future: version,
                  builder: (context, snapshot) => Text(
                    '$versionLabel ${snapshot.data ?? '—'}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        : ListTile(
            key: const ValueKey('butlerly-brand-version-tile'),
            contentPadding: EdgeInsets.zero,
            leading: const ButlerlyBrandIcon(size: 44),
            title: Text(appName, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: FutureBuilder<String>(
              future: version,
              builder: (context, snapshot) => Text(
                '$versionLabel ${snapshot.data ?? '—'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
  );
}
