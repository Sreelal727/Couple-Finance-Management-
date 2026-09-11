import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/dates.dart';
import '../core/ids.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'attachment_store.dart';
import 'protocol.dart';
import 'sync_crypto.dart';

class SyncResult {
  final DeviceInfo peer;
  final int sent;
  final int received;
  final int attachmentsSent;
  final int attachmentsReceived;
  const SyncResult({
    required this.peer,
    required this.sent,
    required this.received,
    required this.attachmentsSent,
    required this.attachmentsReceived,
  });

  bool get nothingChanged =>
      sent == 0 && received == 0 && attachmentsSent == 0 && attachmentsReceived == 0;

  String get summary => nothingChanged
      ? 'Already up to date'
      : 'Sent $sent, received $received'
          '${attachmentsSent + attachmentsReceived > 0 ? ', ${attachmentsSent + attachmentsReceived} photos' : ''}';
}

/// Drives one full sync against a peer's [SyncServer].
class SyncClient {
  SyncClient({
    required this.repo,
    required this.attachments,
    required this.self,
    required this.crypto,
  });

  final Repository repo;
  final AttachmentStore attachments;
  final DeviceInfo self;
  final SyncCrypto crypto;

  /// Unauthenticated identity check. Works before pairing.
  static Future<DeviceInfo> hello(String host, int port, {Duration timeout = const Duration(seconds: 4)}) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.getUrl(Uri.http('$host:$port', '/hello'));
      final res = await req.close().timeout(timeout);
      final body = await _readAll(res);
      if (res.statusCode != 200) throw SyncException('hello failed (${res.statusCode})');
      final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
      if (j['app'] != SyncProtocol.app) throw const SyncException('not a Duo Finance phone');
      return DeviceInfo.fromJson(j);
    } finally {
      client.close(force: true);
    }
  }

  Future<SyncResult> sync(String host, int port, {String? expectedDeviceId}) async {
    final startedAt = Dates.nowMs();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    DeviceInfo? peer;
    try {
      peer = await hello(host, port);
      if (expectedDeviceId != null && peer.deviceId != expectedDeviceId) {
        throw SyncException('That phone is "${peer.name}", not the paired one');
      }

      // 1. What does the peer already have?
      final vec = await _post(client, host, port, '/vector', {'t': 'vector'});
      final theirVector = _vectorFrom(vec['vector']);

      // 2. Exchange rows.
      final outgoing = await repo.rowsSince(theirVector);
      final sent = outgoing.values.fold<int>(0, (n, l) => n + l.length);
      final myHave = await attachments.idsWithBytes();
      final ex = await _post(client, host, port, '/exchange', {
        't': 'exchange',
        'vector': await repo.vector(),
        'rows': outgoing,
        'have': myHave.toList(),
      });
      final incoming = _rowsFrom(ex['rows']);
      final received = await repo.applyIncoming(incoming);
      final theirVectorAfter = _vectorFrom(ex['vector']);
      final theirHave = ((ex['have'] as List?) ?? const []).cast<String>().toSet();
      final theyWant = ((ex['want'] as List?) ?? const []).cast<String>();

      // 3. Attachment bytes in both directions.
      var attIn = 0;
      for (final a in await attachments.missingBytes()) {
        if (!theirHave.contains(a.id)) continue;
        final bytes = await _get(client, host, port, '/attachment/${a.id}');
        if (bytes != null && await attachments.storeReceived(a, bytes)) attIn++;
      }
      var attOut = 0;
      for (final id in theyWant) {
        final a = await repo.attachmentById(id);
        if (a == null) continue;
        final bytes = await attachments.read(a);
        if (bytes == null) continue;
        await _postBytes(client, host, port, '/attachment/$id', await crypto.seal(bytes));
        attOut++;
      }

      await repo.savePeerVector(peer.deviceId, theirVectorAfter);
      final existing = await repo.peerByDevice(peer.deviceId);
      await repo.upsertPeer((existing ??
              Peer(
                deviceId: peer.deviceId,
                memberId: peer.memberId,
                name: peer.name,
                lastAddress: null,
                lastSeenAt: null,
                lastSyncAt: null,
                pairedAt: Dates.nowMs(),
              ))
          .copyWith(
        name: peer.name,
        lastAddress: '$host:$port',
        lastSeenAt: Dates.nowMs(),
        lastSyncAt: Dates.nowMs(),
      ));
      final result = SyncResult(
        peer: peer,
        sent: sent,
        received: received,
        attachmentsSent: attOut,
        attachmentsReceived: attIn,
      );
      await repo.addSyncLog(SyncLogEntry(
        id: newId(),
        peerName: peer.name,
        startedAt: startedAt,
        finishedAt: Dates.nowMs(),
        method: SyncMethod.lan,
        outcome: SyncOutcome.ok,
        sent: sent,
        received: received,
        attachmentsSent: attOut,
        attachmentsReceived: attIn,
        detail: 'We connected to $host',
      ));
      if (attIn > 0) repo.bump();
      return result;
    } catch (e) {
      await repo.addSyncLog(SyncLogEntry(
        id: newId(),
        peerName: peer?.name ?? host,
        startedAt: startedAt,
        finishedAt: Dates.nowMs(),
        method: SyncMethod.lan,
        outcome: SyncOutcome.failed,
        sent: 0,
        received: 0,
        attachmentsSent: 0,
        attachmentsReceived: 0,
        detail: e.toString(),
      ));
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  // ------------------------------------------------------------- helpers

  Future<Map<String, dynamic>> _post(
      HttpClient client, String host, int port, String path, Map<String, dynamic> body) async {
    final sealed = await crypto.sealJson({
      ...body,
      'ts': Dates.nowMs(),
      'from': self.toJson(),
    });
    final res = await _postBytes(client, host, port, path, sealed);
    try {
      return await crypto.openJson(res);
    } on FormatException {
      throw const SyncException('Could not decrypt reply. Are both phones paired with the same code?');
    }
  }

  Future<Uint8List> _postBytes(HttpClient client, String host, int port, String path, List<int> bytes) async {
    final req = await client.postUrl(Uri.http('$host:$port', path));
    req.headers.contentType = ContentType.binary;
    req.contentLength = bytes.length;
    req.add(bytes);
    final res = await req.close().timeout(const Duration(seconds: 60));
    final body = await _readAll(res);
    if (res.statusCode != 200) {
      throw SyncException('Peer refused $path (${res.statusCode}): ${utf8.decode(body, allowMalformed: true)}');
    }
    return body;
  }

  Future<Uint8List?> _get(HttpClient client, String host, int port, String path) async {
    final req = await client.getUrl(Uri.http('$host:$port', path));
    final res = await req.close().timeout(const Duration(seconds: 60));
    final body = await _readAll(res);
    if (res.statusCode != 200) return null;
    return crypto.open(body);
  }

  static Future<Uint8List> _readAll(HttpClientResponse res) async {
    final b = BytesBuilder(copy: false);
    await for (final chunk in res) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  static Map<String, int> _vectorFrom(Object? v) =>
      ((v as Map?) ?? const {}).map((k, val) => MapEntry(k as String, (val as num).toInt()));

  static RowBatch _rowsFrom(Object? v) {
    final m = (v as Map?) ?? const {};
    return m.map((table, rows) => MapEntry(
          table as String,
          (rows as List).map((r) => Map<String, Object?>.from(r as Map)).toList(),
        ));
  }
}
