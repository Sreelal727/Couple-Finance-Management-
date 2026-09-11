import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/category_icons.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoriesPage()));

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Expense'),
              Tab(text: 'Income'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _List(cats: data.expenseCategories, kind: CategoryKind.expense),
            _List(cats: data.incomeCategories, kind: CategoryKind.income),
          ],
        ),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton(
            onPressed: () => editCategory(
              ctx,
              null,
              DefaultTabController.of(ctx).index == 0 ? CategoryKind.expense : CategoryKind.income,
            ),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.cats, required this.kind});
  final List<Category> cats;
  final CategoryKind kind;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<Repository>();
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        for (final c in cats)
          ListTile(
            leading: CategoryIcon(category: c),
            title: Text(c.name),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                if (await confirm(
                  context,
                  'Delete "${c.name}"?',
                  message: 'Existing entries keep their data but show as uncategorised.',
                )) {
                  await repo.softDelete('categories', c.id);
                }
              },
            ),
            onTap: () => editCategory(context, c, kind),
          ),
      ],
    );
  }
}

Future<void> editCategory(BuildContext context, Category? existing, CategoryKind kind) async {
  final repo = context.read<Repository>();
  final data = context.read<AppData>();
  final name = TextEditingController(text: existing?.name ?? '');
  var icon = existing?.icon ?? 'other';
  var color = existing?.colorHex ?? '#0E7C7B';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'New category' : 'Edit category'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              const Text('Icon'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in CategoryIcons.map.entries)
                    InkWell(
                      onTap: () => setState(() => icon = e.key),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: icon == e.key ? Theme.of(ctx).colorScheme.primaryContainer : null,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(e.value, size: 22),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Colour'),
              const SizedBox(height: 8),
              ColorPickerRow(selected: color, onSelected: (c) => setState(() => color = c)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return;
  await repo.save(
    Category(
      meta: existing?.meta ?? repo.newMeta(),
      name: name.text.trim(),
      icon: icon,
      colorHex: color,
      kind: existing?.kind ?? kind,
      sortOrder:
          existing?.sortOrder ??
          (kind == CategoryKind.expense ? data.expenseCategories.length : data.incomeCategories.length),
    ),
  );
}
