import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../sync/sync_service.dart';
import '../quick_adds/quick_add_bar.dart';
import '../settle/settle_page.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';
import '../sms_inbox/sms_inbox_page.dart';
import '../sync/sync_page.dart';
import '../transactions/txn_detail_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onSeeAll});
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final repo = context.watch<Repository>();
    final sync = context.watch<SyncService>();
    final now = DateTime.now();
    final hour = now.hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');

    return RefreshIndicator(
      onRefresh: () async {
        await data.reload();
        if (sync.isPaired) {
          try {
            await sync.syncNow();
          } catch (_) {}
        }
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$greeting, ${data.me?.name ?? ''}', style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        Dates.monthLabel(now),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                _SyncPill(onTap: () => SyncPage.open(context)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FutureBuilder<List<Txn>>(
              future: repo.txnsForMonth(now),
              builder: (ctx, snap) => _MonthCard(txns: snap.data ?? const []),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _BalanceCard(onTap: () => SettlePage.open(context)),
          ),
          if (data.pendingSms > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.sms_rounded),
                  title: Text(
                    '${data.pendingSms} bank ${data.pendingSms == 1 ? 'transaction' : 'transactions'} detected',
                  ),
                  subtitle: const Text('Tap to add them with a name'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => SmsInboxPage.open(context),
                ),
              ),
            ),
          const SectionHeader('Quick add'),
          const QuickAddBar(),
          SectionHeader('Recent', action: onSeeAll),
          FutureBuilder<List<Txn>>(
            future: repo.recentTxns(limit: 10),
            builder: (ctx, snap) {
              final items = snap.data ?? const [];
              if (snap.hasData && items.isEmpty) {
                return const EmptyState(
                  icon: Icons.receipt_long_rounded,
                  title: 'No entries yet',
                  subtitle: 'Tap + to add your first expense, or turn on SMS capture in Settings.',
                );
              }
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
}

class _SyncPill extends StatelessWidget {
  const _SyncPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final data = context.watch<AppData>();
    final scheme = Theme.of(context).colorScheme;
    final peer = data.peers.firstOrNull;
    final online = peer != null && sync.sightings.containsKey(peer.deviceId);
    String label;
    IconData icon;
    Color color;
    if (!sync.isPaired) {
      label = 'Pair';
      icon = Icons.link_rounded;
      color = scheme.outline;
    } else if (sync.phase == SyncPhase.syncing) {
      label = 'Syncing';
      icon = Icons.sync_rounded;
      color = scheme.primary;
    } else if (online) {
      label = '${peer.name} nearby';
      icon = Icons.wifi_rounded;
      color = Colors.green.shade700;
    } else {
      label = peer?.lastSyncAt == null ? 'Not synced' : Dates.relative(Dates.fromMs(peer!.lastSyncAt!));
      icon = Icons.wifi_off_rounded;
      color = scheme.outline;
    }
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color)),
      onPressed: onTap,
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.txns});
  final List<Txn> txns;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final scheme = Theme.of(context).colorScheme;
    final spent = txns.where((t) => t.type == TxnType.expense).fold<int>(0, (n, t) => n + t.amountPaise);
    final income = txns.where((t) => t.type == TxnType.income).fold<int>(0, (n, t) => n + t.amountPaise);
    final overall = data.budgets.where((b) => b.categoryId == null).firstOrNull;
    final byPerson = <String, int>{};
    for (final t in txns.where((t) => t.type == TxnType.expense)) {
      byPerson[t.paidBy] = (byPerson[t.paidBy] ?? 0) + t.amountPaise;
    }
    final now = DateTime.now();
    final daysLeft = Dates.nextMonthStart(now).difference(DateTime(now.year, now.month, now.day)).inDays;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spent this month', style: TextStyle(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(
              Money.format(spent),
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800, color: scheme.onPrimaryContainer),
            ),
            if (overall != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: overall.amountPaise == 0 ? 0 : (spent / overall.amountPaise).clamp(0, 1),
                  minHeight: 8,
                  color: spent > overall.amountPaise ? scheme.error : scheme.primary,
                  backgroundColor: scheme.onPrimaryContainer.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                spent > overall.amountPaise
                    ? '${Money.format(spent - overall.amountPaise)} over budget'
                    : '${Money.format(overall.amountPaise - spent)} left of ${Money.format(overall.amountPaise)} · $daysLeft days to go',
                style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                for (final m in data.members) ...[
                  MemberAvatar(member: m, radius: 10),
                  const SizedBox(width: 4),
                  Text(
                    '${m.name} ${Money.format(byPerson[m.id] ?? 0)}',
                    style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                ],
                const Spacer(),
                if (income > 0)
                  Text('+${Money.format(income)} in', style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 13)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final scheme = Theme.of(context).colorScheme;
    final b = data.balance;
    final me = data.me?.name ?? 'You';
    final partner = data.partnerName;
    String text;
    IconData icon;
    if (b == null || b.settled) {
      text = 'All settled up';
      icon = Icons.handshake_rounded;
    } else if (b.netPaise > 0) {
      text = '$partner owes $me ${Money.format(b.netPaise)}';
      icon = Icons.call_received_rounded;
    } else {
      text = '$me owe${me == 'You' ? '' : 's'} $partner ${Money.format(-b.netPaise)}';
      icon = Icons.call_made_rounded;
    }
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          child: Icon(icon, color: scheme.onSecondaryContainer),
        ),
        title: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Shared expenses · tap to settle up'),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
