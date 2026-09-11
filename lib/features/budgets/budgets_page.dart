import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';

class BudgetsPage extends StatelessWidget {
  const BudgetsPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BudgetsPage()));

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final repo = context.read<Repository>();
    final overall = data.budgets.where((b) => b.categoryId == null).firstOrNull;
    final byCat = {for (final b in data.budgets.where((b) => b.categoryId != null)) b.categoryId!: b};
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly budgets')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.account_balance_wallet_rounded)),
            title: const Text('Overall monthly budget'),
            subtitle: Text(overall == null ? 'Not set' : Money.format(overall.amountPaise)),
            trailing: const Icon(Icons.edit_rounded),
            onTap: () => _edit(context, repo, overall, null),
          ),
          const Divider(),
          const SectionHeader('Per category'),
          for (final c in data.expenseCategories)
            ListTile(
              leading: CategoryIcon(category: c),
              title: Text(c.name),
              subtitle: Text(byCat[c.id] == null ? 'No limit' : Money.format(byCat[c.id]!.amountPaise)),
              trailing: byCat[c.id] == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => repo.softDelete('budgets', byCat[c.id]!.meta.id),
                    ),
              onTap: () => _edit(context, repo, byCat[c.id], c.id),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, Repository repo, Budget? existing, String? categoryId) async {
    final v = await askText(
      context,
      'Monthly budget (₹)',
      initial: existing == null ? null : Money.editable(existing.amountPaise),
      keyboard: TextInputType.number,
    );
    if (v == null) return;
    final paise = Money.parse(v);
    if (paise == null || paise <= 0) {
      if (existing != null) await repo.softDelete('budgets', existing.meta.id);
      return;
    }
    await repo.save(Budget(meta: existing?.meta ?? repo.newMeta(), categoryId: categoryId, amountPaise: paise));
  }
}
