import 'package:butlerly/app/shell/adaptive_shell.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_action_group.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/components/butlerly_transaction_inner_card.dart';
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
  String? _selectedDesktopRuleId;
  bool _desktopEditing = false;
  bool _desktopCreating = false;

  bool get _isDesktop =>
      effectiveButlerlyLayoutMode(context, MediaQuery.sizeOf(context).width) ==
      ButlerlyLayoutMode.wide;

  void _closeEditor() => setState(() {
    _desktopEditing = false;
    _desktopCreating = false;
  });

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
    if (_isDesktop) {
      setState(() {
        _selectedDesktopRuleId = current?.id.value;
        _desktopCreating = current == null;
        _desktopEditing = true;
      });
      return;
    }
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
    await _saveDraft(draft, current);
  }

  Future<void> _saveDraft(_RuleDraft draft, TransactionRule? current) async {
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
    if (_desktopEditing) {
      setState(() {
        _selectedDesktopRuleId = rule.id.value;
        _desktopEditing = false;
        _desktopCreating = false;
      });
    }
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
    final confirmed = await showButlerlyConfirmationSheet(
      context: context,
      title: context.l10n.text('deleteRuleTitle'),
      message: context.l10n.text('deleteRuleBody'),
      cancelLabel: context.l10n.text('cancel'),
      confirmLabel: context.l10n.text('delete'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final result = await _finance?.deleteTransactionRule?.call(rule.id.value);
    if (!mounted) return;
    if (result is ApplicationFailure) {
      _showMessage(context.l10n.text('ruleDeleteFailed'));
      return;
    }
    if (_selectedDesktopRuleId == rule.id.value) {
      _selectedDesktopRuleId = null;
    }
    _showMessage(context.l10n.text('ruleDeleted'));
    _refresh();
  }

  void _showDetails(_RuleData data, TransactionRule rule) {
    showButlerlyBottomSheet<void>(
      context: context,
      builder: (context) => ButlerlySheet(
        title: Text(rule.name),
        content: _RuleDetailsContent(
          rule: rule,
          conditions: _conditions(context, data, rule),
          actions: _actions(context, data, rule),
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

  void _selectDesktopRule(TransactionRule rule) {
    setState(() {
      _selectedDesktopRuleId = rule.id.value;
      _desktopEditing = false;
      _desktopCreating = false;
    });
  }

  void _closeDesktopDetails() {
    setState(() {
      _selectedDesktopRuleId = null;
      _desktopEditing = false;
    });
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
      final desktop =
          effectiveButlerlyLayoutMode(
            context,
            MediaQuery.sizeOf(context).width,
          ) ==
          ButlerlyLayoutMode.wide;
      final selectedDesktopRule = desktop && _selectedDesktopRuleId != null
          ? data.rules
                .where((rule) => rule.id.value == _selectedDesktopRuleId)
                .firstOrNull
          : null;
      return ButlerlyPage(
        title: context.l10n.text('ruleManagement'),
        subtitle: context.l10n.text('ruleManagementHowItWorks'),
        fullWidth: desktop,
        actions: [
          ButlerlyHeaderAddButton(
            buttonKey: const ValueKey('rules-add'),
            label: context.l10n.text('addRule'),
            onPressed: () => _edit(data),
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
          else if (desktop)
            LayoutBuilder(
              key: const ValueKey('desktop-rules-workspace'),
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _RulesDesktopTable(
                      rules: data.rules,
                      conditions: (rule) => _conditions(context, data, rule),
                      actions: (rule) => _actions(context, data, rule),
                      onDetails: _selectDesktopRule,
                      onToggle: _toggle,
                      onEdit: (rule) => _edit(data, rule),
                      onDelete: _delete,
                    ),
                  ),
                  if (_desktopEditing || selectedDesktopRule != null) ...[
                    const SizedBox(width: ButlerlySpacing.cardGap),
                    SizedBox(
                      width: constraints.maxWidth < 1100 ? 320 : 400,
                      child: _desktopEditing
                          ? SizedBox(
                              height: MediaQuery.sizeOf(context).height * 0.75,
                              child: _RuleEditorSheet(
                                key: ValueKey(
                                  'rule-editor-${selectedDesktopRule?.id.value ?? 'new'}',
                                ),
                                current: selectedDesktopRule,
                                merchants: data.merchants,
                                categories: data.categories,
                                paymentSources: data.paymentSources,
                                tags: data.tags,
                                onSubmit: (draft) =>
                                    _saveDraft(draft, selectedDesktopRule),
                                onCancel: _closeEditor,
                              ),
                            )
                          : _RuleDesktopDetailsPanel(
                              rule: selectedDesktopRule!,
                              conditions: _conditions(
                                context,
                                data,
                                selectedDesktopRule!,
                              ),
                              actions: _actions(
                                context,
                                data,
                                selectedDesktopRule!,
                              ),
                              onClose: _closeDesktopDetails,
                              onEdit: () => _edit(data, selectedDesktopRule!),
                            ),
                    ),
                  ],
                ],
              ),
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

/// Contextual rule details on desktop. This panel does not push a route or
/// open a modal, so users can select another row without dismissing it first.
class _RuleDesktopDetailsPanel extends StatelessWidget {
  const _RuleDesktopDetailsPanel({
    required this.rule,
    required this.conditions,
    required this.actions,
    required this.onClose,
    required this.onEdit,
  });

  final TransactionRule rule;
  final String conditions;
  final String actions;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => ButlerlyCard(
    key: const ValueKey('desktop-rule-details-panel'),
    semanticLabel: rule.name,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ButlerlyCardHeader(
          title: rule.name,
          action: IconButton(
            key: const ValueKey('desktop-rule-details-close'),
            tooltip: context.l10n.text('close'),
            onPressed: onClose,
            icon: const Icon(Icons.close),
            iconSize: 20,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(height: ButlerlySpacing.standard),
        _RuleDetailsContent(
          rule: rule,
          conditions: conditions,
          actions: actions,
        ),
        const SizedBox(height: ButlerlySpacing.standard),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            key: const ValueKey('desktop-rule-details-edit'),
            onPressed: onEdit,
            child: Text(context.l10n.text('edit')),
          ),
        ),
      ],
    ),
  );
}

/// Keep the desktop side panel and device bottom sheet content in sync.
class _RuleDetailsContent extends StatelessWidget {
  const _RuleDetailsContent({
    required this.rule,
    required this.conditions,
    required this.actions,
  });

  final TransactionRule rule;
  final String conditions;
  final String actions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        rule.description?.isNotEmpty == true
            ? rule.description!
            : context.l10n.text('ruleNoDescription'),
      ),
      const SizedBox(height: ButlerlySpacing.standard),
      Text(context.l10n.text('ruleConditions')),
      Text(conditions),
      const SizedBox(height: ButlerlySpacing.standard),
      Text(context.l10n.text('ruleActions')),
      Text(actions),
      const SizedBox(height: ButlerlySpacing.standard),
      Text('${context.l10n.text('rulePriority')}: ${rule.priority}'),
    ],
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

/// Full-width desktop rules table, using the same inset surface, dividers
/// and horizontal overflow behavior as the Home and Transactions tables.
class _RulesDesktopTable extends StatelessWidget {
  const _RulesDesktopTable({
    required this.rules,
    required this.conditions,
    required this.actions,
    required this.onDetails,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  static const double minimumWidth = 1000;
  static const double priorityWidth = 76;
  static const double statusWidth = 88;
  static const double controlsWidth = 116;

  final List<TransactionRule> rules;
  final String Function(TransactionRule) conditions;
  final String Function(TransactionRule) actions;
  final ValueChanged<TransactionRule> onDetails;
  final void Function(TransactionRule, bool) onToggle;
  final ValueChanged<TransactionRule> onEdit;
  final ValueChanged<TransactionRule> onDelete;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ButlerlyCard(
      padding: const EdgeInsets.all(ButlerlyDesktopInnerCard.outerGutter),
      child: ButlerlyDesktopInnerCard(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final table = Column(
              key: const ValueKey('desktop-rules-table'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(flex: 3, child: _header(context, 'name')),
                    Expanded(
                      flex: 3,
                      child: _header(context, 'ruleConditions'),
                    ),
                    Expanded(flex: 3, child: _header(context, 'ruleActions')),
                    SizedBox(
                      width: priorityWidth,
                      child: _header(
                        context,
                        'rulePriority',
                        align: TextAlign.end,
                      ),
                    ),
                    SizedBox(
                      width: statusWidth,
                      child: _header(
                        context,
                        'status',
                        align: TextAlign.center,
                      ),
                    ),
                    SizedBox(
                      width: controlsWidth,
                      child: Text(
                        '${context.l10n.text('edit')} / ${context.l10n.text('delete')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ButlerlyTableTokens.headerTextStyle(context),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: ButlerlyTableTokens.headerToRowsGap),
                _divider(context),
                for (final rule in rules) ...[
                  _row(context, rule),
                  _divider(context),
                ],
              ],
            );
            if (constraints.maxWidth >= minimumWidth) return table;
            return SingleChildScrollView(
              key: const ValueKey('desktop-rules-table-horizontal-scroll'),
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: minimumWidth, child: table),
            );
          },
        ),
      ),
    ),
  );

  Widget _header(
    BuildContext context,
    String key, {
    TextAlign align = TextAlign.start,
  }) => Text(
    context.l10n.text(key),
    style: ButlerlyTableTokens.headerTextStyle(context),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    textAlign: align,
  );

  Widget _divider(BuildContext context) => Divider(
    height: ButlerlyTableTokens.dividerThickness,
    thickness: ButlerlyTableTokens.dividerThickness,
    color: ButlerlyTableTokens.dividerColor(context),
  );

  Widget _cell(
    BuildContext context,
    String value, {
    FontWeight? weight,
    TextAlign align = TextAlign.start,
  }) => Tooltip(
    message: value,
    child: Text(
      value.isEmpty ? '—' : value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(fontWeight: weight),
    ),
  );

  Widget _row(BuildContext context, TransactionRule rule) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      key: ValueKey('desktop-rule-row-${rule.id.value}'),
      onTap: () => onDetails(rule),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: ButlerlyTableTokens.rowVerticalPadding,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 3,
              child: _cell(context, rule.name, weight: FontWeight.w600),
            ),
            Expanded(flex: 3, child: _cell(context, conditions(rule))),
            Expanded(flex: 3, child: _cell(context, actions(rule))),
            SizedBox(
              width: priorityWidth,
              child: _cell(context, '${rule.priority}', align: TextAlign.end),
            ),
            SizedBox(
              width: statusWidth,
              child: Center(
                child: SizedBox(
                  key: ValueKey('desktop-rule-switch-box-${rule.id.value}'),
                  width: 44,
                  height: 20,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Switch.adaptive(
                      key: ValueKey('desktop-rule-switch-${rule.id.value}'),
                      value: rule.enabled,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onChanged: (enabled) => onToggle(rule, enabled),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: controlsWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ButlerlyDesktopTableIconAction(
                    buttonKey: ValueKey('desktop-rule-edit-${rule.id.value}'),
                    icon: Icons.edit_outlined,
                    tooltip: context.l10n.text('edit'),
                    onPressed: () => onEdit(rule),
                  ),
                  const SizedBox(width: ButlerlySpacing.small),
                  ButlerlyDesktopTableIconAction(
                    buttonKey: ValueKey('desktop-rule-delete-${rule.id.value}'),
                    icon: Icons.delete_outline,
                    tooltip: context.l10n.text('delete'),
                    onPressed: () => onDelete(rule),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
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
    this.onSubmit,
    this.onCancel,
    super.key,
  });

  final ValueChanged<_RuleDraft>? onSubmit;
  final VoidCallback? onCancel;
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
  TransactionRulePreview? _testResult;
  bool _testing = false;
  bool _testFailed = false;

  void _invalidatePreview() {
    if (!mounted) return;
    setState(() {
      _testResult = null;
      _testFailed = false;
    });
  }

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
    _descriptionContains.addListener(_invalidatePreview);
    _rawCounterpartyContains.addListener(_invalidatePreview);
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
    final draft = _RuleDraft(
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
    );
    if (widget.onSubmit != null) {
      widget.onSubmit!(draft);
    } else {
      Navigator.pop(context, draft);
    }
  }

  String _merchantName(String id) =>
      widget.merchants.where((m) => m.id.value == id).firstOrNull?.name ?? id;

  String _categoryName(String id) =>
      widget.categories.where((c) => c.id.value == id).firstOrNull?.name ?? id;

  String _sourceName(String id) =>
      widget.paymentSources.where((p) => p.id.value == id).firstOrNull?.name ??
      id;

  String _tagName(String id) =>
      widget.tags.where((t) => t.id.value == id).firstOrNull?.name ?? id;

  String _conditionSummary(BuildContext context) {
    final terms = <String>[];
    final l10n = context.l10n;
    if (_conditionMerchantId case final String value) {
      terms.add("${l10n.text('merchant')} = ${_merchantName(value)}");
    }
    if (_conditionCategoryId case final String value) {
      terms.add("${l10n.text('category')} = ${_categoryName(value)}");
    }
    if (_conditionPaymentSourceId case final String value) {
      terms.add("${l10n.text('paymentSource')} = ${_sourceName(value)}");
    }
    if (_conditionTagId case final String value) {
      terms.add("${l10n.text('tag')} = ${_tagName(value)}");
    }
    if (_optional(_descriptionContains.text) case final String value) {
      terms.add("${l10n.text('rulePreviewDescription')} \"$value\"");
    }
    if (_optional(_rawCounterpartyContains.text) case final String value) {
      terms.add("${l10n.text('rulePreviewMerchantText')} \"$value\"");
    }
    return terms.isEmpty
        ? l10n.text('rulePreviewNoCondition')
        : terms.join(' ${l10n.text('rulePreviewAnd')} ');
  }

  String _actionSummary(BuildContext context) {
    final terms = <String>[];
    final l10n = context.l10n;
    if (_assignMerchantId case final String value) {
      terms.add("${l10n.text('merchant')} = ${_merchantName(value)}");
    }
    if (_assignCategoryId case final String value) {
      terms.add("${l10n.text('category')} = ${_categoryName(value)}");
    }
    if (_assignSubcategoryId case final String value) {
      terms.add("${l10n.text('subcategory')} = ${_categoryName(value)}");
    }
    if (_assignPaymentSourceId case final String value) {
      terms.add("${l10n.text('paymentSource')} = ${_sourceName(value)}");
    }
    if (_assignTagId case final String value) {
      terms.add("${l10n.text('tag')} = ${_tagName(value)}");
    }
    return terms.isEmpty
        ? l10n.text('rulePreviewNoAction')
        : terms.join(' ${l10n.text('rulePreviewAnd')} ');
  }

  Future<void> _testRule() async {
    final hasCondition =
        _conditionMerchantId != null ||
        _conditionCategoryId != null ||
        _conditionPaymentSourceId != null ||
        _conditionTagId != null ||
        _optional(_descriptionContains.text) != null ||
        _optional(_rawCounterpartyContains.text) != null;
    final hasAction =
        _assignMerchantId != null ||
        _assignCategoryId != null ||
        _assignSubcategoryId != null ||
        _assignPaymentSourceId != null ||
        _assignTagId != null;
    if (!hasCondition || !hasAction) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.text('ruleNeedsConditionAction'))),
      );
      return;
    }
    final preview = services.isRegistered<FinanceServices>()
        ? services<FinanceServices>().previewTransactionRule
        : null;
    if (preview == null) {
      setState(() => _testFailed = true);
      return;
    }
    final now = DateTime.now().toUtc();
    final rule = TransactionRule(
      id: widget.current?.id ?? TransactionRuleId('preview.rule'),
      name: _name.text.trim().isEmpty ? 'Preview' : _name.text.trim(),
      enabled: true, // Preview also works while editing disabled rules.
      merchantId: _id<MerchantId>(_conditionMerchantId, MerchantId.new),
      categoryId: _id<CategoryId>(_conditionCategoryId, CategoryId.new),
      paymentSourceId: _id<PaymentSourceId>(
        _conditionPaymentSourceId,
        PaymentSourceId.new,
      ),
      tagId: _id<TagId>(_conditionTagId, TagId.new),
      descriptionContains: _optional(_descriptionContains.text),
      rawCounterpartyContains: _optional(_rawCounterpartyContains.text),
      assignMerchantId: _id<MerchantId>(_assignMerchantId, MerchantId.new),
      assignCategoryId: _id<CategoryId>(_assignCategoryId, CategoryId.new),
      assignSubcategoryId: _id<CategoryId>(
        _assignSubcategoryId,
        CategoryId.new,
      ),
      assignPaymentSourceId: _id<PaymentSourceId>(
        _assignPaymentSourceId,
        PaymentSourceId.new,
      ),
      assignTagId: _id<TagId>(_assignTagId, TagId.new),
      createdAt: widget.current?.createdAt ?? now,
      updatedAt: now,
    );
    setState(() {
      _testing = true;
      _testResult = null;
      _testFailed = false;
    });
    final result = await preview(rule);
    if (!mounted) return;
    setState(() {
      _testing = false;
      if (result is ApplicationSuccess<TransactionRulePreview>) {
        _testResult = result.value;
      } else {
        _testFailed = true;
      }
    });
  }

  Widget _previewCard(BuildContext context) => ButlerlyCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "${context.l10n.text('rulePreviewIf')}: ${_conditionSummary(context)}",
          key: const ValueKey('rule-preview-conditions'),
        ),
        const SizedBox(height: ButlerlySpacing.small),
        Text(
          "${context.l10n.text('rulePreviewThen')}: ${_actionSummary(context)}",
          key: const ValueKey('rule-preview-actions'),
        ),
        const SizedBox(height: ButlerlySpacing.small),
        Text(
          context.l10n.text('rulePreviewReadOnly'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_testing) ...[
          const SizedBox(height: ButlerlySpacing.small),
          const LinearProgressIndicator(),
        ],
        if (_testFailed) ...[
          const SizedBox(height: ButlerlySpacing.small),
          Text(context.l10n.text('rulePreviewFailed')),
        ],
        if (_testResult case final TransactionRulePreview result) ...[
          const SizedBox(height: ButlerlySpacing.small),
          Text(
            "${context.l10n.text('rulePreviewMatchCount')}: "
            "${result.matchCount} / ${result.scannedCount}",
            key: const ValueKey('rule-test-result'),
          ),
          if (result.examples.isEmpty)
            Text(context.l10n.text('rulePreviewNoMatches'))
          else ...[
            const SizedBox(height: ButlerlySpacing.small),
            Text(context.l10n.text('rulePreviewExamples')),
            for (final example in result.examples)
              Text('• $example', maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ],
    ),
  );

  String? _optional(String value) => value.trim().isEmpty ? null : value.trim();

  List<DropdownMenuEntry<String>> _entries(
    String empty,
    Iterable<(String, String)> values,
  ) => [
    DropdownMenuEntry<String>(value: '', label: empty),
    for (final (id, label) in values)
      DropdownMenuEntry<String>(value: id, label: label),
  ];

  Iterable<(String, String)> _rootCategories(String? selectedId) => widget
      .categories
      .where(
        (category) =>
            category.parentId == null &&
            (category.status == CategoryStatus.active ||
                category.id.value == selectedId),
      )
      .map((category) => (category.id.value, category.name));

  Iterable<(String, String)> _subcategories(
    String? parentId,
    String? selectedId,
  ) {
    if (parentId == null) return const <(String, String)>[];
    return widget.categories
        .where(
          (category) =>
              category.parentId?.value == parentId &&
              (category.status == CategoryStatus.active ||
                  category.id.value == selectedId),
        )
        .map((category) => (category.id.value, category.name));
  }

  Widget _dropdown({
    required Key key,
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
    required List<DropdownMenuEntry<String>> entries,
  }) => ButlerlySelectField<String>(
    key: key,
    label: label,
    value: value ?? '',
    entries: entries,
    onChanged: (selected) =>
        onChanged(selected == null || selected.isEmpty ? null : selected),
  );

  Widget _fieldGroup(List<Widget> fields) => Column(
    children: [
      for (var index = 0; index < fields.length; index++) ...[
        if (index > 0) const SizedBox(height: ButlerlySpacing.small),
        fields[index],
      ],
    ],
  );

  Widget _sectionHeading(String label) => Padding(
    padding: const EdgeInsets.only(
      top: ButlerlySpacing.standard,
      bottom: ButlerlySpacing.small,
    ),
    child: Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final empty = context.l10n.text('notSet');
    final merchants = widget.merchants.map(
      (value) => (value.id.value, value.name),
    );
    final sources = widget.paymentSources.map(
      (value) => (value.id.value, value.name),
    );
    final tags = widget.tags.map((value) => (value.id.value, value.name));
    final title = Text(
      context.l10n.text(widget.current == null ? 'addRule' : 'editRule'),
    );
    final content = Column(
      children: [
        _fieldGroup([
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
        ]),
        _sectionHeading(context.l10n.text('ruleConditions')),
        _fieldGroup([
          _dropdown(
            key: const ValueKey('rule-condition-merchant'),
            label: context.l10n.text('merchant'),
            value: _conditionMerchantId,
            onChanged: (v) => setState(() {
              _conditionMerchantId = v;
              _testResult = null;
              _testFailed = false;
            }),
            entries: _entries(empty, merchants),
          ),
          _dropdown(
            key: const ValueKey('rule-condition-category'),
            label: context.l10n.text('category'),
            value: _conditionCategoryId,
            onChanged: (v) => setState(() {
              _conditionCategoryId = v;
              _testResult = null;
              _testFailed = false;
            }),
            entries: _entries(empty, _rootCategories(_conditionCategoryId)),
          ),
          _dropdown(
            key: const ValueKey('rule-condition-payment-source'),
            label: context.l10n.text('paymentSource'),
            value: _conditionPaymentSourceId,
            onChanged: (v) => setState(() {
              _conditionPaymentSourceId = v;
              _testResult = null;
              _testFailed = false;
            }),
            entries: _entries(empty, sources),
          ),
          _dropdown(
            key: const ValueKey('rule-condition-tag'),
            label: context.l10n.text('tag'),
            value: _conditionTagId,
            onChanged: (v) => setState(() {
              _conditionTagId = v;
              _testResult = null;
              _testFailed = false;
            }),
            entries: _entries(empty, tags),
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
        ]),
        _sectionHeading(context.l10n.text('ruleActions')),
        _fieldGroup([
          _dropdown(
            key: const ValueKey('rule-action-merchant'),
            label: context.l10n.text('merchant'),
            value: _assignMerchantId,
            onChanged: (v) => setState(() {
              _assignMerchantId = v;
              _testResult = null;
              _testFailed = false;
            }),
            entries: _entries(empty, merchants),
          ),
          _dropdown(
            key: const ValueKey('rule-action-category'),
            label: context.l10n.text('category'),
            value: _assignCategoryId,
            onChanged: (v) => setState(() {
              _assignCategoryId = v;
              _assignSubcategoryId = null;
              _testResult = null;
              _testFailed = false;
            }),
            entries: _entries(empty, _rootCategories(_assignCategoryId)),
          ),
          _dropdown(
            key: const ValueKey('rule-action-subcategory'),
            label: context.l10n.text('subcategory'),
            value: _assignSubcategoryId,
            onChanged: (v) => setState(() {
              _assignSubcategoryId = v;
              _testResult = null;
              _testFailed = false;
            }),
            entries: _entries(
              empty,
              _subcategories(_assignCategoryId, _assignSubcategoryId),
            ),
          ),
          _dropdown(
            key: const ValueKey('rule-action-payment-source'),
            label: context.l10n.text('paymentSource'),
            value: _assignPaymentSourceId,
            onChanged: (v) => setState(() {
              _assignPaymentSourceId = v;
              _testResult = null;
              _testFailed = false;
            }),
            entries: _entries(empty, sources),
          ),
          _dropdown(
            key: const ValueKey('rule-action-tag'),
            label: context.l10n.text('tag'),
            value: _assignTagId,
            onChanged: (v) => setState(() {
              _assignTagId = v;
              _testResult = null;
              _testFailed = false;
            }),
            entries: _entries(empty, tags),
          ),
        ]),
        _sectionHeading(context.l10n.text('rulePreviewTitle')),
        _previewCard(context),
      ],
    );
    final actions = <Widget>[
      OutlinedButton(
        key: const ValueKey('rule-test-button'),
        onPressed: _testing ? null : _testRule,
        child: Text(context.l10n.text('rulePreviewTest')),
      ),
      ButlerlyCancelButton(
        onPressed: widget.onCancel ?? () => Navigator.pop(context),
        child: Text(context.l10n.text('cancel')),
      ),
      FilledButton(onPressed: _save, child: Text(context.l10n.text('save'))),
    ];
    if (widget.onSubmit == null) {
      return ButlerlySheet(title: title, content: content, actions: actions);
    }
    return ButlerlyCard(
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.headlineSmall!,
                child: title,
              ),
            ),
            IconButton(
              tooltip: context.l10n.text('close'),
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: ButlerlySpacing.standard),
        Expanded(child: SingleChildScrollView(child: content)),
        const SizedBox(height: ButlerlySpacing.standard),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: ButlerlySpacing.small,
          runSpacing: ButlerlySpacing.small,
          children: actions,
        ),
      ],
      ),
    );
  }
}
