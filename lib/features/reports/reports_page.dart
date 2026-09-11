import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  DateTime _month = Dates.monthStart(DateTime.now());
  int? _touchedSection;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final data = context.watch<AppData>();
    final sixMonthsAgo = DateTime(_month.year, _month.month - 5);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Export this month as CSV',
            icon: const Icon(Icons.ios_share_rounded),
            onPressed: () => _exportCsv(context),
          ),
        ],
      ),
      body: FutureBuilder<List<Txn>>(
        future: repo.txnsInRange(sixMonthsAgo, Dates.nextMonthStart(_month)),
        builder: (ctx, snap) {
          final all = snap.data ?? const <Txn>[];
          final start = _month.millisecondsSinceEpoch;
          final end = Dates.nextMonthStart(_month).millisecondsSinceEpoch;
          final txns = all.where((t) => t.occurredAt >= start && t.occurredAt < end).toList();
          final expenses = txns.where((t) => t.type == TxnType.expense).toList();
          final spent = expenses.fold<int>(0, (n, t) => n + t.amountPaise);
          final income = txns.where((t) => t.type == TxnType.income).fold<int>(0, (n, t) => n + t.amountPaise);
          final byCat = <String?, int>{};
          for (final t in expenses) {
            byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amountPaise;
          }
          final catRows = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          final byPerson = <String, int>{};
          for (final t in expenses) {
            byPerson[t.paidBy] = (byPerson[t.paidBy] ?? 0) + t.amountPaise;
          }
          final sharedTotal = expenses.where((t) => t.isShared).fold<int>(0, (n, t) => n + t.amountPaise);
          final byTitle = <String, int>{};
          for (final t in expenses) {
            final k = t.title.isNotEmpty ? t.title : (t.merchant ?? '');
            if (k.isEmpty) continue;
            byTitle[k] = (byTitle[k] ?? 0) + t.amountPaise;
          }
          final topTitles = byTitle.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
          // Monthly series (spent), last 6 months ending at _month.
          final months = List.generate(6, (i) => DateTime(_month.year, _month.month - 5 + i));
          final monthly = [
            for (final m in months)
              all
                  .where(
                    (t) =>
                        t.type == TxnType.expense &&
                        t.occurredAt >= m.millisecondsSinceEpoch &&
                        t.occurredAt < Dates.nextMonthStart(m).millisecondsSinceEpoch,
                  )
                  .fold<int>(0, (n, t) => n + t.amountPaise),
          ];
          final overallBudget = data.budgets.where((b) => b.categoryId == null).firstOrNull;
          final catBudgets = {
            for (final b in data.budgets.where((b) => b.categoryId != null)) b.categoryId!: b.amountPaise,
          };

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              MonthPicker(month: _month, onChanged: (m) => setState(() => _month = m)),
              Row(
                children: [
                  Expanded(
                    child: StatTile(label: 'Spent', value: Money.format(spent), icon: Icons.arrow_upward_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Income',
                      value: Money.format(income),
                      icon: Icons.arrow_downward_rounded,
                      color: Colors.green.shade700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(
                      label: 'Saved',
                      value: Money.signed(income - spent),
                      icon: Icons.savings_rounded,
                      color: income - spent >= 0 ? Colors.green.shade700 : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final m in data.members) ...[
                    Expanded(
                      child: StatTile(
                        label: '${m.name} paid',
                        value: Money.format(byPerson[m.id] ?? 0),
                        color: MemberColors.parse(m.colorHex),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: StatTile(label: 'Shared', value: Money.format(sharedTotal), icon: Icons.people_rounded),
                  ),
                ],
              ),
              if (overallBudget != null) ...[
                const SizedBox(height: 8),
                _BudgetLine(label: 'Overall budget', spent: spent, budget: overallBudget.amountPaise),
              ],
              const SectionHeader('By category'),
              if (catRows.isEmpty)
                Text('No expenses this month.', style: TextStyle(color: Theme.of(context).colorScheme.outline))
              else ...[
                SizedBox(
                  height: 200,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 56,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, resp) => setState(() {
                          _touchedSection = resp?.touchedSection?.touchedSectionIndex;
                        }),
                      ),
                      sections: [
                        for (var i = 0; i < catRows.length; i++)
                          PieChartSectionData(
                            value: catRows[i].value.toDouble(),
                            color: _catColor(context, data, catRows[i].key, i),
                            radius: _touchedSection == i ? 34 : 26,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                ),
                if (_touchedSection != null && _touchedSection! < catRows.length)
                  Center(
                    child: Text(
                      '${data.category(catRows[_touchedSection!].key)?.name ?? 'Uncategorised'} · ${Money.format(catRows[_touchedSection!].value)}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                const SizedBox(height: 8),
                for (var i = 0; i < catRows.length; i++)
                  _CategoryRow(
                    color: _catColor(context, data, catRows[i].key, i),
                    name: data.category(catRows[i].key)?.name ?? 'Uncategorised',
                    amount: catRows[i].value,
                    share: spent == 0 ? 0 : catRows[i].value / spent,
                    budget: catBudgets[catRows[i].key],
                  ),
              ],
              const SectionHeader('Last 6 months'),
              SizedBox(
                height: 180,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                          '${Dates.shortMonth(months[group.x])}\n${Money.format(monthly[group.x])}',
                          TextStyle(color: Theme.of(context).colorScheme.onInverseSurface),
                        ),
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      topTitles: const AxisTitles(),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, meta) => Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              Dates.shortMonth(months[v.toInt()]),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < 6; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY: monthly[i] / 100,
                              width: 22,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                              color: i == 5
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.primary.withValues(alpha: 0.45),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (var i = 0; i < 6; i++)
                      Text(monthly[i] == 0 ? '–' : _short(monthly[i]), style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
              if (topTitles.isNotEmpty) ...[
                const SectionHeader('Top spends'),
                for (final e in topTitles.take(8))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(e.key, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: Text(Money.format(e.value), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _short(int paise) {
    final r = paise / 100;
    if (r >= 100000) return '${(r / 100000).toStringAsFixed(1)}L';
    if (r >= 1000) return '${(r / 1000).toStringAsFixed(r >= 10000 ? 0 : 1)}k';
    return r.toStringAsFixed(0);
  }

  Color _catColor(BuildContext context, AppData data, String? catId, int index) {
    final c = data.category(catId);
    if (c != null) return MemberColors.parse(c.colorHex);
    return Theme.of(context).colorScheme.outline;
  }

  Future<void> _exportCsv(BuildContext context) async {
    final repo = context.read<Repository>();
    final data = context.read<AppData>();
    final txns = await repo.txnsForMonth(_month);
    final fmt = DateFormat('yyyy-MM-dd HH:mm');
    final buf = StringBuffer('date,type,amount,title,category,paid_by,shared,partner_owes,merchant,note,logged_by\n');
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    for (final t in txns.reversed) {
      buf.writeln(
        [
          fmt.format(Dates.fromMs(t.occurredAt)),
          t.type.name,
          (t.amountPaise / 100).toStringAsFixed(2),
          q(t.title),
          q(data.category(t.categoryId)?.name ?? ''),
          q(data.memberName(t.paidBy)),
          t.isShared ? 'yes' : 'no',
          (t.partnerOwesPaise / 100).toStringAsFixed(2),
          q(t.merchant ?? ''),
          q(t.note),
          q(data.memberName(t.meta.authorId)),
        ].join(','),
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'duo-finance-${DateFormat('yyyy-MM').format(_month)}.csv'));
    await file.writeAsString(buf.toString());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Duo Finance ${Dates.monthLabel(_month)}',
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.color, required this.name, required this.amount, required this.share, this.budget});
  final Color color;
  final String name;
  final int amount;
  final double share;
  final int? budget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = budget != null && amount > budget!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Text('${(share * 100).round()}%  ', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
              Text(Money.format(amount), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: budget != null ? (amount / budget!).clamp(0, 1) : share,
              minHeight: 5,
              color: over ? scheme.error : color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
          if (budget != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                over
                    ? '${Money.format(amount - budget!)} over the ${Money.format(budget!)} budget'
                    : '${Money.format(budget! - amount)} left of ${Money.format(budget!)}',
                style: TextStyle(color: over ? scheme.error : scheme.onSurfaceVariant, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _BudgetLine extends StatelessWidget {
  const _BudgetLine({required this.label, required this.spent, required this.budget});
  final String label;
  final int spent;
  final int budget;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final over = spent > budget;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label)),
                Text(
                  '${Money.format(spent)} / ${Money.format(budget)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (spent / budget).clamp(0, 1),
                minHeight: 8,
                color: over ? scheme.error : scheme.primary,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
