import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

String _paymentSourceText(PaymentSource source) => source.lastFour == null
    ? (source.displayIdentity ?? source.name)
    : '${source.displayIdentity ?? source.name} ••••${source.lastFour}';

enum ButlerlyDuplicateDecision { useExisting, continueAnyway, cancel }

final class ButlerlyDuplicateConfirmationResult {
  const ButlerlyDuplicateConfirmationResult({
    required this.decision,
    this.selectedTransactionId,
  });
  final ButlerlyDuplicateDecision decision;
  final String? selectedTransactionId;
}

/// Shared, workflow-neutral confirmation for strict duplicate candidates.
class ButlerlyDuplicateTransactionConfirmation extends StatefulWidget {
  const ButlerlyDuplicateTransactionConfirmation({
    required this.proposed,
    required this.candidates,
    required this.onDecision,
    this.paymentSourceLabels = const {},
    super.key,
  });
  final TransactionDto proposed;
  final List<DuplicateTransactionCandidate> candidates;
  final ValueChanged<ButlerlyDuplicateConfirmationResult> onDecision;
  final Map<String, String> paymentSourceLabels;

  @override
  State<ButlerlyDuplicateTransactionConfirmation> createState() =>
      _ButlerlyDuplicateTransactionConfirmationState();
}

class _ButlerlyDuplicateTransactionConfirmationState
    extends State<ButlerlyDuplicateTransactionConfirmation> {
  String? _selectedTransactionId;

  @override
  void initState() {
    super.initState();
    if (widget.candidates.length == 1) {
      _selectedTransactionId = widget.candidates.single.transaction.id;
    }
  }

  void _choose(ButlerlyDuplicateDecision decision) => widget.onDecision(
    ButlerlyDuplicateConfirmationResult(
      decision: decision,
      selectedTransactionId: decision == ButlerlyDuplicateDecision.useExisting
          ? _selectedTransactionId
          : null,
    ),
  );

  @override
  Widget build(BuildContext context) => ButlerlySheet(
    title: Semantics(
      liveRegion: true,
      header: true,
      child: Text(context.l10n.text('possibleDuplicate')),
    ),
    content: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.text('proposedTransaction')),
          _summary(widget.proposed),
          const SizedBox(height: ButlerlySpacing.standard),
          Text(context.l10n.text('existingTransactions')),
          for (final candidate in widget.candidates) ...[
            const Divider(),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              title: _summary(candidate.transaction),
              value: candidate.transaction.id,
              // ignore: deprecated_member_use
              groupValue: _selectedTransactionId,
              // ignore: deprecated_member_use
              onChanged: (value) =>
                  setState(() => _selectedTransactionId = value),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => _choose(ButlerlyDuplicateDecision.cancel),
        child: Text(context.l10n.text('cancel')),
      ),
      TextButton(
        onPressed: () => _choose(ButlerlyDuplicateDecision.continueAnyway),
        child: Text(context.l10n.text('continueAnyway')),
      ),
      FilledButton(
        onPressed: _selectedTransactionId == null
            ? null
            : () => _choose(ButlerlyDuplicateDecision.useExisting),
        child: Text(context.l10n.text('useExistingTransaction')),
      ),
    ],
  );
  Widget _summary(TransactionDto transaction) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      '${transaction.transactionDate ?? '—'} · ${localizedTransactionAmount(context, transaction.amount)} ${transaction.currency} · ${transaction.direction}\n'
      '${transaction.description ?? transaction.rawCounterparty ?? ''}'
      '${transaction.paymentSourceId == null || widget.paymentSourceLabels[transaction.paymentSourceId] == null ? '' : '\n${widget.paymentSourceLabels[transaction.paymentSourceId]}'}',
    ),
  );
}

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
      onChanged: onChanged,
      onClear: selected == null ? null : () => onChanged(null),
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
    required this.currencies,
    required this.value,
    required this.label,
    required this.anyLabel,
    required this.onChanged,
    super.key,
  });
  final Iterable<String> currencies;
  final String? value;
  final String label;
  final String anyLabel;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => ButlerlySelectField<String>(
    label: label,
    value: value,
    entries: [
      for (final code in currencies)
        DropdownMenuEntry(value: code, label: code),
    ],
    onChanged: onChanged,
    onClear: value == null ? null : () => onChanged(null),
    clearTooltip: anyLabel,
  );
}

