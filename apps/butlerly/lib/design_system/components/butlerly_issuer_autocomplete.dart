import 'package:butlerly/design_system/components/butlerly_issuer_catalog.dart';
import 'package:butlerly/design_system/components/butlerly_payment_source_icon.dart';
import 'package:flutter/material.dart';

/// Offline issuer autocomplete; users may always type a custom issuer.
class ButlerlyIssuerAutocomplete extends StatefulWidget {
  const ButlerlyIssuerAutocomplete({
    required this.controller,
    required this.label,
    super.key,
  });

  final TextEditingController controller;
  final String label;

  @override
  State<ButlerlyIssuerAutocomplete> createState() =>
      _ButlerlyIssuerAutocompleteState();
}

class _ButlerlyIssuerAutocompleteState
    extends State<ButlerlyIssuerAutocomplete> {
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => RawAutocomplete<IssuerInstitution>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (issuer) => issuer.name,
      optionsBuilder: (value) => suggestIssuers(value.text),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSubmitted(),
            decoration: InputDecoration(
              labelText: widget.label,
              prefixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  final issuer = issuerForName(value.text);
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: issuer == null
                        ? Icon(
                            Icons.account_balance_outlined,
                            color: Theme.of(context).colorScheme.onSurface,
                          )
                        : ButlerlyIssuerIcon(issuer: issuer, size: 24),
                  );
                },
              ),
            ),
          ),
      optionsViewBuilder: (context, onSelected, options) {
        final highlightedIndex = AutocompleteHighlightedOption.of(context);
        return Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 6,
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: constraints.maxWidth,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 264),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final issuer = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    selected: index == highlightedIndex,
                    selectedTileColor:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    leading: ButlerlyIssuerIcon(issuer: issuer, size: 26),
                    title: Text(issuer.name),
                    subtitle: Text(
                      issuer.aliases.take(3).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelected(issuer),
                  );
                },
              ),
            ),
          ),
        ),
      );
      },
    ),
  );
}
