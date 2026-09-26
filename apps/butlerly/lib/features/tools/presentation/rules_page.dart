import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  late Future<_RuleData> _data = _load();

  Future<_RuleData> _load() async {
    final finance = _finance;
    final list = finance?.listTransactionRules;
    if (finance == null || list == null) return const _RuleData.empty();
    final results = await Future.wait([
      list(),
      finance.listMerchants(),
      finance.listCategories(),
      finance.listPaymentSources(),
      finance.listTags(),
    ]);
    final rules = results[0];
    if (rules is! ApplicationSuccess<List<TransactionRule>>) {
      throw StateError('Rules could not be loaded.');
    }
    return _RuleData(
      rules.value,
      _valueOrEmpty<Merchant>(results[1]),
      _valueOrEmpty<Category>(results[2]),
      _valueOrEmpty<PaymentSource>(results[3]),
      _valueOrEmpty<Tag>(results[4]),
    );
  }

  List<T> _valueOrEmpty<T>(Object result) => switch (result) {
    ApplicationSuccess<List<T>>(:final value) => value,
    _ => <T>[],
  };

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _data = _load();
    });
  }

  Future<void> _edit(_RuleData data, [TransactionRule? current]) async {
    final draft = await showButlerlyBottomSheet<_RuleDraft>(
      context: context,
      builder: (_) => _RuleEditorSheet(
        current: current,
        merchants: data.merchants,
        categories: data.categories,
        paymentSources: data.paymentSources,
        tags: data.tags,
      ),
    );
    if (!mounted || draft == null) return;
    final finance = _finance;
    final save = finance?.saveTransactionRule;
    if (save == null) return;
    final now = DateTime.now().toUtc();
    final rule = TransactionRule(
      id:
          current?.id ??
          TransactionRuleId('user.rule.${now.microsecondsSinceEpoch}'),
      name: draft.name,
      description: draft.description,
      enabled: current?.enabled ?? true,
      priority: draft.priority,
      merchantId: _id<MerchantId>(draft.conditionMerchantId, MerchantId.new),
      categoryId: _id<CategoryId>(draft.conditionCategoryId, CategoryId.new),
      paymentSourceId: _id<PaymentSourceId>(
        draft.conditionPaymentSourceId,
        PaymentSourceId.new,
      ),
      tagId: _id<TagId>(draft.conditionTagId, TagId.new),
      descriptionContains: draft.descriptionContains,
      rawCounterpartyContains: draft.rawCounterpartyContains,
      assignMerchantId: _id<MerchantId>(draft.assignMerchantId, MerchantId.new),
      assignCategoryId: _id<CategoryId>(draft.assignCategoryId, CategoryId.new),
      assignSubcategoryId: _id<CategoryId>(
        draft.assignSubcategoryId,
        CategoryId.new,
      ),
      assignPaymentSourceId: _id<PaymentSourceId>(
        draft.assignPaymentSourceId,
        PaymentSourceId.new,
      ),
      assignTagId: _id<TagId>(draft.assignTagId, TagId.new),
      createdAt: current?.createdAt ?? now,
      updatedAt: now,
    );
    final result = await save(rule);
    if (!mounted) return;
    if (result is ApplicationFailure) {
      _showMessage(context.l10n.text('ruleSaveFailed'));
      return;
    }
    _showMessage(context.l10n.text('ruleSaved'));
    _refresh();
  }

  Future<void> _toggle(TransactionRule rule, bool enabled) async {
    final action = _finance?.setTransactionRuleEnabled;
    if (action == null) return;
    final result = await action(rule, enabled);
    if (!mounted) return;
    if (result is ApplicationFailure) {
      _showMessage(context.l10n.text('ruleSaveFailed'));
      return;
    }
    _refresh();
  }

  Future<void> _delete(TransactionRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.text('deleteRuleTitle')),
        content: Text(context.l10n.text('deleteRuleBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.text('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await _finance?.deleteTransactionRule?.call(rule.id.value);
    if (!mounted) return;
    if (result is ApplicationFailure) {
      _showMessage(context.l10n.text('ruleDeleteFailed'));
      return;
    }
    _showMessage(context.l10n.text('ruleDeleted'));
    _refresh();
  }

  void _showDetails(_RuleData data, TransactionRule rule) {
    showButlerlyBottomSheet<void>(
      context: context,
      builder: (context) => ButlerlySheet(
        title: Text(rule.name),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rule.description?.isNotEmpty == true
                  ? rule.description!
                  : context.l10n.text('ruleNoDescription'),
            ),
            const SizedBox(height: ButlerlySpacing.standard),
            Text(context.l10n.text('ruleConditions')),
            Text(_conditions(context, data, rule)),
            const SizedBox(height: ButlerlySpacing.standard),
            Text(context.l10n.text('ruleActions')),
            Text(_actions(context, data, rule)),
            const SizedBox(height: ButlerlySpacing.standard),
            Text('${context.l10n.text('rulePriority')}: ${rule.priority}'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('close')),
          ),
        ],
      ),
    );
  }

  String _conditions(
    BuildContext context,
    _RuleData data,
    TransactionRule rule,
  ) {
    final values = <String>[];
    if (rule.merchantId != null) {
      values.add(
        '${context.l10n.text('merchant')}: ${data.merchantName(rule.merchantId!)}',
      );
    }
    if (rule.categoryId != null) {
      values.add(
        '${context.l10n.text('category')}: ${data.categoryName(rule.categoryId!)}',
      );
    }
    if (rule.paymentSourceId != null) {
      values.add(
        '${context.l10n.text('paymentSource')}: ${data.paymentSourceName(rule.paymentSourceId!)}',
      );
    }
    if (rule.tagId != null) {
      values.add('${context.l10n.text('tag')}: ${data.tagName(rule.tagId!)}');
    }
    if (rule.descriptionContains != null) {
      values.add(rule.descriptionContains!);
    }
    if (rule.rawCounterpartyContains != null) {
      values.add(rule.rawCounterpartyContains!);
    }
    return values.join(' · ');
  }

  String _actions(BuildContext context, _RuleData data, TransactionRule rule) {
    final values = <String>[];
    if (rule.assignMerchantId != null) {
      values.add(
        '${context.l10n.text('merchant')}: ${data.merchantName(rule.assignMerchantId!)}',
      );
    }
    if (rule.assignCategoryId != null) {
      values.add(
        '${context.l10n.text('category')}: ${data.categoryName(rule.assignCategoryId!)}',
      );
    }
    if (rule.assignSubcategoryId != null) {
      values.add(
        '${context.l10n.text('subcategory')}: ${data.categoryName(rule.assignSubcategoryId!)}',
      );
    }
    if (rule.assignPaymentSourceId != null) {
      values.add(
        '${context.l10n.text('paymentSource')}: ${data.paymentSourceName(rule.assignPaymentSourceId!)}',
      );
    }
    if (rule.assignTagId != null) {
      values.add(
        '${context.l10n.text('tag')}: ${data.tagName(rule.assignTagId!)}',
      );
    }
    return values.join(' · ');
  }

  void _showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => FutureBuilder<_RuleData>(
    future: _data,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const ButlerlyLoadingState();
      }
      if (snapshot.hasError) {
        return ButlerlyErrorState(
          title: context.l10n.text('ruleManagement'),
          message: context.l10n.text('tryAgain'),
          preserved: context.l10n.text('dataPreserved'),
          actionLabel: context.l10n.text('tryAgain'),
          onAction: _refresh,
        );
      }
      final data = snapshot.requireData;
      return ButlerlyPage(
        title: context.l10n.text('ruleManagement'),
        subtitle: context.l10n.text('ruleManagementSubtitle'),
        actions: [
          IconButton(
            tooltip: context.l10n.text('addRule'),
            onPressed: () => _edit(data),
            icon: const Icon(Icons.add_rounded),
          ),
        ],
        children: [
          if (data.rules.isEmpty)
            ButlerlyEmptyState(
              icon: Icons.rule_outlined,
              title: context.l10n.text('noRules'),
              message: context.l10n.text('noRulesBody'),
              actionLabel: context.l10n.text('addRule'),
              onAction: () => _edit(data),
            )
          else
            Column(
              children: [
                for (final rule in data.rules)
                  _RuleCard(
                    rule: rule,
                    conditions: _conditions(context, data, rule),
                    actions: _actions(context, data, rule),
                    onDetails: () => _showDetails(data, rule),
                    onToggle: (value) => _toggle(rule, value),
                    onEdit: () => _edit(data, rule),
                    onDelete: () => _delete(rule),
                  ),
              ],
            ),
          const SizedBox(height: ButlerlySpacing.structural),
        ],
      );
    },
  );
}

