import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

String _paymentSourceText(PaymentSource source) => source.lastFour == null
    ? (source.displayIdentity ?? source.name)
    : '${source.displayIdentity ?? source.name} ••••${source.lastFour}';

class ButlerlyCategorySelector extends StatelessWidget {
  const ButlerlyCategorySelector({
    required this.categories,
    required this.masterData,
    required this.value,
    required this.label,
    required this.onChanged,
    required this.clearLabel,
    super.key,
  });
  final List<Category> categories;
  final TransactionMasterData masterData;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;
  final String clearLabel;

  @override
  Widget build(BuildContext context) => ButlerlySelectField<String>(
    label: label,
    value: value,
    entries: [
      for (final category in categories.where(
        (category) =>
            category.status == CategoryStatus.active &&
            category.parentId == null,
      ))
        DropdownMenuEntry(
          value: category.id.value,
          label: masterData.categoryName(category.id.value) ?? category.name,
        ),
    ],
    onChanged: onChanged,
    onClear: value == null ? null : () => onChanged(null),
    clearTooltip: clearLabel,
  );
}

class ButlerlySubcategorySelector extends StatelessWidget {
  const ButlerlySubcategorySelector({
    required this.categories,
    required this.masterData,
    required this.parentId,
    required this.value,
    required this.label,
    required this.onChanged,
    required this.clearLabel,
    super.key,
  });
  final List<Category> categories;
  final TransactionMasterData masterData;
  final String? parentId;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    final children = categories.where(
      (category) =>
          category.status == CategoryStatus.active &&
          category.parentId?.value == parentId,
    );
    final selected = children.any((category) => category.id.value == value)
        ? value
        : null;
    return ButlerlySelectField<String>(
      label: label,
      value: selected,
      entries: [
        for (final category in children)
          DropdownMenuEntry(
            value: category.id.value,
            label: masterData.categoryName(category.id.value) ?? category.name,
          ),
      ],
      onChanged: (next) => onChanged(next ?? parentId),
      onClear: selected == null ? null : () => onChanged(parentId),
      clearTooltip: clearLabel,
    );
  }
}

class ButlerlyMerchantSelector extends StatelessWidget {
  const ButlerlyMerchantSelector({
    required this.merchants,
    required this.value,
    required this.label,
    required this.onChanged,
    this.onCreate,
    required this.clearLabel,
    super.key,
  });
  final List<Merchant> merchants;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onCreate;
  final String clearLabel;

  @override
  Widget build(BuildContext context) => ButlerlySelectField<String>(
    label: label,
    value: value,
    entries: [
      for (final merchant in merchants.where(
        (merchant) => merchant.status == MerchantStatus.active,
      ))
        DropdownMenuEntry(value: merchant.id.value, label: merchant.name),
    ],
    onChanged: onChanged,
    onCreate: onCreate,
    onClear: value == null ? null : () => onChanged(null),
    clearTooltip: clearLabel,
  );
}

class ButlerlyPaymentSourceSelector extends StatelessWidget {
  const ButlerlyPaymentSourceSelector({
    required this.sources,
    required this.value,
    required this.label,
    required this.onChanged,
    required this.clearLabel,
    super.key,
  });
  final List<PaymentSource> sources;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;
  final String clearLabel;

  @override
  Widget build(BuildContext context) => ButlerlySelectField<String>(
    label: label,
    value: value,
    entries: [
      for (final source in sources.where(
        (source) => source.status == PaymentSourceStatus.active,
      ))
        DropdownMenuEntry(
          value: source.id.value,
          label: _paymentSourceText(source),
        ),
    ],
    onChanged: onChanged,
    onClear: value == null ? null : () => onChanged(null),
    clearTooltip: clearLabel,
  );
}

class ButlerlyTagPicker extends StatefulWidget {
  const ButlerlyTagPicker({
    required this.tags,
    required this.masterData,
    required this.selected,
    required this.onChanged,
    this.onCreate,
    required this.searchLabel,
    required this.createLabel,
    super.key,
  });
  final List<Tag> tags;
  final TransactionMasterData masterData;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final VoidCallback? onCreate;
  final String searchLabel;
  final String createLabel;

  @override
  State<ButlerlyTagPicker> createState() => _ButlerlyTagPickerState();
}

class _ButlerlyTagPickerState extends State<ButlerlyTagPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tags = widget.tags.where((tag) => tag.status == TagStatus.active);
    final visible = tags.where((tag) {
      final label = widget.masterData.tagName(tag.id.value) ?? tag.name;
      return _query.trim().isEmpty ||
          label.toLowerCase().contains(_query.trim().toLowerCase());
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.tags.length > 8)
          TextField(
            decoration: InputDecoration(
              labelText: widget.searchLabel,
              prefixIcon: const Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tag in visible)
              FilterChip(
                label: Text(
                  widget.masterData.tagName(tag.id.value) ?? tag.name,
                ),
                selected: widget.selected.contains(tag.id.value),
                onSelected: (isSelected) {
                  final next = {...widget.selected};
                  if (isSelected) {
                    next.add(tag.id.value);
                  } else {
                    next.remove(tag.id.value);
                  }
                  widget.onChanged(next);
                },
              ),
            if (widget.onCreate != null)
              ActionChip(
                label: Text(widget.createLabel),
                avatar: const Icon(Icons.add),
                onPressed: widget.onCreate,
              ),
          ],
        ),
      ],
    );
  }
}