class ButlerlyDirectionSelector extends StatelessWidget {
  const ButlerlyDirectionSelector({
    required this.value,
    required this.onChanged,
    required this.expenseLabel,
    required this.incomeLabel,
    super.key,
  });
  final TransactionDirection value;
  final ValueChanged<TransactionDirection> onChanged;
  final String expenseLabel;
  final String incomeLabel;

  @override
  Widget build(BuildContext context) => SegmentedButton<TransactionDirection>(
    showSelectedIcon: false,
    segments: [
      ButtonSegment(
        value: TransactionDirection.expense,
        label: Text(expenseLabel),
      ),
      ButtonSegment(
        value: TransactionDirection.income,
        label: Text(incomeLabel),
      ),
    ],
    selected: {value},
    onSelectionChanged: (selection) => onChanged(selection.single),
  );
}

class ButlerlyDateRangeFilter extends StatelessWidget {
  const ButlerlyDateRangeFilter({
    required this.from,
    required this.to,
    required this.fromLabel,
    required this.toLabel,
    required this.formatDate,
    required this.onFromChanged,
    required this.onToChanged,
    super.key,
  });
  final DateTime? from;
  final DateTime? to;
  final String fromLabel;
  final String toLabel;
  final String Function(DateTime) formatDate;
  final ValueChanged<DateTime?> onFromChanged;
  final ValueChanged<DateTime?> onToChanged;

  Future<void> _pick(BuildContext context, {required bool isFrom}) async {
    final value = await showDatePicker(
      context: context,
      firstDate: isFrom ? DateTime(2000) : (from ?? DateTime(2000)),
      lastDate: DateTime.now(),
      initialDate: (isFrom ? from : to) ?? DateTime.now(),
    );
    if (value != null) (isFrom ? onFromChanged : onToChanged)(value);
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _pick(context, isFrom: true),
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(from == null ? fromLabel : formatDate(from!)),
        ),
      ),
      const SizedBox(width: ButlerlySpacing.compact),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _pick(context, isFrom: false),
          icon: const Icon(Icons.event_outlined),
          label: Text(to == null ? toLabel : formatDate(to!)),
        ),
      ),
    ],
  );
}

class ButlerlyReviewFilter extends StatelessWidget {
  const ButlerlyReviewFilter({
    required this.value,
    required this.label,
    required this.onChanged,
    super.key,
  });
  final bool? value;
  final String label;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile.adaptive(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: value == true,
    onChanged: (next) => onChanged(next ? true : null),
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
    this.compact = false,
    this.maxVisible,
    super.key,
  });
  final Iterable<String> tagIds;
  final TransactionMasterData masterData;
  final String label;
  final String unavailableLabel;
  final bool compact;
  final int? maxVisible;

  @override
  Widget build(BuildContext context) {
    final labels = tagIds
        .map((id) => masterData.tagName(id) ?? unavailableLabel)
        .toList();
    final visible = maxVisible == null
        ? labels
        : labels.take(maxVisible!).toList();
    return Semantics(
      label: label,
      value: labels.isEmpty ? unavailableLabel : labels.join(', '),
      child: labels.isEmpty
          ? Text(unavailableLabel)
          : Wrap(
              spacing: compact ? 4 : 8,
              runSpacing: compact ? 2 : 4,
              children: [
                for (final item in visible)
                  Chip(
                    label: Text(item),
                    visualDensity: compact ? VisualDensity.compact : null,
                  ),
                if (visible.length < labels.length)
                  Chip(label: Text('+${labels.length - visible.length}')),
              ],
            ),
    );
  }
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