T? _id<T>(String? value, T Function(String) create) =>
    value == null || value.isEmpty ? null : create(value);

final class _RuleData {
  const _RuleData(
    this.rules,
    this.merchants,
    this.categories,
    this.paymentSources,
    this.tags,
  );

  const _RuleData.empty()
    : rules = const [],
      merchants = const [],
      categories = const [],
      paymentSources = const [],
      tags = const [];

  final List<TransactionRule> rules;
  final List<Merchant> merchants;
  final List<Category> categories;
  final List<PaymentSource> paymentSources;
  final List<Tag> tags;

  String merchantName(MerchantId id) =>
      merchants.where((value) => value.id == id).firstOrNull?.name ?? id.value;
  String categoryName(CategoryId id) =>
      categories.where((value) => value.id == id).firstOrNull?.name ?? id.value;
  String paymentSourceName(PaymentSourceId id) =>
      paymentSources.where((value) => value.id == id).firstOrNull?.name ??
      id.value;
  String tagName(TagId id) =>
      tags.where((value) => value.id == id).firstOrNull?.name ?? id.value;
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.conditions,
    required this.actions,
    required this.onDetails,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final TransactionRule rule;
  final String conditions;
  final String actions;
  final VoidCallback onDetails;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: ButlerlySpacing.standard),
    child: ButlerlyCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        onTap: onDetails,
        leading: ButlerlyActionIcon(
          icon: rule.enabled ? Icons.rule_rounded : Icons.rule_folder_outlined,
        ),
        title: Text(rule.name),
        subtitle: Text('$conditions\n$actions'),
        isThreeLine: true,
        trailing: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 0,
          children: [
            Switch.adaptive(value: rule.enabled, onChanged: onToggle),
            IconButton(
              tooltip: context.l10n.text('edit'),
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: context.l10n.text('delete'),
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    ),
  );
}

