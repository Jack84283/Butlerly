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
    super.key,
  });
  final List<Category> categories;
  final TransactionMasterData masterData;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;

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
    super.key,
  });
  final List<Category> categories;
  final TransactionMasterData masterData;
  final String? parentId;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;

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
    super.key,
  });
  final List<Merchant> merchants;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;
  final VoidCallback? onCreate;

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
  );
}

class ButlerlyPaymentSourceSelector extends StatelessWidget {
  const ButlerlyPaymentSourceSelector({
    required this.sources,
    required this.value,
    required this.label,
    required this.onChanged,
    super.key,
  });
  final List<PaymentSource> sources;
  final String? value;
  final String label;
  final ValueChanged<String?> onChanged;

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
  );
}

class ButlerlyTagPicker extends StatelessWidget {
  const ButlerlyTagPicker({
    required this.tags,
    required this.masterData,
    required this.selected,
    required this.onChanged,
    super.key,
  });
  final List<Tag> tags;
  final TransactionMasterData masterData;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final tag in tags.where((tag) => tag.status == TagStatus.active))
        FilterChip(
          label: Text(masterData.tagName(tag.id.value) ?? tag.name),
          selected: selected.contains(tag.id.value),
          onSelected: (isSelected) {
            final next = {...selected};
            if (isSelected) {
              next.add(tag.id.value);
            } else {
              next.remove(tag.id.value);
            }
            onChanged(next);
          },
        ),
    ],
  );
}
