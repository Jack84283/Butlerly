import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_compact_section_selector.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/components/butlerly_modal_sheet.dart';
import 'package:butlerly/design_system/theme/butlerly_semantic_colors.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class MasterDataPage extends StatefulWidget {
  const MasterDataPage({super.key});

  @override
  State<MasterDataPage> createState() => _MasterDataPageState();
}

class _MasterDataPageState extends State<MasterDataPage> {
  late Future<_MasterData> _data;
  String? _languageCode;
  int _sectionIndex = 0;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _data = Future.value(const _MasterData([], [], [], {}, {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = Localizations.localeOf(context).languageCode;
    if (_languageCode == languageCode) return;
    _languageCode = languageCode;
    _data = _load(languageCode);
  }

  Future<_MasterData> _load(String languageCode) async {
    final finance = _finance;
    if (finance == null) return const _MasterData([], [], [], {}, {});
    final locale = languageCode == 'zh' ? 'zh-Hans' : languageCode;
    final results = await Future.wait([
      finance.listCategories(),
      finance.listTags(),
      finance.listMerchants(),
      finance.loadMasterTranslations(masterType: 'category', locale: locale),
      finance.loadMasterTranslations(masterType: 'category', locale: 'en'),
      finance.loadMasterTranslations(masterType: 'tag', locale: locale),
      finance.loadMasterTranslations(masterType: 'tag', locale: 'en'),
    ]);
    final categories = results[0];
    final tags = results[1];
    final merchants = results[2];
    if (categories is! ApplicationSuccess<List<Category>> ||
        tags is! ApplicationSuccess<List<Tag>> ||
        merchants is! ApplicationSuccess<List<Merchant>>) {
      throw StateError('Master data could not be loaded.');
    }
    Map<String, String> labelsAt(int index) => switch (results[index]) {
      ApplicationSuccess<Map<String, String>>(:final value) => value,
      _ => const <String, String>{},
    };
    return _MasterData(
      categories.value,
      tags.value,
      merchants.value,
      {...labelsAt(4), ...labelsAt(3)},
      {...labelsAt(6), ...labelsAt(5)},
    );
  }

  void _refresh() {
    if (!mounted) return;
    final data = _load(_languageCode ?? 'en');
    setState(() {
      _data = data;
    });
  }

  bool _accepted<T>(ApplicationResult<T> result) {
    if (result is ApplicationSuccess<T>) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.text('dataPreserved'))));
    return false;
  }

  Future<void> _editExisting(Object value) async {
    final finance = _finance;
    if (finance == null) return;
    if (value is Merchant) {
      await _editMerchant(value);
      return;
    }
    final currentName = switch (value) {
      Category(:final name) => name,
      Tag(:final name) => name,
      _ => throw ArgumentError.value(value, 'value'),
    };
    final labelKey = switch (value) {
      Category() => 'categoryName',
      Tag() => 'tagName',
      _ => throw ArgumentError.value(value, 'value'),
    };
    final name = await _editSheet(
      context,
      title: context.l10n.text('edit'),
      labelKey: labelKey,
      initial: currentName,
    );
    if (name == null || !mounted) return;

    if (value is Category) {
      final parent = value.parentId == null ? null : await _chooseParent();
      if (!mounted || (value.parentId != null && parent == null)) return;
      final saved = await finance.saveCategory(
        Category(
          id: value.id,
          name: name,
          origin: value.origin,
          parentId: parent,
          status: value.status,
        ),
      );
      if (!_accepted(saved)) return;
    } else if (value is Tag) {
      final saved = await finance.saveTag(
        Tag(id: value.id, name: name, status: value.status),
      );
      if (!_accepted(saved)) return;
    }
    if (mounted) _refresh();
  }

  Future<void> _editMerchant(Merchant merchant) async {
    final finance = _finance;
    if (finance == null) return;
    final draft = await showButlerlyBottomSheet<_MerchantDraft>(
      context: context,
      builder: (_) => _MerchantEditorSheet(merchant: merchant),
    );
    if (!mounted || draft == null) return;
    final update = finance.updateMerchantMatchingConfiguration;
    if (update == null) return;
    final result = await update(
      merchant: Merchant(
        id: merchant.id,
        name: merchant.isBuiltIn ? merchant.name : draft.name,
        status: merchant.status,
        rawName: merchant.rawName,
        defaultCategoryId: merchant.defaultCategoryId,
        defaultSubcategoryId: merchant.defaultSubcategoryId,
        isBuiltIn: merchant.isBuiltIn,
        aliases: merchant.aliases,
        normalizationPatterns: merchant.normalizationPatterns,
      ),
      aliases: draft.aliases,
      patterns: draft.patterns,
    );
    if (!_accepted(result)) return;
    if (mounted) _refresh();
  }

  Future<void> _add() async {
    final index = _sectionIndex;
    final titleKey = switch (index) {
      0 => 'addCategory',
      1 => 'addSubcategory',
      2 => 'addTagManagement',
      3 => 'addMerchant',
      _ => 'add',
    };
    final labelKey = switch (index) {
      0 => 'categoryName',
      1 => 'subcategoryName',
      2 => 'tagName',
      3 => 'merchantName',
      _ => 'name',
    };
    final result = await _editSheet(
      context,
      title: context.l10n.text(titleKey),
      labelKey: labelKey,
    );
    if (result == null || !mounted) return;
    final finance = _finance;
    if (finance == null) return;

    if (index == 2) {
      final saved = await finance.saveTag(
        Tag(
          id: TagId('user.tag.${DateTime.now().microsecondsSinceEpoch}'),
          name: result,
        ),
      );
      if (!_accepted(saved)) return;
    } else if (index == 3) {
      final saved = await finance.saveMerchant(
        Merchant(
          id: MerchantId(
            'user.merchant.${DateTime.now().microsecondsSinceEpoch}',
          ),
          name: result,
          rawName: result,
        ),
      );
      if (!_accepted(saved)) return;
    } else {
      final parent = index == 1 ? await _chooseParent() : null;
      if (!mounted || (index == 1 && parent == null)) return;
      final saved = await finance.saveCategory(
        Category(
          id: CategoryId(
            'user.category.${DateTime.now().microsecondsSinceEpoch}',
          ),
          name: result,
          origin: CategoryOrigin.user,
          parentId: parent,
        ),
      );
      if (!_accepted(saved)) return;
    }
    if (mounted) _refresh();
  }

  Future<CategoryId?> _chooseParent() async {
    final data = await _data;
    if (!mounted) return null;
    final roots = data.categories
        .where(
          (value) =>
              value.parentId == null && value.status == CategoryStatus.active,
        )
        .toList();
    return showButlerlyBottomSheet<CategoryId>(
      context: context,
      builder: (context) => ButlerlySheet(
        key: const ValueKey('master-data-parent-sheet'),
        title: Text(context.l10n.text('parentCategory')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final category in roots)
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => Navigator.pop(context, category.id),
                title: Text(data.categoryLabel(category)),
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _editSheet(
    BuildContext context, {
    required String title,
    required String labelKey,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showButlerlyBottomSheet<String>(
      context: context,
      builder: (context) => ButlerlySheet(
        key: const ValueKey('master-data-edit-sheet'),
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.text(labelKey)),
          onSubmitted: (_) => Navigator.pop(context, controller.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.text('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(context.l10n.text('save')),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result?.trim().isEmpty == true ? null : result?.trim();
  }

  @override
  Widget build(BuildContext context) => ButlerlyPage(
    title: context.l10n.text('masterData'),
    pinnedSpacing: ButlerlyPinnedPageSpacing.tightHeader,
    actions: [
      Padding(
        padding: const EdgeInsetsDirectional.only(
          end: ButlerlySpacing.headerActionTrailing,
        ),
        child: IconButton.filled(
          key: const ValueKey('master-data-add'),
          tooltip: context.l10n.text('add'),
          onPressed: _add,
          icon: const Icon(Icons.add),
          style: IconButton.styleFrom(
            backgroundColor: context.colors.interactive,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            minimumSize: const Size.square(ButlerlySize.minimumTarget),
            maximumSize: const Size.square(ButlerlySize.minimumTarget),
          ),
        ),
      ),
    ],
    pinnedHeader: ButlerlyCompactSectionSelector(
      labels: [
        context.l10n.text('categories'),
        context.l10n.text('subcategories'),
        context.l10n.text('tags'),
        context.l10n.text('merchants'),
      ],
      selectedIndex: _sectionIndex,
      onSelected: (index) => setState(() => _sectionIndex = index),
    ),
    children: [
      FutureBuilder<_MasterData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const ButlerlyLoadingState();
          }
          if (snapshot.hasError) {
            return ButlerlyErrorState(
              title: context.l10n.text('reviewLoadError'),
              message: context.l10n.text('tryAgain'),
              preserved: context.l10n.text('dataPreserved'),
              actionLabel: context.l10n.text('tryAgain'),
              onAction: _refresh,
            );
          }
          final data = snapshot.requireData;
          return _MasterDataList(
            index: _sectionIndex,
            data: data,
            onChanged: _refresh,
            finance: _finance,
            onEdit: _editExisting,
          );
        },
      ),
      const SizedBox(height: ButlerlySpacing.structural),
    ],
  );
}

final class _MasterData {
  const _MasterData(
    this.categories,
    this.tags,
    this.merchants,
    this.categoryLabels,
    this.tagLabels,
  );

  final List<Category> categories;
  final List<Tag> tags;
  final List<Merchant> merchants;
  final Map<String, String> categoryLabels;
  final Map<String, String> tagLabels;

  String categoryLabel(Category value) =>
      categoryLabels[value.id.value] ?? value.name;

  String tagLabel(Tag value) => tagLabels[value.id.value] ?? value.name;
}

class _MasterDataList extends StatelessWidget {
  const _MasterDataList({
    required this.index,
    required this.data,
    required this.onChanged,
    required this.finance,
    required this.onEdit,
  });

  final int index;
  final _MasterData data;
  final VoidCallback onChanged;
  final FinanceServices? finance;
  final Future<void> Function(Object value) onEdit;

  void _showFailure(BuildContext context) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.text('dataPreserved'))));
  }

  @override
  Widget build(BuildContext context) {
    if (index == 2) {
      return _ListCard(
        children: [
          for (final tag in data.tags)
            _Row(
              title: data.tagLabel(tag),
              origin: tag.id.value.startsWith('tag.')
                  ? context.l10n.text('builtin')
                  : context.l10n.text('user'),
              active: tag.status == TagStatus.active,
              onEdit: tag.id.value.startsWith('tag.')
                  ? null
                  : () => onEdit(tag),
              onToggle: finance == null
                  ? null
                  : () async {
                      final saved = await finance!.saveTag(
                        tag.status == TagStatus.active
                            ? tag.archive()
                            : Tag(id: tag.id, name: tag.name),
                      );
                      if (saved is ApplicationSuccess<Tag>) {
                        onChanged();
                      } else if (context.mounted) {
                        _showFailure(context);
                      }
                    },
            ),
        ],
      );
    }

    if (index == 3) {
      return _ListCard(
        children: [
          for (final merchant in data.merchants)
            _Row(
              title: merchant.name,
              origin: merchant.isBuiltIn
                  ? context.l10n.text('builtin')
                  : context.l10n.text('user'),
              active: merchant.status == MerchantStatus.active,
              onEdit: () => onEdit(merchant),
              onToggle: finance == null
                  ? null
                  : () async {
                      final saved = await finance!.saveMerchant(
                        merchant.status == MerchantStatus.active
                            ? merchant.archive()
                            : Merchant(
                                id: merchant.id,
                                name: merchant.name,
                                rawName: merchant.rawName,
                                defaultCategoryId: merchant.defaultCategoryId,
                                defaultSubcategoryId:
                                    merchant.defaultSubcategoryId,
                                isBuiltIn: merchant.isBuiltIn,
                              ),
                      );
                      if (saved is ApplicationSuccess<Merchant>) {
                        onChanged();
                      } else if (context.mounted) {
                        _showFailure(context);
                      }
                    },
            ),
        ],
      );
    }

    final values = data.categories.where(
      (category) =>
          index == 0 ? category.parentId == null : category.parentId != null,
    );
    return _ListCard(
      children: [
        for (final category in values)
          _Row(
            title: data.categoryLabel(category),
            subtitle: index == 1
                ? data.categories
                      .where((parent) => parent.id == category.parentId)
                      .map(data.categoryLabel)
                      .firstOrNull
                : '${data.categories.where((child) => child.parentId == category.id).length} ${context.l10n.text('subcategories').toLowerCase()}',
            origin: category.origin == CategoryOrigin.system
                ? context.l10n.text('builtin')
                : context.l10n.text('user'),
            active: category.status == CategoryStatus.active,
            onEdit: category.origin == CategoryOrigin.user
                ? () => onEdit(category)
                : null,
            onToggle: finance == null
                ? null
                : () async {
                    final saved = await finance!.saveCategory(
                      category.status == CategoryStatus.active
                          ? category.archive()
                          : Category(
                              id: category.id,
                              name: category.name,
                              origin: category.origin,
                              parentId: category.parentId,
                            ),
                    );
                    if (saved is ApplicationSuccess<Category>) {
                      onChanged();
                    } else if (context.mounted) {
                      _showFailure(context);
                    }
                  },
          ),
      ],
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => children.isEmpty
      ? ButlerlyEmptyState(
          icon: Icons.folder_open_outlined,
          title: context.l10n.text('noMasterData'),
          message: context.l10n.text('masterDataSubtitle'),
        )
      : ButlerlyCard(
          padding: EdgeInsets.zero,
          child: ButlerlySeparatedList(children: children),
        );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.origin,
    required this.active,
    required this.onToggle,
    this.onEdit,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String origin;
  final bool active;
  final VoidCallback? onToggle;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: Text(
      [
        ?subtitle,
        origin,
        if (!active) context.l10n.text('archived'),
      ].join(' · '),
    ),
    trailing: onToggle == null && onEdit == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onEdit != null)
                IconButton(
                  tooltip: context.l10n.text('edit'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
              if (onToggle != null)
                IconButton(
                  tooltip: context.l10n.text(
                    active ? 'deactivate' : 'reactivate',
                  ),
                  icon: Icon(
                    active
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: onToggle,
                ),
            ],
          ),
  );
}

