import 'package:butlerly/app/locale/locale_provider.dart';
import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/transaction_master_data.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly/l10n/finance_formatters.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

final class FinancialProfilePage extends ConsumerStatefulWidget {
  const FinancialProfilePage({this.onboarding = false, super.key});

  final bool onboarding;

  @override
  ConsumerState<FinancialProfilePage> createState() =>
      _FinancialProfilePageState();
}

final class _FinancialProfilePageState
    extends ConsumerState<FinancialProfilePage> {
  final _targetController = TextEditingController();
  FinancialProfile? _profile;
  FinancialProfile? _draft;
  TransactionMasterDataSnapshot? _masterData;
  int _step = 0;
  bool _loading = true;
  bool _editing = false;
  bool _saving = false;
  bool _storageUnavailable = false;
  bool _categoryLoadError = false;
  String? _loadError;
  String? _targetError;
  bool _targetOptionSelected = false;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _editing = widget.onboarding;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
        _categoryLoadError = false;
      });
    }
    final finance = _finance;
    if (finance?.loadFinancialProfile == null ||
        finance?.saveFinancialProfile == null ||
        finance?.clearFinancialProfile == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _storageUnavailable = true;
        });
      }
      return;
    }
    try {
      final languageCode = Localizations.localeOf(context).languageCode;
      final profileResult = await finance!.loadFinancialProfile!();
      if (profileResult is ApplicationFailure<FinancialProfile?>) {
        throw StateError(profileResult.failure.operation);
      }
      final profile =
          (profileResult as ApplicationSuccess<FinancialProfile?>).value;
      final masterData = await TransactionMasterDataProvider(
        finance,
      ).load(languageCode: languageCode);
      if (!mounted) return;
      final draft = profile ?? FinancialProfile.empty(now: DateTime.now());
      setState(() {
        _profile = profile;
        _draft = draft;
        _masterData = masterData;
        _loading = false;
        _categoryLoadError = false;
        _targetOptionSelected = draft.hasMonthlySavingsTarget == true;
      });
      _targetController.text = draft.monthlySavingsTarget?.toString() ?? '';
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
        _categoryLoadError = error is TransactionMasterDataLoadException;
      });
    }
  }

  Future<bool> _save({required bool complete}) async {
    final draft = _draft;
    final finance = _finance;
    if (draft == null || finance?.saveFinancialProfile == null || _saving) {
      return false;
    }
    if (_targetError != null) return false;
    setState(() => _saving = true);
    final now = DateTime.now().toUtc();
    final saved = draft.copyWith(
      status: complete
          ? FinancialProfileStatus.completed
          : FinancialProfileStatus.inProgress,
      updatedAt: now,
      completedAt: complete ? now : null,
    );
    final result = await finance!.saveFinancialProfile!(saved);
    if (!mounted) return false;
    setState(() => _saving = false);
    if (result is! ApplicationSuccess<FinancialProfile>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('financialProfileSaveFailed')),
        ),
      );
      return false;
    }
    setState(() {
      _profile = result.value;
      _draft = result.value;
      if (complete) _editing = false;
    });
    if (complete) {
      if (widget.onboarding) {
        context.go('/');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('financialProfileSaved'))),
        );
      }
    }
    return true;
  }

  Future<bool> _persistProgress() async {
    if (!widget.onboarding) return true;
    return _save(complete: false);
  }

  Future<void> _skip() async {
    final draft = _draft;
    if (draft != null && draft.answeredQuestionCount > 0) {
      final saved = await _persistProgress();
      if (!saved) return;
    }
    if (mounted) context.go('/');
  }

  Future<void> _clearProfile() async {
    final confirmed = await showButlerlyConfirmationSheet(
      context: context,
      title: context.l10n.text('financialProfileClearTitle'),
      message: context.l10n.text('financialProfileClearBody'),
      cancelLabel: context.l10n.text('cancel'),
      confirmLabel: context.l10n.text('financialProfileClearConfirm'),
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    final result = await _finance!.clearFinancialProfile!();
    if (!mounted) return;
    if (result is! ApplicationSuccess<void>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.text('financialProfileSaveFailed')),
        ),
      );
      return;
    }
    setState(() {
      _profile = null;
      _draft = null;
      _editing = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.text('financialProfileCleared'))),
    );
  }

  void _startEditing() {
    final draft = _profile ?? FinancialProfile.empty(now: DateTime.now());
    setState(() {
      _draft = draft;
      _editing = true;
      _step = 0;
      _targetOptionSelected = draft.hasMonthlySavingsTarget == true;
      _targetError = null;
    });
    _targetController.text = draft.monthlySavingsTarget?.toString() ?? '';
  }

  void _updateDraft(FinancialProfile next) => setState(() => _draft = next);

  void _cancelEditing() {
    final router = GoRouter.maybeOf(context);
    if (router?.canPop() == true) {
      router!.pop();
    } else {
      setState(() {
        _draft = _profile;
        _editing = false;
      });
    }
  }

  void _setTargetOption(bool amount) {
    setState(() {
      _targetOptionSelected = amount;
      _targetError = null;
      if (!amount) {
        _targetController.clear();
        _draft = _draft?.copyWith(
          hasMonthlySavingsTarget: false,
          monthlySavingsTarget: null,
          monthlySavingsTargetCurrency: null,
        );
      } else {
        _draft = _draft?.copyWith(hasMonthlySavingsTarget: true);
      }
    });
  }

  String _normalizeLocalizedDecimal(String raw) {
    final symbols = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    ).symbols;
    return raw
        .trim()
        .replaceAll('\u00a0', '')
        .replaceAll(symbols.GROUP_SEP, '')
        .replaceAll(symbols.DECIMAL_SEP, '.');
  }

  void _setTarget(String raw) {
    final value = _normalizeLocalizedDecimal(raw);
    if (value.isEmpty) {
      setState(() {
        _targetError = null;
        _draft = _draft?.copyWith(
          hasMonthlySavingsTarget: true,
          monthlySavingsTarget: null,
          monthlySavingsTargetCurrency: null,
        );
      });
      return;
    }
    try {
      final parsed = DecimalValue.parse(value);
      final preference = ref.read(userPreferenceProvider).value;
      if (parsed.isNegative) {
        throw const _TargetValidationError('financialProfileTargetInvalid');
      }
      if (parsed.coefficient.abs().toString().length >
              FinancialProfile.maxSavingsTargetDigits ||
          parsed.scale > FinancialProfile.maxSavingsTargetScale) {
        throw const _TargetValidationError('financialProfileTargetTooLarge');
      }
      setState(() {
        _targetError = null;
        _draft = _draft?.copyWith(
          hasMonthlySavingsTarget: true,
          monthlySavingsTarget: parsed,
          monthlySavingsTargetCurrency:
              preference?.baseCurrency ?? CurrencyCode('USD'),
        );
      });
    } on _TargetValidationError catch (error) {
      setState(() => _targetError = error.key);
    } on DomainValidationException {
      setState(() => _targetError = 'financialProfileTargetInvalid');
    }
  }

  String _sectionName(BuildContext context, int step) => switch (step) {
    0 => context.l10n.text('financialProfileHousehold'),
    1 => context.l10n.text('financialProfileSpending'),
    2 => context.l10n.text('financialProfileGoals'),
    _ => context.l10n.text('financialProfilePreferences'),
  };

  String _categoryLabel(BuildContext context, String id) {
    final master = _masterData?.presentation;
    return master?.categoryName(id) ?? context.l10n.text('unavailableCategory');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_storageUnavailable) {
      return _page(
        context,
        children: [
          ButlerlyEmptyState(
            icon: Icons.storage_outlined,
            title: context.l10n.text('financialProfileStorageUnavailable'),
            message: context.l10n.text('dataPreserved'),
          ),
        ],
      );
    }
    if (_loadError != null) {
      return _page(
        context,
        children: [
          ButlerlyErrorState(
            title: context.l10n.text(
              _categoryLoadError
                  ? 'financialProfileCategoriesUnavailable'
                  : 'financialProfileStorageUnavailable',
            ),
            message: context.l10n.text(
              _categoryLoadError
                  ? 'financialProfileCategoriesUnavailableBody'
                  : 'dataPreserved',
            ),
            preserved: context.l10n.text('dataPreserved'),
            actionLabel: context.l10n.text('tryAgain'),
            onAction: _load,
          ),
        ],
      );
    }
    return _editing ? _buildSurvey(context) : _buildSummary(context);
  }

  Widget _page(
    BuildContext context, {
    required List<Widget> children,
    String? subtitle,
  }) => ButlerlyPage(
    title: context.l10n.text('financialProfile'),
    subtitle: subtitle ?? context.l10n.text('financialProfileBody'),
    leading: GoRouter.maybeOf(context)?.canPop() == true
        ? IconButton(
            tooltip: context.l10n.text('close'),
            onPressed: () => context.pop(),
            icon: const Icon(Icons.arrow_back),
          )
        : null,
    children: children,
  );

  Widget _buildSummary(BuildContext context) {
    final profile = _profile;
    final status = profile?.status ?? FinancialProfileStatus.notStarted;
    final answered = profile?.answeredQuestionCount ?? 0;
    return _page(
      context,
      children: [
        ButlerlyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ButlerlyCardHeader(
                title: context.l10n.text('financialProfileSummary'),
                subtitle: context.l10n.text(switch (status) {
                  FinancialProfileStatus.notStarted =>
                    'financialProfileNoProfile',
                  FinancialProfileStatus.inProgress =>
                    'financialProfileInProgressBody',
                  FinancialProfileStatus.completed => 'financialProfileBody',
                }),
              ),
              const SizedBox(height: ButlerlySpacing.standard),
              _summaryRow(
                context.l10n.text('financialProfileStatus'),
                context.l10n.text(_statusKey(status)),
              ),
              _summaryRow(
                context.l10n.text('financialProfileAnsweredLabel'),
                context.l10n.text('financialProfileAnswered', {
                  'count': '$answered',
                }),
              ),
              if (profile != null)
                _summaryRow(
                  context.l10n.text('financialProfileLastUpdated'),
                  MaterialLocalizations.of(
                    context,
                  ).formatMediumDate(profile.updatedAt.toLocal()),
                ),
            ],
          ),
        ),
        const SizedBox(height: ButlerlySpacing.standard),
        if (profile != null && profile.answeredQuestionCount > 0)
          ButlerlyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _summaryAnswers(context, profile),
            ),
          ),
        const SizedBox(height: ButlerlySpacing.standard),
        FilledButton.icon(
          key: const ValueKey('financial-profile-edit'),
          onPressed: _startEditing,
          icon: Icon(
            profile == null ? Icons.play_arrow_rounded : Icons.edit_outlined,
          ),
          label: Text(
            context.l10n.text(
              profile == null ? 'setUpMyProfile' : 'financialProfileEdit',
            ),
          ),
        ),
        if (profile != null) ...[
          const SizedBox(height: ButlerlySpacing.small),
          OutlinedButton(
            onPressed: _startEditing,
            child: Text(context.l10n.text('financialProfileRetake')),
          ),
          const SizedBox(height: ButlerlySpacing.small),
          TextButton(
            onPressed: _clearProfile,
            child: Text(context.l10n.text('financialProfileClear')),
          ),
        ],
      ],
    );
  }

  Widget _buildSurvey(BuildContext context) {
    final draft = _draft;
    if (draft == null) return _page(context, children: const []);
    final progress = (_step + 1) / 4;
    return _page(
      context,
      subtitle: context.l10n.text('financialProfileBody'),
      children: [
        ButlerlyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _sectionName(context, _step),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  const SizedBox(width: ButlerlySpacing.small),
                  Flexible(
                    child: Text(
                      context.l10n.text('financialProfileStep', {
                        'step': '${_step + 1}',
                      }),
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ButlerlySpacing.small),
              LinearProgressIndicator(value: progress),
            ],
          ),
        ),
        const SizedBox(height: ButlerlySpacing.standard),
        _buildStepQuestions(context, draft),
        const SizedBox(height: ButlerlySpacing.standard),
        Row(
          children: [
            if (_step > 0)
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('financial-profile-back'),
                  onPressed: _saving ? null : () => setState(() => _step -= 1),
                  child: Text(context.l10n.text('financialProfileBack')),
                ),
              ),
            if (_step > 0) const SizedBox(width: ButlerlySpacing.small),
            Expanded(
              child: FilledButton(
                key: ValueKey(
                  _step == 3
                      ? 'financial-profile-save'
                      : 'financial-profile-continue',
                ),
                onPressed: _saving ? null : _continue,
                child: Text(
                  context.l10n.text(
                    _step == 3
                        ? 'financialProfileFinish'
                        : 'financialProfileContinue',
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: ButlerlySpacing.small),
        Align(
          alignment: Alignment.center,
          child: TextButton(
            key: const ValueKey('financial-profile-cancel'),
            onPressed: _saving
                ? null
                : widget.onboarding
                ? _skip
                : _cancelEditing,
            child: Text(
              context.l10n.text(widget.onboarding ? 'skip' : 'cancel'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepQuestions(BuildContext context, FinancialProfile draft) =>
      switch (_step) {
        0 => _householdQuestions(context, draft),
        1 => _spendingQuestions(context, draft),
        2 => _goalQuestions(context, draft),
        _ => _preferenceQuestions(context, draft),
      };

  Widget _householdQuestions(
    BuildContext context,
    FinancialProfile draft,
  ) => Column(
    children: [
      _radioQuestion<HouseholdSize>(
        context,
        title: context.l10n.text('financialProfileQ1'),
        value: draft.householdSize,
        options: {
          HouseholdSize.one: 'financialProfileHouseholdOne',
          HouseholdSize.two: 'financialProfileHouseholdTwo',
          HouseholdSize.three: 'financialProfileHouseholdThree',
          HouseholdSize.four: 'financialProfileHouseholdFour',
          HouseholdSize.fiveOrMore: 'financialProfileHouseholdFiveOrMore',
        },
        onChanged: (value) =>
            _updateDraft(draft.copyWith(householdSize: value)),
      ),
      _radioQuestion<DependentsCount>(
        context,
        title: context.l10n.text('financialProfileQ2'),
        value: draft.dependentsCount,
        options: {
          DependentsCount.none: 'financialProfileDependentsNone',
          DependentsCount.one: 'financialProfileDependentsOne',
          DependentsCount.two: 'financialProfileDependentsTwo',
          DependentsCount.threeOrMore: 'financialProfileDependentsThreeOrMore',
        },
        onChanged: (value) =>
            _updateDraft(draft.copyWith(dependentsCount: value)),
      ),
      _radioQuestion<HousingSituation>(
        context,
        title: context.l10n.text('financialProfileQ3'),
        value: draft.housingSituation,
        options: {
          HousingSituation.renting: 'financialProfileHousingRenting',
          HousingSituation.mortgage: 'financialProfileHousingMortgage',
          HousingSituation.ownOutright: 'financialProfileHousingOwnOutright',
          HousingSituation.other: 'financialProfileHousingOther',
          HousingSituation.preferNotToSay:
              'financialProfileHousingPreferNotToSay',
        },
        onChanged: (value) =>
            _updateDraft(draft.copyWith(housingSituation: value)),
      ),
    ],
  );

  Widget _spendingQuestions(BuildContext context, FinancialProfile draft) =>
      Column(
        children: [
          _categoryQuestion(
            context,
            title: context.l10n.text('financialProfileQ4'),
            hint: context.l10n.text('financialProfileQ4Hint'),
            selected: draft.primarySpendingCategoryIds,
            max: 3,
            onChanged: (selected) => _updateDraft(
              draft.copyWith(primarySpendingCategoryIds: selected),
            ),
          ),
          const SizedBox(height: ButlerlySpacing.standard),
          _radioQuestion<ExpensePredictability>(
            context,
            title: context.l10n.text('financialProfileQ5'),
            value: draft.expensePredictability,
            options: {
              ExpensePredictability.mostlyFixed:
                  'financialProfileExpenseMostlyFixed',
              ExpensePredictability.mixedFixedVariable:
                  'financialProfileExpenseMixed',
              ExpensePredictability.highlyVariable:
                  'financialProfileExpenseVariable',
            },
            onChanged: (value) =>
                _updateDraft(draft.copyWith(expensePredictability: value)),
          ),
          _categoryQuestion(
            context,
            title: context.l10n.text('financialProfileQ6'),
            selected: draft.categoriesToImprove,
            onChanged: (selected) =>
                _updateDraft(draft.copyWith(categoriesToImprove: selected)),
          ),
        ],
      );

  Widget _goalQuestions(BuildContext context, FinancialProfile draft) => Column(
    children: [
      _radioQuestion<PrimaryFinancialGoal>(
        context,
        title: context.l10n.text('financialProfileQ7'),
        value: draft.primaryFinancialGoal,
        options: {
          PrimaryFinancialGoal.understandSpending:
              'financialProfileGoalUnderstandSpending',
          PrimaryFinancialGoal.saveMore: 'financialProfileGoalSaveMore',
          PrimaryFinancialGoal.reduceExpenses:
              'financialProfileGoalReduceExpenses',
          PrimaryFinancialGoal.improveCashFlow:
              'financialProfileGoalImproveCashFlow',
          PrimaryFinancialGoal.reduceDebt: 'financialProfileGoalReduceDebt',
        },
        onChanged: (value) =>
            _updateDraft(draft.copyWith(primaryFinancialGoal: value)),
      ),
      _savingsTargetQuestion(context, draft),
      _radioQuestion<GoalTimeframe>(
        context,
        title: context.l10n.text('financialProfileQ9'),
        value: draft.goalTimeframe,
        options: {
          GoalTimeframe.shortTerm: 'financialProfileTimeframeShort',
          GoalTimeframe.mediumTerm: 'financialProfileTimeframeMedium',
          GoalTimeframe.longTerm: 'financialProfileTimeframeLong',
        },
        descriptions: {
          GoalTimeframe.shortTerm: 'financialProfileTimeframeShortBody',
          GoalTimeframe.mediumTerm: 'financialProfileTimeframeMediumBody',
          GoalTimeframe.longTerm: 'financialProfileTimeframeLongBody',
        },
        onChanged: (value) =>
            _updateDraft(draft.copyWith(goalTimeframe: value)),
      ),
    ],
  );

  Widget _preferenceQuestions(BuildContext context, FinancialProfile draft) =>
      Column(
        children: [
          _radioQuestion<BudgetingPreference>(
            context,
            title: context.l10n.text('financialProfileQ10'),
            value: draft.budgetingPreference,
            options: {
              BudgetingPreference.fixedMonthly: 'financialProfileBudgetFixed',
              BudgetingPreference.flexibleMonthly:
                  'financialProfileBudgetFlexible',
              BudgetingPreference.trackingOnly:
                  'financialProfileBudgetTrackingOnly',
              BudgetingPreference.notSure: 'financialProfileBudgetNotSure',
            },
            onChanged: (value) =>
                _updateDraft(draft.copyWith(budgetingPreference: value)),
          ),
          _multiChoiceQuestion<FinancialInsightType>(
            context,
            title: context.l10n.text('financialProfileQ11'),
            selected: draft.preferredInsightTypes,
            options: {
              FinancialInsightType.spendingTrends:
                  'financialProfileInsightSpendingTrends',
              FinancialInsightType.unusualExpenses:
                  'financialProfileInsightUnusualExpenses',
              FinancialInsightType.savingsOpportunities:
                  'financialProfileInsightSavingsOpportunities',
              FinancialInsightType.budgetTracking:
                  'financialProfileInsightBudgetTracking',
            },
            onChanged: (selected) =>
                _updateDraft(draft.copyWith(preferredInsightTypes: selected)),
          ),
        ],
      );

  Widget _savingsTargetQuestion(BuildContext context, FinancialProfile draft) =>
      ButlerlyCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.text('financialProfileQ8'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            RadioGroup<bool>(
              groupValue: draft.hasMonthlySavingsTarget,
              onChanged: (selected) {
                if (selected != null) _setTargetOption(selected);
              },
              child: Column(
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.l10n.text('financialProfileTargetNoSpecific'),
                    ),
                    value: false,
                  ),
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      context.l10n.text('financialProfileTargetAmount', {
                        'currency':
                            ref
                                .read(userPreferenceProvider)
                                .value
                                ?.baseCurrency
                                .value ??
                            draft.monthlySavingsTargetCurrency?.value ??
                            'USD',
                      }),
                    ),
                    value: true,
                  ),
                ],
              ),
            ),
            if (_targetOptionSelected)
              TextField(
                key: const ValueKey('financial-profile-savings-target'),
                controller: _targetController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: context.l10n.text('financialProfileTargetHint'),
                  errorText: _targetError == null
                      ? null
                      : context.l10n.text(_targetError!),
                ),
                onChanged: _setTarget,
              ),
          ],
        ),
      );

  Widget _radioQuestion<T extends Enum>(
    BuildContext context, {
    required String title,
    required T? value,
    required Map<T, String> options,
    required ValueChanged<T> onChanged,
    Map<T, String> descriptions = const {},
  }) => ButlerlyCard(
    child: RadioGroup<T>(
      groupValue: value,
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          for (final entry in options.entries)
            RadioListTile<T>(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.text(entry.value)),
              subtitle: descriptions[entry.key] == null
                  ? null
                  : Text(context.l10n.text(descriptions[entry.key]!)),
              value: entry.key,
            ),
        ],
      ),
    ),
  );

  Widget _multiChoiceQuestion<T>(
    BuildContext context, {
    required String title,
    required List<T> selected,
    required Map<T, String> options,
    required ValueChanged<List<T>> onChanged,
  }) => ButlerlyCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        for (final entry in options.entries)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.text(entry.value)),
            value: selected.contains(entry.key),
            onChanged: (checked) {
              final next = [...selected];
              if (checked == true && !next.contains(entry.key)) {
                next.add(entry.key);
              } else if (checked != true) {
                next.remove(entry.key);
              }
              onChanged(next);
            },
          ),
      ],
    ),
  );

  Widget _categoryQuestion(
    BuildContext context, {
    required String title,
    String? hint,
    required List<String> selected,
    int? max,
    required ValueChanged<List<String>> onChanged,
  }) {
    final categories = _masterData?.categories
        .where(
          (category) =>
              category.status == CategoryStatus.active ||
              selected.contains(category.id.value),
        )
        .toList(growable: false);
    return ButlerlyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (hint != null) ...[
            const SizedBox(height: ButlerlySpacing.micro),
            Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: ButlerlySpacing.small),
          if (categories == null || categories.isEmpty)
            Text(context.l10n.text('financialProfileNoCategories'))
          else
            Wrap(
              spacing: ButlerlySpacing.compact,
              runSpacing: ButlerlySpacing.compact,
              children: [
                for (final category in categories)
                  FilterChip(
                    label: Text(_categoryLabel(context, category.id.value)),
                    selected: selected.contains(category.id.value),
                    onSelected: (checked) {
                      final next = [...selected];
                      if (checked) {
                        if (max != null && next.length >= max) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                context.l10n.text(
                                  'financialProfileCategoryLimit',
                                ),
                              ),
                            ),
                          );
                          return;
                        }
                        next.add(category.id.value);
                      } else {
                        next.remove(category.id.value);
                      }
                      onChanged(next);
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _continue() async {
    if (_step < 3) {
      final saved = await _persistProgress();
      if (!saved) return;
      if (!mounted) return;
      setState(() => _step += 1);
      return;
    }
    await _save(complete: true);
  }

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: ButlerlySpacing.small),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: ButlerlySpacing.standard),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );

  List<Widget> _summaryAnswers(
    BuildContext context,
    FinancialProfile profile,
  ) => [
    Text(
      context.l10n.text('financialProfileSummary'),
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const SizedBox(height: ButlerlySpacing.small),
    if (profile.householdSize != null)
      _summaryRow(
        context.l10n.text('financialProfileQ1'),
        context.l10n.text(_householdKey(profile.householdSize!)),
      ),
    if (profile.dependentsCount != null)
      _summaryRow(
        context.l10n.text('financialProfileQ2'),
        context.l10n.text(_dependentsKey(profile.dependentsCount!)),
      ),
    if (profile.housingSituation != null)
      _summaryRow(
        context.l10n.text('financialProfileQ3'),
        context.l10n.text(_housingKey(profile.housingSituation!)),
      ),
    if (profile.primarySpendingCategoryIds.isNotEmpty)
      _summaryRow(
        context.l10n.text('financialProfileQ4'),
        profile.primarySpendingCategoryIds
            .map((id) => _categoryLabel(context, id))
            .join(', '),
      ),
    if (profile.expensePredictability != null)
      _summaryRow(
        context.l10n.text('financialProfileQ5'),
        context.l10n.text(_expenseKey(profile.expensePredictability!)),
      ),
    if (profile.categoriesToImprove.isNotEmpty)
      _summaryRow(
        context.l10n.text('financialProfileQ6'),
        profile.categoriesToImprove
            .map((id) => _categoryLabel(context, id))
            .join(', '),
      ),
    if (profile.primaryFinancialGoal != null)
      _summaryRow(
        context.l10n.text('financialProfileQ7'),
        context.l10n.text(_goalKey(profile.primaryFinancialGoal!)),
      ),
    if (profile.hasMonthlySavingsTarget != null)
      _summaryRow(
        context.l10n.text('financialProfileQ8'),
        profile.monthlySavingsTarget == null
            ? context.l10n.text(
                profile.hasMonthlySavingsTarget == true
                    ? 'financialProfileTargetNoAmount'
                    : 'financialProfileTargetNoSpecific',
              )
            : localizedExactMoney(
                context,
                profile.monthlySavingsTarget!.toString(),
                profile.monthlySavingsTargetCurrency?.value ?? 'USD',
              ),
      ),
    if (profile.goalTimeframe != null)
      _summaryRow(
        context.l10n.text('financialProfileQ9'),
        context.l10n.text(_timeframeKey(profile.goalTimeframe!)),
      ),
    if (profile.budgetingPreference != null)
      _summaryRow(
        context.l10n.text('financialProfileQ10'),
        context.l10n.text(_budgetKey(profile.budgetingPreference!)),
      ),
    if (profile.preferredInsightTypes.isNotEmpty)
      _summaryRow(
        context.l10n.text('financialProfileQ11'),
        profile.preferredInsightTypes
            .map(_insightKey)
            .map(context.l10n.text)
            .join(', '),
      ),
  ];

  String _statusKey(FinancialProfileStatus value) => switch (value) {
    FinancialProfileStatus.notStarted => 'financialProfileStatusNotStarted',
    FinancialProfileStatus.inProgress => 'financialProfileStatusInProgress',
    FinancialProfileStatus.completed => 'financialProfileStatusCompleted',
  };

  String _householdKey(HouseholdSize value) => switch (value) {
    HouseholdSize.one => 'financialProfileHouseholdOne',
    HouseholdSize.two => 'financialProfileHouseholdTwo',
    HouseholdSize.three => 'financialProfileHouseholdThree',
    HouseholdSize.four => 'financialProfileHouseholdFour',
    HouseholdSize.fiveOrMore => 'financialProfileHouseholdFiveOrMore',
  };

  String _dependentsKey(DependentsCount value) => switch (value) {
    DependentsCount.none => 'financialProfileDependentsNone',
    DependentsCount.one => 'financialProfileDependentsOne',
    DependentsCount.two => 'financialProfileDependentsTwo',
    DependentsCount.threeOrMore => 'financialProfileDependentsThreeOrMore',
  };

  String _housingKey(HousingSituation value) => switch (value) {
    HousingSituation.renting => 'financialProfileHousingRenting',
    HousingSituation.mortgage => 'financialProfileHousingMortgage',
    HousingSituation.ownOutright => 'financialProfileHousingOwnOutright',
    HousingSituation.other => 'financialProfileHousingOther',
    HousingSituation.preferNotToSay => 'financialProfileHousingPreferNotToSay',
  };

  String _expenseKey(ExpensePredictability value) => switch (value) {
    ExpensePredictability.mostlyFixed => 'financialProfileExpenseMostlyFixed',
    ExpensePredictability.mixedFixedVariable => 'financialProfileExpenseMixed',
    ExpensePredictability.highlyVariable => 'financialProfileExpenseVariable',
  };

  String _goalKey(PrimaryFinancialGoal value) => switch (value) {
    PrimaryFinancialGoal.understandSpending =>
      'financialProfileGoalUnderstandSpending',
    PrimaryFinancialGoal.saveMore => 'financialProfileGoalSaveMore',
    PrimaryFinancialGoal.reduceExpenses => 'financialProfileGoalReduceExpenses',
    PrimaryFinancialGoal.improveCashFlow =>
      'financialProfileGoalImproveCashFlow',
    PrimaryFinancialGoal.reduceDebt => 'financialProfileGoalReduceDebt',
  };

  String _timeframeKey(GoalTimeframe value) => switch (value) {
    GoalTimeframe.shortTerm => 'financialProfileTimeframeShort',
    GoalTimeframe.mediumTerm => 'financialProfileTimeframeMedium',
    GoalTimeframe.longTerm => 'financialProfileTimeframeLong',
  };

  String _budgetKey(BudgetingPreference value) => switch (value) {
    BudgetingPreference.fixedMonthly => 'financialProfileBudgetFixed',
    BudgetingPreference.flexibleMonthly => 'financialProfileBudgetFlexible',
    BudgetingPreference.trackingOnly => 'financialProfileBudgetTrackingOnly',
    BudgetingPreference.notSure => 'financialProfileBudgetNotSure',
  };

  String _insightKey(FinancialInsightType value) => switch (value) {
    FinancialInsightType.spendingTrends =>
      'financialProfileInsightSpendingTrends',
    FinancialInsightType.unusualExpenses =>
      'financialProfileInsightUnusualExpenses',
    FinancialInsightType.savingsOpportunities =>
      'financialProfileInsightSavingsOpportunities',
    FinancialInsightType.budgetTracking =>
      'financialProfileInsightBudgetTracking',
  };
}

final class _TargetValidationError implements Exception {
  const _TargetValidationError(this.key);

  final String key;
}