final class _RuleDraft {
  const _RuleDraft({
    required this.name,
    required this.description,
    required this.priority,
    this.conditionMerchantId,
    this.conditionCategoryId,
    this.conditionPaymentSourceId,
    this.conditionTagId,
    this.descriptionContains,
    this.rawCounterpartyContains,
    this.assignMerchantId,
    this.assignCategoryId,
    this.assignSubcategoryId,
    this.assignPaymentSourceId,
    this.assignTagId,
  });

  final String name;
  final String? description;
  final int priority;
  final String? conditionMerchantId;
  final String? conditionCategoryId;
  final String? conditionPaymentSourceId;
  final String? conditionTagId;
  final String? descriptionContains;
  final String? rawCounterpartyContains;
  final String? assignMerchantId;
  final String? assignCategoryId;
  final String? assignSubcategoryId;
  final String? assignPaymentSourceId;
  final String? assignTagId;
}

class _RuleEditorSheet extends StatefulWidget {
  const _RuleEditorSheet({
    required this.current,
    required this.merchants,
    required this.categories,
    required this.paymentSources,
    required this.tags,
  });

  final TransactionRule? current;
  final List<Merchant> merchants;
  final List<Category> categories;
  final List<PaymentSource> paymentSources;
  final List<Tag> tags;

  @override
  State<_RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends State<_RuleEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _priority;
  late final TextEditingController _descriptionContains;
  late final TextEditingController _rawCounterpartyContains;
  String? _conditionMerchantId;
  String? _conditionCategoryId;
  String? _conditionPaymentSourceId;
  String? _conditionTagId;
  String? _assignMerchantId;
  String? _assignCategoryId;
  String? _assignSubcategoryId;
  String? _assignPaymentSourceId;
  String? _assignTagId;

  @override
  void initState() {
    super.initState();
    final value = widget.current;
    _name = TextEditingController(text: value?.name);
    _description = TextEditingController(text: value?.description);
    _priority = TextEditingController(text: '${value?.priority ?? 0}');
    _descriptionContains = TextEditingController(
      text: value?.descriptionContains,
    );
    _rawCounterpartyContains = TextEditingController(
      text: value?.rawCounterpartyContains,
    );
    _conditionMerchantId = value?.merchantId?.value;
    _conditionCategoryId = value?.categoryId?.value;
    _conditionPaymentSourceId = value?.paymentSourceId?.value;
    _conditionTagId = value?.tagId?.value;
    _assignMerchantId = value?.assignMerchantId?.value;
    _assignCategoryId = value?.assignCategoryId?.value;
    _assignSubcategoryId = value?.assignSubcategoryId?.value;
    _assignPaymentSourceId = value?.assignPaymentSourceId?.value;
    _assignTagId = value?.assignTagId?.value;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _priority.dispose();
    _descriptionContains.dispose();
    _rawCounterpartyContains.dispose();
    super.dispose();
  }

