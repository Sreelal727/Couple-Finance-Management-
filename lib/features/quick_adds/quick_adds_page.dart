import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';

class QuickAddsPage extends StatelessWidget {
  const QuickAddsPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuickAddsPage()));

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final repo = context.read<Repository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Quick adds')),
      body: data.quickAdds.isEmpty
          ? EmptyState(
              icon: Icons.bolt_rounded,
              title: 'One-tap expenses',
              subtitle: 'Things you pay for often: auto ₹40, tea ₹15, milk ₹30. Tap once on the home screen and it\'s logged.',
              action: FilledButton(onPressed: () => _edit(context, null), child: const Text('Add one')),
            )
          : ListView(
              children: [
                for (final q in data.quickAdds)
                  ListTile(
                    leading: CategoryIcon(category: data.category(q.categoryId)),
                    title: Text(q.label),
                    subtitle: Text(
                      '${q.amountPaise > 0 ? Money.format(q.amountPaise) : 'Ask amount'} · ${q.isShared ? 'Shared' : 'Personal'}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => repo.softDelete('quick_adds', q.id),
                    ),
                    onTap: () => _edit(context, q),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(context, null),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Future<void> _edit(BuildContext context, QuickAdd? existing) async {
    final repo = context.read<Repository>();
    final data = context.read<AppData>();
    final label = TextEditingController(text: existing?.label ?? '');
    final amount = TextEditingController(
      text: existing == null || existing.amountPaise == 0 ? '' : Money.editable(existing.amountPaise),
    );
    String? catId = existing?.categoryId ?? data.expenseCategories.firstOrNull?.id;
    var shared = existing?.isShared ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'New quick add' : 'Edit quick add'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Label', hintText: 'Auto to office'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹)',
                    helperText: 'Leave empty to ask each time',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: catId,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [for (final c in data.expenseCategories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => catId = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Shared expense'),
                  value: shared,
                  onChanged: (v) => setState(() => shared = v),
                ),
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
    if (ok != true || label.text.trim().isEmpty) return;
    await repo.save(
      QuickAdd(
        meta: existing?.meta ?? repo.newMeta(),
        label: label.text.trim(),
        amountPaise: Money.parse(amount.text) ?? 0,
        categoryId: catId,
        isShared: shared,
        sortOrder: existing?.sortOrder ?? data.quickAdds.length,
      ),
    );
  }
}
