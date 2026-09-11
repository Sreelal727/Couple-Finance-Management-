import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';
import '../transactions/txn_detail_page.dart';

class SettlePage extends StatefulWidget {
  const SettlePage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettlePage()));

  @override
  State<SettlePage> createState() => _SettlePageState();
}

class _SettlePageState extends State<SettlePage> {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final data = context.watch<AppData>();
    final b = data.balance;
    final me = data.me;
    final partnerId = data.partner?.id ?? data.peers.firstOrNull?.memberId;
    final partnerName = data.partnerName;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settle up')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: scheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    b == null || b.settled
                        ? 'All settled up 🎉'
                        : b.netPaise > 0
                        ? '$partnerName owes ${me?.name ?? 'you'}'
                        : '${me?.name ?? 'You'} owe${me == null ? '' : 's'} $partnerName',
                    style: TextStyle(color: scheme.onSecondaryContainer),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    Money.format(b?.netPaise.abs() ?? 0),
                    style: Theme.of(context).textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSecondaryContainer),
                  ),
                  const SizedBox(height: 12),
                  if (b != null && !b.settled && partnerId != null)
                    FilledButton.icon(
                      icon: const Icon(Icons.handshake_rounded),
                      label: const Text('Record a settlement'),
                      onPressed: () => _settle(context, b, partnerId),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Shared expenses are split as you chose when adding them. Settling records a payment between you two; it does not create an expense.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
          const SectionHeader('Settlements'),
          FutureBuilder<List<Settlement>>(
            future: repo.settlements(),
            builder: (ctx, snap) {
              final items = snap.data ?? const [];
              if (items.isEmpty) return Text('No settlements yet.', style: TextStyle(color: scheme.outline));
              return Column(
                children: [
                  for (final s in items)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.swap_horiz_rounded),
                      title: Text(
                        '${data.memberName(s.fromMember)} paid ${data.memberName(s.toMember)} ${Money.format(s.amountPaise)}',
                      ),
                      subtitle: Text(
                        '${Dates.dayLabel(Dates.fromMs(s.occurredAt))}${s.note.isNotEmpty ? ' · ${s.note}' : ''}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () async {
                          if (await confirm(context, 'Delete this settlement?')) {
                            await repo.softDelete('settlements', s.meta.id);
                          }
                        },
                      ),
                    ),
                ],
              );
            },
          ),
          const SectionHeader('Recent shared expenses'),
          FutureBuilder<List<Txn>>(
            future: repo.recentTxns(limit: 60),
            builder: (ctx, snap) {
              final items = (snap.data ?? const <Txn>[])
                  .where((t) => t.isShared && t.type == TxnType.expense)
                  .take(20)
                  .toList();
              if (items.isEmpty) return Text('No shared expenses yet.', style: TextStyle(color: scheme.outline));
              return Column(
                children: [
                  for (final t in items)
                    TxnTile(txn: t, showDate: true, onTap: () => TxnDetailPage.open(context, t.id)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _settle(BuildContext context, Balance b, String partnerId) async {
    final repo = context.read<Repository>();
    final amountCtrl = TextEditingController(text: Money.editable(b.netPaise.abs()));
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record settlement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'GPay, cash…'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final amount = Money.parse(amountCtrl.text);
    if (amount == null || amount <= 0) return;
    final meId = repo.identity.memberId;
    await repo.save(
      Settlement(
        meta: repo.newMeta(),
        fromMember: b.netPaise > 0 ? partnerId : meId,
        toMember: b.netPaise > 0 ? meId : partnerId,
        amountPaise: amount,
        occurredAt: Dates.nowMs(),
        note: noteCtrl.text.trim(),
      ),
    );
    if (mounted) setState(() {});
  }
}
