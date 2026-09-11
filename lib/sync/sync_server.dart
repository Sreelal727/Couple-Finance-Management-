import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'attachment_store.dart';
import 'protocol.dart';
import 'sync_crypto.dart';

typedef PeerSeenCallback = Future<void> Function(DeviceInfo peer, String address);

/// The HTTP server every phone runs while the app is open. The partner's phone
/// connects to it directly over Wi-Fi; nothing goes through the internet.
class SyncServer {
  SyncServer({
    required this.repo,
    required this.attachments,
    required this.self,
    required this.crypto,
    required this.onPeerSeen,
  });

  final Repository repo;
  final AttachmentStore attachments;
  final DeviceInfo self;
  final SyncCrypto? Function() crypto; // null until paired
  final PeerSeenCallback onPeerSeen;

  HttpServer? _server;
  int get port => _server?.port ?? SyncProtocol.httpPort;
  bool get running => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final router = Router()
      ..get('/hello', _hello)
      ..post('/vector', _vector)
      ..post('/exchange', _exchange)
      ..get('/attachment/<id>', _getAttachment)
      ..post('/attachment/<id>', _putAttachment);
    try {
      _server = await shelf_io.serve(router.call, InternetAddress.anyIPv4, SyncProtocol.httpPort, shared: true);
    } on SocketException {
      _server = await shelf_io.serve(router.call, InternetAddress.anyIPv4, 0, shared: true);
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ------------------------------------------------------------ handlers

  Response _hello(Request req) => Response.ok(
    jsonEncode({'app': SyncProtocol.app, 'v': SyncProtocol.version, ...self.toJson(), 'port': port}),
    headers: {'content-type': 'application/json'},
  );

  Future<Response> _vector(Request req) async {
    final c = crypto();
    if (c == null) return Response.forbidden('not paired');
    try {
      final msg = await c.openJson(await _body(req));
      _checkEnvelope(msg);
      final from = DeviceInfo.fromJson(msg['from'] as Map<String, dynamic>);
      await onPeerSeen(from, _remote(req));
      return await _sealed(c, {
        't': 'vector',
        'ts': Dates.nowMs(),
        'from': self.toJson(),
        'vector': await repo.vector(),
      });
    } catch (e) {
      return Response.forbidden('bad request: $e');
    }
  }

  Future<Response> _exchange(Request req) async {
    final c = crypto();
    if (c == null) return Response.forbidden('not paired');
    final startedAt = Dates.nowMs();
    DeviceInfo? from;
    try {
      final msg = await c.openJson(await _body(req));
      _checkEnvelope(msg);
      from = DeviceInfo.fromJson(msg['from'] as Map<String, dynamic>);
      await onPeerSeen(from, _remote(req));

      final theirVector = _vectorFrom(msg['vector']);
      final incoming = _rowsFrom(msg['rows']);
      final theirHave = ((msg['have'] as List?) ?? const []).cast<String>().toSet();

      final received = await repo.applyIncoming(incoming);
      final outgoing = await repo.rowsSince(theirVector);
      final sent = outgoing.values.fold<int>(0, (n, l) => n + l.length);
      final myHave = await attachments.idsWithBytes();
      final myRows = (await repo.allAttachments()).map((a) => a.id).toSet();
      final want = theirHave.where((id) => !myHave.contains(id) && myRows.contains(id)).toList();
      final myVector = await repo.vector();
      // After this reply the peer will know everything we know.
      await repo.savePeerVector(from.deviceId, myVector);
      final peer = await repo.peerByDevice(from.deviceId);
      if (peer != null) await repo.upsertPeer(peer.copyWith(lastSyncAt: Dates.nowMs()));
      await repo.addSyncLog(
        SyncLogEntry(
          id: newId(),
          peerName: from.name,
          startedAt: startedAt,
          finishedAt: Dates.nowMs(),
          method: SyncMethod.lan,
          outcome: SyncOutcome.ok,
          sent: sent,
          received: received,
          attachmentsSent: 0,
          attachmentsReceived: 0,
          detail: 'They connected to us',
        ),
      );
      return await _sealed(c, {
        't': 'exchange',
        'ts': Dates.nowMs(),
        'from': self.toJson(),
        'rows': outgoing,
        'vector': myVector,
        'have': myHave.toList(),
        'want': want,
        'applied': received,
      });
    } catch (e) {
      await repo.addSyncLog(
        SyncLogEntry(
          id: newId(),
          peerName: from?.name ?? 'Unknown',
          startedAt: startedAt,
          finishedAt: Dates.nowMs(),
          method: SyncMethod.lan,
          outcome: SyncOutcome.failed,
          sent: 0,
          received: 0,
          attachmentsSent: 0,
          attachmentsReceived: 0,
          detail: 'Incoming sync failed: $e',
        ),
      );
      return Response.forbidden('bad request: $e');
    }
  }

  Future<Response> _getAttachment(Request req, String id) async {
    final c = crypto();
    if (c == null) return Response.forbidden('not paired');
    final att = await repo.attachmentById(id);
    if (att == null) return Response.notFound('no such attachment');
    final bytes = await attachments.read(att);
    if (bytes == null) return Response.notFound('bytes not on this phone');
    return Response.ok(await c.seal(bytes), headers: {'content-type': 'application/octet-stream'});
  }

  Future<Response> _putAttachment(Request req, String id) async {
    final c = crypto();
    if (c == null) return Response.forbidden('not paired');
    final att = await repo.attachmentById(id);
    if (att == null) return Response.notFound('no such attachment');
    try {
      final bytes = await c.open(await _body(req));
      final ok = await attachments.storeReceived(att, bytes);
      return ok ? Response.ok('stored') : Response(422, body: 'hash mismatch');
    } catch (e) {
      return Response.forbidden('bad request: $e');
    }
  }

  // ------------------------------------------------------------- helpers

  static Future<Uint8List> _body(Request req) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in req.read()) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static Future<Response> _sealed(SyncCrypto c, Map<String, dynamic> json) async =>
      Response.ok(await c.sealJson(json), headers: {'content-type': 'application/octet-stream'});

  static void _checkEnvelope(Map<String, dynamic> msg) {
    final ts = (msg['ts'] as num?)?.toInt();
    if (ts == null) throw const SyncException('missing timestamp');
    final skew = (Dates.nowMs() - ts).abs();
    if (skew > SyncProtocol.maxSkew.inMilliseconds) {
      throw const SyncException('clock skew too large, check both phones\' time');
    }
  }

  static String _remote(Request req) {
    final info = req.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    return info?.remoteAddress.address ?? '?';
  }

  static Map<String, int> _vectorFrom(Object? v) =>
      ((v as Map?) ?? const {}).map((k, val) => MapEntry(k as String, (val as num).toInt()));

  static RowBatch _rowsFrom(Object? v) {
    final m = (v as Map?) ?? const {};
    return m.map(
      (table, rows) =>
          MapEntry(table as String, (rows as List).map((r) => Map<String, Object?>.from(r as Map)).toList()),
    );
  }
}
