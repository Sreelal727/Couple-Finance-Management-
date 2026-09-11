import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/category_icons.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';

class GoalsPage extends StatelessWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Savings goals')),
      body: FutureBuilder<(List<Goal>, Map<String, int>)>(
        future: _loadGoals(repo),
        builder: (ctx, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (goals, totals) = snap.data!;
          final saved = totals.values.fold<int>(0, (a, b) => a + b);
          final target = goals.fold<int>(0, (a, g) => a + g.targetPaise);
          if (goals.isEmpty) {
            return EmptyState(
              icon: Icons.savings_rounded,
              title: 'Save for something together',
              subtitle: 'Emergency fund, a trip home, a new fridge. Track what each of you has put in.',
              action: FilledButton(onPressed: () => _editGoal(context, null), child: const Text('Create a goal')),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: StatTile(label: 'Total saved', value: Money.format(saved), icon: Icons.savings_rounded),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatTile(label: 'Of target', value: Money.format(target), icon: Icons.flag_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              for (final g in goals) _GoalCard(goal: g, saved: totals[g.id] ?? 0),
              const SizedBox(height: 80),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'goal_fab',
        onPressed: () => _editGoal(context, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Goal'),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.saved});
  final Goal goal;
  final int saved;

  @override
  Widget build(BuildContext context) {
    final color = MemberColors.parse(goal.colorHex);
    final progress = goal.targetPaise == 0 ? 0.0 : (saved / goal.targetPaise).clamp(0.0, 1.0);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => GoalDetailPage.open(context, goal.id),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(CategoryIcons.of(goal.icon), color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(goal.name, style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          '${Money.format(saved)} of ${Money.format(goal.targetPaise)}'
                          '${goal.deadline != null ? ' · by ${Dates.dayLabel(Dates.fromMs(goal.deadline!))}' : ''}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GoalDetailPage extends StatefulWidget {
  const GoalDetailPage({super.key, required this.goalId});
  final String goalId;

  static Future<void> open(BuildContext context, String id) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => GoalDetailPage(goalId: id)));

  @override
  State<GoalDetailPage> createState() => _GoalDetailPageState();
}

class _GoalDetailPageState extends State<GoalDetailPage> {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final data = context.watch<AppData>();
    return FutureBuilder<(Goal?, List<GoalContribution>, Map<String, Map<String, int>>)>(
      future: _loadGoal(repo, widget.goalId),
      builder: (ctx, snap) {
        final goal = snap.data?.$1;
        if (goal == null || goal.meta.deleted) {
          return Scaffold(
            appBar: AppBar(),
            body: snap.hasData
                ? const EmptyState(icon: Icons.savings_rounded, title: 'Goal deleted')
                : const SizedBox(),
          );
        }
        final contributions = snap.data!.$2;
        final byMember = snap.data!.$3[goal.id] ?? const {};
        final saved = byMember.values.fold<int>(0, (a, b) => a + b);
        final color = MemberColors.parse(goal.colorHex);
        return Scaffold(
          appBar: AppBar(
            title: Text(goal.name),
            actions: [
              IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => _editGoal(context, goal)),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (await confirm(context, 'Delete this goal?')) {
                    await repo.softDelete('goals', goal.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                Money.format(saved),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: color),
              ),
              Text(
                'of ${Money.format(goal.targetPaise)} · ${Money.format((goal.targetPaise - saved).clamp(0, goal.targetPaise))} to go',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final m in data.members)
                    Expanded(
                      child: StatTile(
                        label: m.name,
                        value: Money.format(byMember[m.id] ?? 0),
                        color: MemberColors.parse(m.colorHex),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add money'),
                onPressed: () => _contribute(context, goal, false),
              ),
              TextButton(onPressed: () => _contribute(context, goal, true), child: const Text('Withdraw')),
              const SectionHeader('Contributions'),
              for (final c in contributions)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: MemberAvatar(member: data.member(c.memberId), name: data.memberName(c.memberId)),
                  title: Text(
                    '${data.memberName(c.memberId)} ${c.amountPaise < 0 ? 'withdrew' : 'added'} ${Money.format(c.amountPaise.abs())}',
                  ),
                  subtitle: Text(
                    '${Dates.dayLabel(Dates.fromMs(c.occurredAt))}${c.note.isNotEmpty ? ' · ${c.note}' : ''}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => repo.softDelete('goal_contributions', c.meta.id),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _contribute(BuildContext context, Goal goal, bool withdraw) async {
    final repo = context.read<Repository>();
    final data = context.read<AppData>();
    final amount = TextEditingController();
    final note = TextEditingController();
    var member = repo.identity.memberId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(withdraw ? 'Withdraw from ${goal.name}' : 'Add to ${goal.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount (₹)'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final m in data.members)
                    ChoiceChip(
                      label: Text(m.name),
                      selected: member == m.id,
                      onSelected: (_) => setState(() => member = m.id),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final paise = Money.parse(amount.text);
    if (paise == null || paise <= 0) return;
    await repo.save(
      GoalContribution(
        meta: repo.newMeta(),
        goalId: goal.id,
        memberId: member,
        amountPaise: withdraw ? -paise : paise,
        occurredAt: Dates.nowMs(),
        note: note.text.trim(),
      ),
    );
    if (mounted) setState(() {});
  }
}

Future<void> _editGoal(BuildContext context, Goal? existing) async {
  final repo = context.read<Repository>();
  final name = TextEditingController(text: existing?.name ?? '');
  final target = TextEditingController(text: existing == null ? '' : Money.editable(existing.targetPaise));
  var icon = existing?.icon ?? 'savings';
  var color = existing?.colorHex ?? '#0E7C7B';
  DateTime? deadline = existing?.deadline == null ? null : Dates.fromMs(existing!.deadline!);
  const icons = [
    'savings',
    'travel',
    'home',
    'car',
    'bike',
    'phone',
    'laptop',
    'baby',
    'celebration',
    'beach',
    'temple',
    'gift',
    'education',
    'health',
    'star',
  ];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'New goal' : 'Edit goal'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'Emergency fund'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: target,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Target (₹)'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(deadline == null ? 'Target date (optional)' : Dates.dayLabel(deadline!)),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: deadline ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => deadline = d);
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final k in icons)
                    if (CategoryIcons.map.containsKey(k))
                      IconButton(
                        isSelected: icon == k,
                        icon: Icon(CategoryIcons.map[k]),
                        onPressed: () => setState(() => icon = k),
                      ),
                ],
              ),
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
  final paise = Money.parse(target.text) ?? 0;
  await repo.save(
    Goal(
      meta: existing?.meta ?? repo.newMeta(),
      name: name.text.trim(),
      targetPaise: paise,
      deadline: deadline?.millisecondsSinceEpoch,
      icon: icon,
      colorHex: color,
    ),
  );
}

Future<(List<Goal>, Map<String, int>)> _loadGoals(Repository repo) async =>
    (await repo.goals(), await repo.goalTotals());

Future<(Goal?, List<GoalContribution>, Map<String, Map<String, int>>)> _loadGoal(Repository repo, String id) async =>
    (await repo.goalById(id), await repo.contributions(id), await repo.goalTotalsByMember());
