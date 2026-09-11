import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/category_icons.dart';
import '../../data/models.dart';
import 'app_data.dart';

class MemberAvatar extends StatelessWidget {
  const MemberAvatar({super.key, required this.member, this.radius = 14, this.name});
  final Member? member;
  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final label = (member?.name ?? name ?? '?');
    final color = member == null ? Theme.of(context).colorScheme.outline : MemberColors.parse(member!.colorHex);
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        label.isEmpty ? '?' : label[0].toUpperCase(),
        style: TextStyle(color: Colors.white, fontSize: radius, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class CategoryIcon extends StatelessWidget {
  const CategoryIcon({super.key, required this.category, this.size = 40, this.fallback});
  final Category? category;
  final double size;
  final IconData? fallback;

  @override
  Widget build(BuildContext context) {
    final color = category == null ? Theme.of(context).colorScheme.outline : MemberColors.parse(category!.colorHex);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(size / 3)),
      child: Icon(
        category == null ? (fallback ?? Icons.category_rounded) : CategoryIcons.of(category!.icon),
        color: color,
        size: size * 0.55,
      ),
    );
  }
}

/// One row in any transaction list.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, this.onTap, this.showDate = false});
  final Txn txn;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final cat = data.category(txn.categoryId);
    final payer = data.member(txn.paidBy);
    final isIncome = txn.type == TxnType.income;
    final scheme = Theme.of(context).colorScheme;
    final subtitleParts = <String>[
      if (showDate) Dates.dayLabel(Dates.fromMs(txn.occurredAt)) else Dates.time(Dates.fromMs(txn.occurredAt)),
      if (cat != null) cat.name,
      if (txn.isShared) 'Shared' else 'Personal',
    ];
    return ListTile(
      onTap: onTap,
      leading: CategoryIcon(category: cat, fallback: isIncome ? Icons.payments_rounded : null),
      title: Text(
        txn.title.isNotEmpty ? txn.title : (txn.merchant ?? cat?.name ?? (isIncome ? 'Income' : 'Expense')),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(subtitleParts.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            (isIncome ? '+' : '') + Money.format(txn.amountPaise),
            style: TextStyle(fontWeight: FontWeight.w600, color: isIncome ? Colors.green.shade700 : scheme.onSurface),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MemberAvatar(member: payer, radius: 8, name: data.memberName(txn.paidBy)),
              const SizedBox(width: 4),
              Text(data.memberName(txn.paidBy), style: Theme.of(context).textTheme.labelSmall),
              if (txn.source == TxnSource.sms) ...[
                const SizedBox(width: 4),
                Icon(Icons.sms_rounded, size: 12, color: scheme.outline),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.actionLabel});
  final String title;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
          if (action != null) TextButton(onPressed: action, child: Text(actionLabel ?? 'See all')),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// ‹ September 2026 › selector.
class MonthPicker extends StatelessWidget {
  const MonthPicker({super.key, required this.month, required this.onChanged});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
        ),
        TextButton(
          onPressed: isCurrent ? null : () => onChanged(DateTime(now.year, now.month)),
          child: Text(Dates.monthLabel(month), style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: isCurrent ? null : () => onChanged(DateTime(month.year, month.month + 1)),
        ),
      ],
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.color, this.icon});
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 16, color: color ?? scheme.primary), const SizedBox(width: 6)],
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showSnack(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}

Future<bool> confirm(BuildContext context, String title, {String? message, String okLabel = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okLabel)),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> askText(
  BuildContext context,
  String title, {
  String? initial,
  String? hint,
  TextInputType? keyboard,
  String okLabel = 'Save',
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        keyboardType: keyboard,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(okLabel)),
      ],
    ),
  );
}

/// Colour swatches row used for members, categories and goals.
class ColorPickerRow extends StatelessWidget {
  const ColorPickerRow({super.key, required this.selected, required this.onSelected, this.colors});
  final String selected;
  final ValueChanged<String> onSelected;
  final List<Color>? colors;

  static const defaults = <Color>[
    Color(0xFF0E7C7B),
    Color(0xFFD1495B),
    Color(0xFF3A6EA5),
    Color(0xFFEDAE49),
    Color(0xFF6A4C93),
    Color(0xFF2A9D8F),
    Color(0xFFE76F51),
    Color(0xFFF4A261),
    Color(0xFF588157),
    Color(0xFF9B5DE5),
    Color(0xFFF15BB5),
    Color(0xFF00BBF9),
    Color(0xFFBC6C25),
    Color(0xFF6C757D),
    Color(0xFF8D6E63),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final c in colors ?? defaults)
          GestureDetector(
            onTap: () => onSelected(MemberColors.toHex(c)),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: MemberColors.toHex(c) == selected.toUpperCase()
                    ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3)
                    : null,
              ),
              child: MemberColors.toHex(c) == selected.toUpperCase()
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
          ),
      ],
    );
  }
}
