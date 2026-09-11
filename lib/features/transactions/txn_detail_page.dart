import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../sync/attachment_store.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';
import 'add_txn_page.dart';

class TxnDetailPage extends StatefulWidget {
  const TxnDetailPage({super.key, required this.txnId});
  final String txnId;

  static Future<void> open(BuildContext context, String txnId) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TxnDetailPage(txnId: txnId)));

  @override
  State<TxnDetailPage> createState() => _TxnDetailPageState();
}

class _TxnDetailPageState extends State<TxnDetailPage> {
  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final data = context.watch<AppData>();
    return FutureBuilder<Txn?>(
      future: repo.txnById(widget.txnId),
      builder: (ctx, snap) {
        final t = snap.data;
        if (t == null || t.meta.deleted) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(icon: Icons.receipt_long_rounded, title: 'This entry was deleted'),
          );
        }
        final cat = data.category(t.categoryId);
        final payer = data.member(t.paidBy);
        final author = data.memberName(t.meta.authorId);
        final isIncome = t.type == TxnType.income;
        final scheme = Theme.of(context).colorScheme;
        final otherName = data.members.where((m) => m.id != t.paidBy).firstOrNull?.name ?? data.partnerName;
        return Scaffold(
          appBar: AppBar(
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                onPressed: () async {
                  await AddTxnPage.open(context, existing: t);
                  if (mounted) setState(() {});
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () async {
                  if (await confirm(
                    context,
                    'Delete this entry?',
                    message: 'It will be removed on both phones after the next sync.',
                  )) {
                    await repo.softDelete('transactions', t.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  CategoryIcon(category: cat, size: 56, fallback: isIncome ? Icons.payments_rounded : null),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (isIncome ? '+' : '') + Money.format(t.amountPaise, showPaise: true),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700, color: isIncome ? Colors.green.shade700 : null),
                        ),
                        Text(
                          t.title.isNotEmpty ? t.title : (t.merchant ?? cat?.name ?? ''),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _Row('Category', cat?.name ?? 'Uncategorised'),
              _Row('When', Dates.dateTime(Dates.fromMs(t.occurredAt))),
              _Row(isIncome ? 'Received by' : 'Paid by', payer?.name ?? data.memberName(t.paidBy)),
              if (!isIncome)
                _Row(
                  'Split',
                  t.isShared
                      ? '$otherName owes ${payer?.name ?? data.memberName(t.paidBy)} ${Money.format(t.partnerOwesPaise)}'
                      : 'Personal',
                ),
              if (t.merchant != null) _Row('Merchant / payee', t.merchant!),
              if (t.note.isNotEmpty) _Row('Note', t.note),
              _Row('Logged by', '$author · ${Dates.dateTime(Dates.fromMs(t.meta.createdAt))}'),
              _Row('Source', switch (t.source) {
                TxnSource.manual => 'Entered manually',
                TxnSource.sms => 'Bank SMS',
                TxnSource.share => 'Shared screenshot',
                TxnSource.quick => 'Quick add',
              }),
              if (t.meta.updatedAt != t.meta.createdAt)
                _Row('Last edited', Dates.dateTime(Dates.fromMs(t.meta.updatedAt))),
              const SizedBox(height: 16),
              FutureBuilder<List<Attachment>>(
                future: repo.attachmentsFor(t.id),
                builder: (ctx, s) {
                  final atts = s.data ?? const [];
                  if (atts.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Receipts', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [for (final a in atts) _AttachmentThumb(att: a)]),
                      Text(
                        'Photos arrive on the other phone with the next sync.',
                        style: TextStyle(color: scheme.outline, fontSize: 12),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({required this.att});
  final Attachment att;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AttachmentStore>();
    return FutureBuilder<Uint8List?>(
      future: store.read(att),
      builder: (ctx, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cloud_download_outlined),
                Text('Not synced yet', style: TextStyle(fontSize: 11)),
              ],
            ),
          );
        }
        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(8),
              child: InteractiveViewer(child: Image.memory(bytes)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, width: 110, height: 110, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}
