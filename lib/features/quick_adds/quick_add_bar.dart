import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';
import '../transactions/add_txn_page.dart';
import 'quick_adds_page.dart';

/// Horizontal row of one-tap templates on the home screen.
class QuickAddBar extends StatelessWidget {
  const QuickAddBar({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final q in data.quickAdds)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: CategoryIcon(category: data.category(q.categoryId), size: 22),
                label: Text(q.amountPaise > 0 ? '${q.label} ${Money.format(q.amountPaise)}' : q.label),
                onPressed: () => _tap(context, q),
              ),
            ),
          ActionChip(
            avatar: const Icon(Icons.add_rounded, size: 18),
            label: Text(data.quickAdds.isEmpty ? 'Create quick adds' : 'Edit'),
            onPressed: () => QuickAddsPage.open(context),
          ),
        ],
      ),
    );
  }

  Future<void> _tap(BuildContext context, QuickAdd q) async {
    final repo = context.read<Repository>();
    if (q.amountPaise <= 0) {
      await AddTxnPage.open(
        context,
        prefill: TxnPrefill(title: q.label, categoryId: q.categoryId, isShared: q.isShared, source: TxnSource.quick),
      );
      return;
    }
    final txn = Txn(
      meta: repo.newMeta(),
      type: TxnType.expense,
      amountPaise: q.amountPaise,
      categoryId: q.categoryId,
      title: q.label,
      note: '',
      merchant: null,
      occurredAt: Dates.nowMs(),
      paidBy: repo.identity.memberId,
      isShared: q.isShared,
      payerSharePaise: q.isShared ? (q.amountPaise / 2).round() : q.amountPaise,
      source: TxnSource.quick,
      smsRef: null,
    );
    await repo.save(txn);
    if (!context.mounted) return;
    showSnack(
      context,
      'Added ${q.label} ${Money.format(q.amountPaise)}',
      action: SnackBarAction(label: 'Undo', onPressed: () => repo.softDelete('transactions', txn.id)),
    );
  }
}
