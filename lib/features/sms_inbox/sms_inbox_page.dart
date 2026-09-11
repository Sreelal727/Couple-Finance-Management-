import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../sms/notifications.dart';
import '../../sms/sms_service.dart';
import '../shared/widgets.dart';
import '../transactions/add_txn_page.dart';

/// Opens the add form prefilled from a detected SMS. Used by the inbox list
/// and by the notification tap.
Future<void> addFromSms(BuildContext context, SmsItem item) async {
  await AddTxnPage.open(
    context,
    prefill: TxnPrefill(
      type: item.direction == SmsDirection.debit ? TxnType.expense : TxnType.income,
      amountPaise: item.amountPaise,
      merchant: item.merchant,
      occurredAt: item.receivedAt,
      source: TxnSource.sms,
      smsRef: item.bodyHash,
      smsItemId: item.id,
    ),
  );
}

class SmsInboxPage extends StatefulWidget {
  const SmsInboxPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SmsInboxPage()));

  @override
  State<SmsInboxPage> createState() => _SmsInboxPageState();
}

class _SmsInboxPageState extends State<SmsInboxPage> {
  bool _showHandled = false;
  bool _scanning = false;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final sms = context.watch<SmsService>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detected transactions'),
        actions: [
          IconButton(
            tooltip: 'Scan inbox again',
            icon: _scanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh_rounded),
            onPressed: _scanning || !sms.enabled
                ? null
                : () async {
                    setState(() => _scanning = true);
                    final n = await sms.scanInbox(days: 30);
                    if (!context.mounted) return;
                    setState(() => _scanning = false);
                    showSnack(context, n == 0 ? 'No new bank SMS found' : 'Found $n new transactions');
                  },
          ),
          PopupMenuButton<String>(
            onSelected: (v) => setState(() => _showHandled = v == 'all'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pending', child: Text('Pending only')),
              PopupMenuItem(value: 'all', child: Text('Show handled too')),
            ],
          ),
        ],
      ),
      body: !sms.enabled
          ? EmptyState(
              icon: Icons.sms_rounded,
              title: 'SMS capture is off',
              subtitle: 'When on, bank and UPI debit alerts become one-tap expense entries. SMS are read on this phone only and never leave it.',
              action: FilledButton(
                onPressed: () async {
                  final ok = await sms.enable();
                  if (!ok && context.mounted) showSnack(context, 'SMS permission was not granted');
                },
                child: const Text('Turn on SMS capture'),
              ),
            )
          : FutureBuilder<List<SmsItem>>(
              future: repo.smsItems(status: _showHandled ? null : SmsStatus.pending),
              builder: (ctx, snap) {
                final items = snap.data ?? const [];
                if (snap.hasData && items.isEmpty) {
                  return const EmptyState(
                    icon: Icons.mark_email_read_rounded,
                    title: 'All caught up',
                    subtitle: 'New bank SMS will show up here and as a notification.',
                  );
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final it = items[i];
                    final debit = it.direction == SmsDirection.debit;
                    final handled = it.status != SmsStatus.pending;
                    return Card(
                      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  debit ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                  size: 18,
                                  color: debit ? scheme.error : Colors.green.shade700,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  Money.format(it.amountPaise),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    it.merchant != null
                                        ? (debit ? 'to ${it.merchant}' : 'from ${it.merchant}')
                                        : it.sender,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (handled)
                                  Chip(
                                    label: Text(it.status == SmsStatus.added ? 'Added' : 'Dismissed'),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${Dates.dateTime(Dates.fromMs(it.receivedAt))} · ${it.sender}${it.accountTail != null ? ' · a/c …${it.accountTail}' : ''}',
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              it.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.outline, fontSize: 12),
                            ),
                            if (!handled)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () async {
                                      await repo.updateSms(it.copyWith(status: SmsStatus.dismissed));
                                      await Notifications.cancelFor(it.id);
                                    },
                                    child: const Text('Not an expense'),
                                  ),
                                  FilledButton.tonalIcon(
                                    icon: const Icon(Icons.add_rounded, size: 18),
                                    label: Text(debit ? 'Add expense' : 'Add income'),
                                    onPressed: () => addFromSms(context, it),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