final class _MerchantDraft {
  const _MerchantDraft({
    required this.name,
    required this.aliases,
    required this.patterns,
  });

  final String name;
  final List<String> aliases;
  final List<String> patterns;
}

class _MerchantEditorSheet extends StatefulWidget {
  const _MerchantEditorSheet({required this.merchant});

  final Merchant merchant;

  @override
  State<_MerchantEditorSheet> createState() => _MerchantEditorSheetState();
}

class _MerchantEditorSheetState extends State<_MerchantEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _aliases;
  late final TextEditingController _patterns;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.merchant.name);
    _aliases = TextEditingController(
      text: widget.merchant.aliases.map((value) => value.alias).join('\n'),
    );
    _patterns = TextEditingController(
      text: widget.merchant.normalizationPatterns
          .map((value) => value.pattern)
          .join('\n'),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _aliases.dispose();
    _patterns.dispose();
    super.dispose();
  }

  List<String> _lines(String value) => value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toSet()
      .toList(growable: false);

  @override
  Widget build(BuildContext context) => ButlerlySheet(
    key: const ValueKey('master-data-edit-sheet'),
    title: Text(context.l10n.text('editMerchant')),
    content: Column(
      children: [
        TextField(
          controller: _name,
          enabled: !widget.merchant.isBuiltIn,
          decoration: InputDecoration(
            labelText: context.l10n.text('merchantName'),
          ),
        ),
        TextField(
          controller: _aliases,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.l10n.text('merchantAliases'),
            helperText: context.l10n.text('merchantAliasesBody'),
          ),
        ),
        TextField(
          controller: _patterns,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.l10n.text('merchantNormalizationPatterns'),
            helperText: context.l10n.text('merchantNormalizationPatternsBody'),
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.text('cancel')),
      ),
      FilledButton(
        onPressed: () {
          final name = _name.text.trim();
          if (name.isEmpty) return;
          Navigator.pop(
            context,
            _MerchantDraft(
              name: name,
              aliases: _lines(_aliases.text),
              patterns: _lines(_patterns.text),
            ),
          );
        },
        child: Text(context.l10n.text('save')),
      ),
    ],
  );
}
