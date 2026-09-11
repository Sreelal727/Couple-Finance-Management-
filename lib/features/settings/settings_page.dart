import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/repository.dart';
import '../../sms/sms_service.dart';
import '../../sync/sync_service.dart';
import '../budgets/budgets_page.dart';
import '../categories/categories_page.dart';
import '../lock/lock_screen.dart';
import '../lock/lock_service.dart';
import '../quick_adds/quick_adds_page.dart';
import '../shared/app_data.dart';
import '../shared/widgets.dart';
import '../sms_inbox/sms_inbox_page.dart';
import '../sync/sync_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final repo = context.read<Repository>();
    final sync = context.watch<SyncService>();
    final sms = context.watch<SmsService>();
    final lock = context.watch<LockService>();
    final scheme = Theme.of(context).colorScheme;
    final me = data.me;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ListTile(
            leading: MemberAvatar(member: me, radius: 20),
            title: Text(me?.name ?? ''),
            subtitle: Text(
              data.partner != null
                  ? 'Partner: ${data.partner!.name}'
                  : (data.peers.isNotEmpty
                        ? 'Partner: ${data.peers.first.name} (sync to see their entries)'
                        : 'No partner paired yet'),
            ),
            trailing: const Icon(Icons.edit_rounded),
            onTap: () => _editProfile(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync_rounded),
            title: const Text('Sync & pairing'),
            subtitle: Text(sync.isPaired ? 'Paired' : 'Not paired'),
            onTap: () => SyncPage.open(context),
          ),
          ListTile(
            leading: const Icon(Icons.sms_rounded),
            title: const Text('SMS capture'),
            subtitle: Text(sms.enabled ? 'On · bank alerts become one-tap entries' : 'Off'),
            trailing: Switch(
              value: sms.enabled,
              onChanged: (v) async {
                if (v) {
                  final ok = await sms.enable();
                  if (!ok && context.mounted) showSnack(context, 'SMS permission was not granted');
                } else {
                  await sms.disable();
                }
              },
            ),
            onTap: () => SmsInboxPage.open(context),
          ),
          ListTile(
            leading: const Icon(Icons.lock_rounded),
            title: const Text('App lock'),
            subtitle: Text(
              lock.enabled
                  ? 'PIN${lock.biometricEnabled ? ' + fingerprint' : ''} · locks after ${lock.timeout.inSeconds}s'
                  : 'Off',
            ),
            onTap: () => _lockSettings(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.category_rounded),
            title: const Text('Categories'),
            onTap: () => CategoriesPage.open(context),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_rounded),
            title: const Text('Monthly budgets'),
            onTap: () => BudgetsPage.open(context),
          ),
          ListTile(
            leading: const Icon(Icons.bolt_rounded),
            title: const Text('Quick adds'),
            onTap: () => QuickAddsPage.open(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.backup_rounded),
            title: const Text('Backup to file'),
            subtitle: const Text('Encrypted with your pairing key. Save it to Drive or email it to yourself.'),
            onTap: () => _backup(context),
          ),
          ListTile(
            leading: const Icon(Icons.restore_rounded),
            title: const Text('Restore from file'),
            subtitle: const Text('Merges a backup or sync file into this phone'),
            onTap: () => _restore(context),
          ),
          FutureBuilder<Map<String, int>>(
            future: repo.tableCounts(),
            builder: (ctx, snap) {
              final c = snap.data ?? const {};
              return ListTile(
                leading: const Icon(Icons.storage_rounded),
                title: const Text('Data on this phone'),
                subtitle: Text(
                  '${c['transactions'] ?? 0} entries · ${c['attachments'] ?? 0} photos · ${c['categories'] ?? 0} categories',
                ),
              );
            },
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Duo Finance keeps everything on your two phones. Nothing is uploaded anywhere. Device id ${repo.identity.deviceId.substring(0, 8)}.',
              style: TextStyle(color: scheme.outline, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editProfile(BuildContext context) async {
    final repo = context.read<Repository>();
    final sync = context.read<SyncService>();
    final me = await repo.me();
    if (!context.mounted) return;
    final name = TextEditingController(text: me.name);
    var color = me.colorHex;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Your profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 16),
              ColorPickerRow(selected: color, onSelected: (c) => setState(() => color = c)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    await repo.save(me.copyWith(name: name.text.trim(), colorHex: color));
    await sync.restartNetwork();
  }

  Future<void> _lockSettings(BuildContext context) async {
    final lock = context.read<LockService>();
    final bio = await lock.biometricsAvailable;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final l = ctx.watch<LockService>();
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text('Require PIN to open'),
                  value: l.enabled,
                  onChanged: (v) async {
                    if (v) {
                      final pin = await askNewPin(ctx);
                      if (pin != null) await l.setPin(pin);
                    } else {
                      await l.disable();
                    }
                  },
                ),
                if (l.enabled) ...[
                  SwitchListTile(
                    title: const Text('Unlock with fingerprint / face'),
                    subtitle: bio ? null : const Text('Not available on this phone'),
                    value: l.biometricEnabled,
                    onChanged: bio ? l.setBiometric : null,
                  ),
                  ListTile(
                    title: const Text('Lock after leaving the app'),
                    trailing: DropdownButton<int>(
                      value: l.timeout.inSeconds,
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Immediately')),
                        DropdownMenuItem(value: 30, child: Text('30 seconds')),
                        DropdownMenuItem(value: 120, child: Text('2 minutes')),
                        DropdownMenuItem(value: 600, child: Text('10 minutes')),
                      ],
                      onChanged: (v) => l.setTimeout(Duration(seconds: v ?? 30)),
                    ),
                  ),
                  ListTile(
                    title: const Text('Change PIN'),
                    onTap: () async {
                      final pin = await askNewPin(ctx);
                      if (pin != null) await l.setPin(pin);
                    },
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _backup(BuildContext context) async {
    final sync = context.read<SyncService>();
    final repo = context.read<Repository>();
    try {
      if (!sync.isPaired) {
        // No pairing key yet: create one so the backup can be encrypted.
        await sync.pairingPayload();
      }
      final bytes = await sync.createBundle();
      final dir = await getTemporaryDirectory();
      final file = File(
        p.join(dir.path, 'duo-finance-backup-${DateFormat('yyyyMMdd').format(DateTime.now())}.duosync'),
      );
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/octet-stream')],
          subject: 'Duo Finance backup',
        ),
      );
      repo.bump();
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }

  Future<void> _restore(BuildContext context) async {
    final sync = context.read<SyncService>();
    try {
      final picked = await FilePicker.pickFiles(type: FileType.any);
      if (picked.isEmpty) return;
      final bytes = await picked.first.readAsBytes();
      final r = await sync.importBundle(bytes);
      if (context.mounted) showSnack(context, 'Restored ${r.applied} records and ${r.attachments} photos');
    } catch (e) {
      if (context.mounted) showSnack(context, e.toString());
    }
  }
}
