import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';
import 'txn_detail_page.dart';

enum _Filter { all, mine, partner, shared, income }

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime _month = Dates.monthStart(DateTime.now());
  _Filter _filter = _Filter.all;
  String _query = '';
  final _search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final data = context.watch<AppData>();
    final meId = repo.identity.memberId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Search title, note, merchant',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final f in _Filter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6, bottom: 8),
                        child: ChoiceChip(
                          label: Text(switch (f) {
                            _Filter.all => 'All',
                            _Filter.mine => data.me?.name ?? 'Me',
                            _Filter.partner => data.partnerName,
                            _Filter.shared => 'Shared',
                            _Filter.income => 'Income',
                          }),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          if (_query.isEmpty) MonthPicker(month: _month, onChanged: (m) => setState(() => _month = m)),
          Expanded(
            child: FutureBuilder<List<Txn>>(
              future: _query.isEmpty ? repo.txnsForMonth(_month) : repo.searchTxns(_query),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final partnerId = data.partner?.id ?? data.peers.firstOrNull?.memberId;
                final items = snap.data!.where((t) {
                  switch (_filter) {
                    case _Filter.all:
                      return true;
                    case _Filter.mine:
                      return t.paidBy == meId;
                    case _Filter.partner:
                      return t.paidBy == partnerId;
                    case _Filter.shared:
                      return t.isShared && t.type == TxnType.expense;
                    case _Filter.income:
                      return t.type == TxnType.income;
                  }
                }).toList();
                if (items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'Nothing here',
                    subtitle: 'Try another month or filter.',
                  );
                }
                final spent = items.where((t) => t.type == TxnType.expense).fold<int>(0, (n, t) => n + t.amountPaise);
                final income = items.where((t) => t.type == TxnType.income).fold<int>(0, (n, t) => n + t.amountPaise);
                // Group by day.
                final groups = <String, List<Txn>>{};
                for (final t in items) {
                  groups.putIfAbsent(Dates.dayLabel(Dates.fromMs(t.occurredAt)), () => []).add(t);
                }
                return ListView(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Text('${items.length} entries', style: Theme.of(context).textTheme.labelLarge),
                          const Spacer(),
                          if (income > 0)
                            Text('+${Money.format(income)}  ', style: TextStyle(color: Colors.green.shade700)),
                          Text('−${Money.format(spent)}', style: Theme.of(context).textTheme.labelLarge),
                        ],
                      ),
                    ),
                    for (final e in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                        child: Row(
                          children: [
                            Text(
                              e.key,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
                            ),
                            const Spacer(),
                            Text(
                              Money.format(
                                e.value
                                    .where((t) => t.type == TxnType.expense)
                                    .fold<int>(0, (n, t) => n + t.amountPaise),
                              ),
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                      for (final t in e.value) TxnTile(txn: t, onTap: () => TxnDetailPage.open(context, t.id)),
                    ],
                    const SizedBox(height: 80),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
