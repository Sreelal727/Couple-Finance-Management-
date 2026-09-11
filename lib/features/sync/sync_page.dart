import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/dates.dart';
import '../../data/repository.dart';
import '../../sync/protocol.dart';
import '../../sync/sync_service.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';
import 'pairing_pages.dart';
import 'sync_log_page.dart';

class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncPage()));

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  @override
  void initState() {
    super.initState();
    final sync = context.read<SyncService>();
    sync.startNetwork().then((_) => sync.announce());
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final data = context.watch<AppData>();
    final repo = context.read<Repository>();
    final scheme = Theme.of(context).colorScheme;
    final peer = data.peers.firstOrNull;
    final sighted = peer == null ? null : sync.sightings[peer.deviceId];
    final unknownNearby = sync.sightings.values
        .where((s) => data.peers.every((p) => p.deviceId != s.deviceId))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Activity',
            onPressed: () => SyncLogPage.open(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: sync.isPaired ? scheme.primaryContainer : scheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(sync.isPaired ? Icons.link_rounded : Icons.link_off_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sync.isPaired ? 'Paired with ${peer?.name ?? 'partner'}' : 'Not paired yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (sync.isPaired) ...[
                    Text(
                      sighted != null
                          ? '${peer!.name}\'s phone is on this network (${sighted.address.address})'
                          : peer?.lastSyncAt != null
                          ? 'Last synced ${Dates.relative(Dates.fromMs(peer!.lastSyncAt!))}'
                          : 'Never synced',
                    ),
                    if (sync.statusText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(sync.statusText!, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    if (sync.lastError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(sync.lastError!, style: TextStyle(color: scheme.error)),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          icon: sync.phase == SyncPhase.syncing
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.sync_rounded),
                          label: const Text('Sync now'),
                          onPressed: sync.phase == SyncPhase.syncing
                              ? null
                              : () async {
                                  try {
                                    final r = await sync.syncNow();
                                    if (context.mounted && r != null) showSnack(context, r.summary);
                                  } catch (e) {
                                    if (context.mounted) showSnack(context, e.toString());
                                  }
                                },
                        ),
                        const SizedBox(width: 8),
                        TextButton(onPressed: () => _manualAddress(context), child: const Text('Enter IP')),
                      ],
                    ),
                  ] else
                    const Text(
                      'Pair once with a QR code. After that the phones find each other automatically whenever both are on the same Wi-Fi or hotspot.',
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Auto-sync when nearby'),
            subtitle: const Text('Sync as soon as the other phone is seen on the network'),
            value: sync.autoSync,
            onChanged: sync.setAutoSync,
          ),
          const SectionHeader('Pairing'),
          ListTile(
            leading: const Icon(Icons.qr_code_2_rounded),
            title: Text(sync.isPaired ? 'Show pairing code again' : 'Show pairing code'),
            subtitle: const Text('Your partner scans this on their phone'),
            onTap: () => PairShowPage.open(context),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner_rounded),
            title: const Text('Scan partner\'s code'),
            onTap: () => PairScanPage.open(context),
          ),
          if (unknownNearby.isNotEmpty)
            for (final s in unknownNearby)
              ListTile(
                leading: const Icon(Icons.phone_android_rounded),
                title: Text('${s.name} is nearby'),
                subtitle: Text('${s.address.address} · not paired. Scan their code to pair.'),
              ),
          const SectionHeader('Without shared Wi-Fi'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Option 1 · Hotspot', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Turn on the hotspot on one phone and connect the other to it. That is a network too, so the normal sync works. No data is used.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  const Text('Option 2 · Sync file', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    'Create an encrypted file with everything new and send it by Bluetooth, Quick Share or WhatsApp. The other phone opens it in Duo Finance.',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: const Text('Create sync file'),
                        onPressed: sync.isPaired ? () => _shareBundle(context, peer?.deviceId) : null,
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.file_open_rounded, size: 18),
                        label: const Text('Open sync file'),
                        onPressed: sync.isPaired ? () => _importBundle(context) : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SectionHeader('This phone'),
          FutureBuilder<List<String>>(
            future: sync.myAddresses(),
            builder: (ctx, snap) => ListTile(
              leading: const Icon(Icons.wifi_rounded),
              title: Text((snap.data ?? const []).isEmpty ? 'Not on a network' : (snap.data!).join(', ')),
              subtitle: Text('Sync port ${sync.port} · ${sync.networkRunning ? 'listening' : 'not running'}'),
              trailing: IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => sync.restartNetwork()),
            ),
          ),
          if (sync.isPaired)
            ListTile(
              leading: Icon(Icons.link_off_rounded, color: scheme.error),
              title: Text('Unpair', style: TextStyle(color: scheme.error)),
              subtitle: const Text('Keeps all data on this phone; stops syncing'),
              onTap: () async {
                if (await confirm(
                  context,
                  'Unpair phones?',
                  message: 'Data already synced stays. You can pair again any time.',
                  okLabel: 'Unpair',
                )) {
                  await sync.unpair();
                  repo.bump();
                }
              },
            ),
        ],
      ),
    );
  }

  Future<void> _manualAddress(BuildContext context) async {
    final sync = context.read<SyncService>();
    final v = await askText(
      context,
      "Partner's IP address",
      hint: '192.168.1.23',
      okLabel: 'Sync',
      keyboard: TextInputType.url,
    );
    if (v == null || v.trim().isEmpty) return;
    final parts = v.trim().split(':');
    try {
      final r = await sync.syncWith(parts[0], parts.length > 1 ? int.parse(parts[1]) : SyncProtocol.httpPort);
      if (context.mounted) showSnack(context, r.summary);
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _shareBundle(BuildContext context, String? peerDeviceId) async {
    final sync = context.read<SyncService>();
    try {
      final bytes = await sync.createBundle(peerDeviceId: peerDeviceId);
      final dir = await getTemporaryDirectory();
      final name = 'duo-sync-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.${SyncProtocol.bundleExtension}';
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/octet-stream')],
          subject: 'Duo Finance sync file',
        ),
      );
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _importBundle(BuildContext context) async {
    final sync = context.read<SyncService>();
    try {
      final picked = await FilePicker.pickFiles(type: FileType.any);
      if (picked.isEmpty) return;
      final bytes = await picked.first.readAsBytes();
      final r = await sync.importBundle(bytes);
      if (context.mounted) {
        showSnack(context, 'Imported ${r.applied} changes and ${r.attachments} photos from ${r.from.name}');
      }
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }
}

/// Small helper so screens can copy text.
Future<void> copyToClipboard(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showSnack(context, 'Copied');
}
