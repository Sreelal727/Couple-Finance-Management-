import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/dates.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../shared/widgets.dart';

class SyncLogPage extends StatelessWidget {
  const SyncLogPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncLogPage()));

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<Repository>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sync activity')),
      body: FutureBuilder<List<SyncLogEntry>>(
        future: repo.syncLog(limit: 100),
        builder: (ctx, snap) {
          final items = snap.data ?? const [];
          if (snap.hasData && items.isEmpty) {
            return const EmptyState(icon: Icons.sync_rounded, title: 'No syncs yet');
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final e = items[i];
              final ok = e.outcome == SyncOutcome.ok;
              final icon = switch (e.method) {
                SyncMethod.lan => Icons.wifi_rounded,
                SyncMethod.bundleOut => Icons.upload_file_rounded,
                SyncMethod.bundleIn => Icons.file_download_rounded,
              };
              final what = switch (e.method) {
                SyncMethod.lan => 'Wi-Fi sync with ${e.peerName}',
                SyncMethod.bundleOut => 'Sync file created for ${e.peerName}',
                SyncMethod.bundleIn => 'Sync file from ${e.peerName}',
              };
              final counts = <String>[
                if (e.sent > 0) '${e.sent} sent',
                if (e.received > 0) '${e.received} received',
                if (e.attachmentsSent + e.attachmentsReceived > 0)
                  '${e.attachmentsSent + e.attachmentsReceived} photos',
              ];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: ok ? scheme.primaryContainer : scheme.errorContainer,
                  child: Icon(
                    ok ? icon : Icons.error_outline_rounded,
                    color: ok ? scheme.onPrimaryContainer : scheme.onErrorContainer,
                  ),
                ),
                title: Text(what),
                subtitle: Text(
                  [
                    Dates.dateTime(Dates.fromMs(e.startedAt)),
                    if (ok && counts.isNotEmpty)
                      counts.join(', ')
                    else if (ok && e.method == SyncMethod.lan)
                      'Already up to date',
                    if (e.detail != null && (!ok || e.method != SyncMethod.lan)) e.detail!,
                  ].join('\n'),
                ),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}
