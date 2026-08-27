import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
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
    this.createTooltip,
    required this.clearLabel,
    super.key,
  });
  final List<Merchant> merchants;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onCreate;
  final String? createTooltip;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    assert(onCreate == null || createTooltip != null);
    return ButlerlySelectField<String>(
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
      createTooltip: createTooltip,
      onClear: value == null ? null : () => onChanged(null),
      clearTooltip: clearLabel,
    );
  }
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

/// Nullable filter variant of the canonical category selector.
class ButlerlyCategoryFilter extends StatelessWidget {
  const ButlerlyCategoryFilter({
    required this.categories,
    required this.masterData,
    required this.value,
    required this.label,
    required this.anyLabel,
    required this.onChanged,
    super.key,
  });
  final List<Category> categories;
  final TransactionMasterData masterData;
  final String? value;
  final String label;
  final String anyLabel;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => ButlerlySelectField<String>(
    label: label,
    value: value,
    entries: [
      DropdownMenuEntry(value: '', label: anyLabel),
      for (final category in categories.where(
        (value) =>
            value.status == CategoryStatus.active && value.parentId == null,
      ))
        DropdownMenuEntry(
          value: category.id.value,
          label: masterData.categoryName(category.id.value) ?? category.name,
        ),
    ],
    onChanged: (value) => onChanged(value == '' ? null : value),
    onClear: value == null ? null : () => onChanged(null),
    clearTooltip: anyLabel,
  );
}

/// Nullable filter variant of the canonical payment-source selector.
class ButlerlyPaymentSourceFilter extends StatelessWidget {
  const ButlerlyPaymentSourceFilter({
    required this.sources,
    required this.value,
    required this.label,
    required this.anyLabel,
    required this.onChanged,
    super.key,
  });
  final List<PaymentSource> sources;
  final String? value;
  final String label;
  final String anyLabel;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => ButlerlySelectField<String>(
    label: label,
    value: value,
    entries: [
      DropdownMenuEntry(value: '', label: anyLabel),
      for (final source in sources.where(
        (value) => value.status == PaymentSourceStatus.active,
      ))
        DropdownMenuEntry(
          value: source.id.value,
          label: _paymentSourceText(source),
        ),
    ],
    onChanged: (value) => onChanged(value == '' ? null : value),
    onClear: value == null ? null : () => onChanged(null),
    clearTooltip: anyLabel,
  );
}

class ButlerlyDirectionFilter extends StatelessWidget {
  const ButlerlyDirectionFilter({
    required this.value,
    required this.label,
    required this.anyLabel,
    required this.onChanged,
    super.key,
  });
  final TransactionDirection? value;
  final String label;
  final String anyLabel;
  final ValueChanged<TransactionDirection?> onChanged;

  @override
  Widget build(BuildContext context) =>
      ButlerlySelectField<TransactionDirection>(
        label: label,
        value: value,
        entries: [
          DropdownMenuEntry(
            value: TransactionDirection.expense,
            label: context.l10n.text('expense'),
          ),
          DropdownMenuEntry(
            value: TransactionDirection.income,
            label: context.l10n.text('income'),
          ),
        ],
        onChanged: onChanged,
        onClear: value == null ? null : () => onChanged(null),
        clearTooltip: anyLabel,
      );
}

class ButlerlyCurrencyFilter extends StatelessWidget {
  const ButlerlyCurrencyFilter({
    required this.value,
    required this.label,
    required this.anyLabel,
    required this.onChanged,
    super.key,
  });
  final String? value;
  final String label;
  final String anyLabel;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => ButlerlySelectField<String>(
    label: label,
    value: value,
    entries: [
      for (final code in const ['USD', 'EUR', 'GBP', 'CAD', 'CNY', 'JPY'])
        DropdownMenuEntry(value: code, label: code),
    ],
    onChanged: onChanged,
    onClear: value == null ? null : () => onChanged(null),
    clearTooltip: anyLabel,
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

class ButlerlyReadOnlyTagList extends StatelessWidget {
  const ButlerlyReadOnlyTagList({
    required this.tagIds,
    required this.masterData,
    required this.label,
    required this.unavailableLabel,
    super.key,
  });
  final Iterable<String> tagIds;
  final TransactionMasterData masterData;
  final String label;
  final String unavailableLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    child: Text(
      tagIds.map((id) => masterData.tagName(id) ?? unavailableLabel).join(', '),
    ),
  );
}

class _ButlerlyTagPickerState extends State<ButlerlyTagPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tags = widget.tags.where((tag) => tag.status == TagStatus.active);
    final visible = tags.where((tag) {
      if (widget.selected.contains(tag.id.value)) return false;
      final label = widget.masterData.tagName(tag.id.value) ?? tag.name;
      return _query.trim().isEmpty ||
          label.toLowerCase().contains(_query.trim().toLowerCase());
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.onCreate == null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(widget.createLabel),
          ),
        if (widget.selected.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in widget.selected)
                InputChip(
                  label: Text(widget.masterData.tagName(id) ?? id),
                  tooltip: context.l10n.text('removeTag'),
                  onDeleted: () {
                    final next = {...widget.selected}..remove(id);
                    widget.onChanged(next);
                  },
                ),
            ],
          ),
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