  void _save() {
    final hasCondition =
        _conditionMerchantId != null ||
        _conditionCategoryId != null ||
        _conditionPaymentSourceId != null ||
        _conditionTagId != null ||
        _descriptionContains.text.trim().isNotEmpty ||
        _rawCounterpartyContains.text.trim().isNotEmpty;
    final hasAction =
        _assignMerchantId != null ||
        _assignCategoryId != null ||
        _assignSubcategoryId != null ||
        _assignPaymentSourceId != null ||
        _assignTagId != null;
    if (_name.text.trim().isEmpty || !hasCondition || !hasAction) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('ruleNeedsConditionAction'))),
      );
      return;
    }
    Navigator.pop(
      context,
      _RuleDraft(
        name: _name.text.trim(),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        priority: int.tryParse(_priority.text.trim()) ?? 0,
        conditionMerchantId: _conditionMerchantId,
        conditionCategoryId: _conditionCategoryId,
        conditionPaymentSourceId: _conditionPaymentSourceId,
        conditionTagId: _conditionTagId,
        descriptionContains: _optional(_descriptionContains.text),
        rawCounterpartyContains: _optional(_rawCounterpartyContains.text),
        assignMerchantId: _assignMerchantId,
        assignCategoryId: _assignCategoryId,
        assignSubcategoryId: _assignSubcategoryId,
        assignPaymentSourceId: _assignPaymentSourceId,
        assignTagId: _assignTagId,
      ),
    );
  }

  String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

  List<DropdownMenuItem<String?>> _items(
    BuildContext context,
    String empty,
    Iterable<(String, String)> values,
  ) => [
    DropdownMenuItem<String?>(value: null, child: Text(empty)),
    for (final (id, label) in values)
      DropdownMenuItem<String?>(value: id, child: Text(label)),
  ];

  Widget _dropdown(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
    List<DropdownMenuItem<String?>> items,
  ) => DropdownButtonFormField<String?>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: items,
    onChanged: onChanged,
  );

  @override
  Widget build(BuildContext context) {
    final empty = context.l10n.text('notSet');
    final merchants = widget.merchants.map(
      (value) => (value.id.value, value.name),
    );
    final categories = widget.categories.map(
      (value) => (value.id.value, value.name),
    );
    final sources = widget.paymentSources.map(
      (value) => (value.id.value, value.name),
    );
    final tags = widget.tags.map((value) => (value.id.value, value.name));
    return ButlerlySheet(
      title: Text(
        context.l10n.text(widget.current == null ? 'addRule' : 'editRule'),
      ),
      content: Column(
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: context.l10n.text('ruleName'),
            ),
          ),
          TextField(
            controller: _description,
            decoration: InputDecoration(
              labelText: context.l10n.text('ruleDescription'),
            ),
          ),
          TextField(
            controller: _priority,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: context.l10n.text('rulePriority'),
            ),
          ),
          const SizedBox(height: ButlerlySpacing.standard),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(context.l10n.text('ruleConditions')),
          ),
          _dropdown(
            context.l10n.text('merchant'),
            _conditionMerchantId,
            (v) => setState(() => _conditionMerchantId = v),
            _items(context, empty, merchants),
          ),
          _dropdown(
            context.l10n.text('category'),
            _conditionCategoryId,
            (v) => setState(() => _conditionCategoryId = v),
            _items(context, empty, categories),
          ),
          _dropdown(
            context.l10n.text('paymentSource'),
            _conditionPaymentSourceId,
            (v) => setState(() => _conditionPaymentSourceId = v),
            _items(context, empty, sources),
          ),
          _dropdown(
            context.l10n.text('tag'),
            _conditionTagId,
            (v) => setState(() => _conditionTagId = v),
            _items(context, empty, tags),
          ),
          TextField(
            controller: _descriptionContains,
            decoration: InputDecoration(
              labelText: context.l10n.text('ruleDescriptionContains'),
            ),
          ),
          TextField(
            controller: _rawCounterpartyContains,
            decoration: InputDecoration(
              labelText: context.l10n.text('ruleCounterpartyContains'),
            ),
          ),
          const SizedBox(height: ButlerlySpacing.standard),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(context.l10n.text('ruleActions')),
          ),
          _dropdown(
            context.l10n.text('merchant'),
            _assignMerchantId,
            (v) => setState(() => _assignMerchantId = v),
            _items(context, empty, merchants),
          ),
          _dropdown(
            context.l10n.text('category'),
            _assignCategoryId,
            (v) => setState(() => _assignCategoryId = v),
            _items(context, empty, categories),
          ),
          _dropdown(
            context.l10n.text('subcategory'),
            _assignSubcategoryId,
            (v) => setState(() => _assignSubcategoryId = v),
            _items(context, empty, categories),
          ),
          _dropdown(
            context.l10n.text('paymentSource'),
            _assignPaymentSourceId,
            (v) => setState(() => _assignPaymentSourceId = v),
            _items(context, empty, sources),
          ),
          _dropdown(
            context.l10n.text('tag'),
            _assignTagId,
            (v) => setState(() => _assignTagId = v),
            _items(context, empty, tags),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.text('cancel')),
        ),
        FilledButton(onPressed: _save, child: Text(context.l10n.text('save'))),
      ],
    );
  }
}
