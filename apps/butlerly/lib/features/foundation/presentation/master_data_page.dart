import 'package:butlerly/core/di/finance_services.dart';
import 'package:butlerly/core/di/service_locator.dart';
import 'package:butlerly/design_system/components/butlerly_components.dart';
import 'package:butlerly/design_system/tokens/butlerly_tokens.dart';
import 'package:butlerly/features/foundation/presentation/master_data_labels.dart';
import 'package:butlerly/l10n/app_localizations.dart';
import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:flutter/material.dart';

class MasterDataPage extends StatefulWidget {
  const MasterDataPage({super.key});

  @override
  State<MasterDataPage> createState() => _MasterDataPageState();
}

class _MasterDataPageState extends State<MasterDataPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late Future<_MasterData> _data;

  FinanceServices? get _finance => services.isRegistered<FinanceServices>()
      ? services<FinanceServices>()
      : null;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<_MasterData> _load() async {
    final finance = _finance;
    if (finance == null) return const _MasterData([], [], []);
    final categories = await finance.listCategories();
    final tags = await finance.listTags();
    if (categories is! ApplicationSuccess<List<Category>> ||
        tags is! ApplicationSuccess<List<Tag>>) {
      throw StateError('Master data could not be loaded.');
    }
    return _MasterData(categories.value, tags.value, []);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _data = _load());
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
    final currentName = value is Category ? value.name : (value as Tag).name;
    final name = await _editDialog(
      context,
      title: context.l10n.text('edit'),
      labelKey: value is Category ? 'categoryName' : 'tagName',
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
    } else {
      final tag = value as Tag;
      final saved = await finance.saveTag(
        Tag(id: tag.id, name: name, status: tag.status),
      );
      if (!_accepted(saved)) return;
    }
    if (mounted) _refresh();
  }

  Future<void> _add() async {
    final index = _tabs.index;
    final result = await _editDialog(
      context,
      title: context.l10n.text(
        index == 0
            ? 'addCategory'
            : index == 1
            ? 'addSubcategory'
            : 'addTagManagement',
      ),
      labelKey: index == 0
          ? 'categoryName'
          : index == 1
          ? 'subcategoryName'
          : 'tagName',
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
    return showDialog<CategoryId>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.text('parentCategory')),
        children: [
          for (final category in roots)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, category.id),
              child: Text(
                categoryDisplayLabel(
                  category,
                  Localizations.localeOf(context).languageCode,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<String?> _editDialog(
    BuildContext context, {
    required String title,
    required String labelKey,
    String? initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
    controller.dispose();
    return result?.trim().isEmpty == true ? null : result?.trim();
  }

  @override
  Widget build(BuildContext context) => ButlerlyPage(
    title: context.l10n.text('masterData'),
    pinnedHeader: TabBar(
      controller: _tabs,
      tabs: [
        Tab(text: context.l10n.text('categories')),
        Tab(text: context.l10n.text('subcategories')),
        Tab(text: context.l10n.text('tags')),
      ],
    ),
    children: [
      const SizedBox(height: 0),
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: Text(context.l10n.text('add')),
                ),
              ),
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: _tabs,
                builder: (context, _) => _MasterDataList(
                  index: _tabs.index,
                  data: data,
                  onChanged: _refresh,
                  finance: _finance,
                  onEdit: _editExisting,
                ),
              ),
            ],
          );
        },
      ),
      const SizedBox(height: ButlerlySpacing.structural),
    ],
  );
}

final class _MasterData {
  const _MasterData(this.categories, this.tags, this.unused);
  final List<Category> categories;
  final List<Tag> tags;
  final List<Object> unused;
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

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    if (index == 2) {
      return _ListCard(
        children: [
          for (final tag in data.tags)
            _Row(
              title: tagDisplayLabel(tag, language),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.text('dataPreserved')),
                          ),
                        );
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
            title: categoryDisplayLabel(category, language),
            subtitle: index == 1
                ? data.categories
                      .where((parent) => parent.id == category.parentId)
                      .map((parent) => categoryDisplayLabel(parent, language))
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.l10n.text('dataPreserved')),
                        ),
                      );
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
