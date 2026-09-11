import 'dart:convert';
import 'dart:typed_data';

import '../core/dates.dart';
import '../core/ids.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'attachment_store.dart';
import 'protocol.dart';
import 'sync_crypto.dart';

class BundleImportResult {
  final DeviceInfo from;
  final int applied;
  final int attachments;
  const BundleImportResult({required this.from, required this.applied, required this.attachments});
}

/// Offline sync: everything the partner's phone hasn't seen, packed into one
/// encrypted file that can travel by Bluetooth, Nearby Share, WhatsApp or a
/// cable. Same merge rules as LAN sync, so mixing the two is safe.
class SyncBundle {
  SyncBundle({required this.repo, required this.attachments, required this.self, required this.crypto});

  final Repository repo;
  final AttachmentStore attachments;
  final DeviceInfo self;
  final SyncCrypto crypto;

  /// [peerDeviceId] null = full export (everything).
  Future<Uint8List> create({String? peerDeviceId}) async {
    final since = peerDeviceId == null ? <String, int>{} : await repo.peerVector(peerDeviceId);
    final rows = await repo.rowsSince(since);
    final atts = <Map<String, dynamic>>[];
    for (final row in rows['attachments'] ?? const <Map<String, Object?>>[]) {
      final a = Attachment.fromMap(row);
      if (a.meta.deleted) continue;
      final bytes = await attachments.read(a);
      if (bytes != null) atts.add({'id': a.id, 'data': base64Encode(bytes)});
    }
    final sealed = await crypto.sealJson({
      't': 'bundle',
      'ts': Dates.nowMs(),
      'from': self.toJson(),
      'for': peerDeviceId,
      'vector': await repo.vector(),
      'rows': rows,
      'attachments': atts,
    });
    final magic = utf8.encode(SyncProtocol.bundleMagic);
    return Uint8List.fromList([...magic, ...sealed]);
  }

  Future<BundleImportResult> import(Uint8List bytes) async {
    final magic = utf8.encode(SyncProtocol.bundleMagic);
    if (bytes.length < magic.length || !_startsWith(bytes, magic)) {
      throw const SyncException('Not a Duo Finance sync file');
    }
    final startedAt = Dates.nowMs();
    Map<String, dynamic> j;
    try {
      j = await crypto.openJson(bytes.sublist(magic.length));
    } catch (_) {
      throw const SyncException('Could not open the file. Was it made by your paired phone?');
    }
    final from = DeviceInfo.fromJson(j['from'] as Map<String, dynamic>);
    final rows = ((j['rows'] as Map?) ?? const {}).map(
      (t, l) => MapEntry(t as String, (l as List).map((r) => Map<String, Object?>.from(r as Map)).toList()),
    );
    final applied = await repo.applyIncoming(rows);
    var stored = 0;
    for (final a in ((j['attachments'] as List?) ?? const [])) {
      final m = a as Map;
      final att = await repo.attachmentById(m['id'] as String);
      if (att == null) continue;
      if (await attachments.hasBytes(att)) continue;
      if (await attachments.storeReceived(att, base64Decode(m['data'] as String))) stored++;
    }
    final theirVector = ((j['vector'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt()));
    // They know their own state; merge with what we already believed.
    final known = await repo.peerVector(from.deviceId);
    for (final e in theirVector.entries) {
      if ((known[e.key] ?? 0) < e.value) known[e.key] = e.value;
    }
    await repo.savePeerVector(from.deviceId, known);
    final existing = await repo.peerByDevice(from.deviceId);
    await repo.upsertPeer(
      (existing ??
              Peer(
                deviceId: from.deviceId,
                memberId: from.memberId,
                name: from.name,
                lastAddress: null,
                lastSeenAt: null,
                lastSyncAt: null,
                pairedAt: Dates.nowMs(),
              ))
          .copyWith(name: from.name, lastSyncAt: Dates.nowMs()),
    );
    await repo.addSyncLog(
      SyncLogEntry(
        id: newId(),
        peerName: from.name,
        startedAt: startedAt,
        finishedAt: Dates.nowMs(),
        method: SyncMethod.bundleIn,
        outcome: SyncOutcome.ok,
        sent: 0,
        received: applied,
        attachmentsSent: 0,
        attachmentsReceived: stored,
        detail: 'Imported sync file',
      ),
    );
    if (stored > 0) repo.bump();
    return BundleImportResult(from: from, applied: applied, attachments: stored);
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }
}
