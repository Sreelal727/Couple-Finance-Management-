import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dates.dart';
import '../core/ids.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'attachment_store.dart';
import 'discovery.dart';
import 'protocol.dart';
import 'sync_bundle.dart';
import 'sync_client.dart';
import 'sync_crypto.dart';
import 'sync_server.dart';

enum SyncPhase { idle, syncing }

/// Owns the server, discovery, pairing secret and auto-sync policy. The UI
/// listens to this for live status.
class SyncService extends ChangeNotifier {
  SyncService({required this.repo, required this.attachments, required this.prefs});

  final Repository repo;
  final AttachmentStore attachments;
  final SharedPreferences prefs;

  static const _secretKey = 'pair_secret';
  static const _autoSyncKey = 'auto_sync';

  Uint8List? _secret;
  SyncCrypto? _crypto;
  SyncServer? _server;
  LanDiscovery? _discovery;
  StreamSubscription<PeerSighting>? _sub;
  DeviceInfo? _self;

  /// Phones heard on the network recently, keyed by device id.
  final Map<String, PeerSighting> sightings = {};
  final Map<String, int> _lastAutoAttempt = {};

  SyncPhase phase = SyncPhase.idle;
  String? statusText;
  String? lastError;
  SyncResult? lastResult;

  bool get isPaired => _secret != null;
  bool get networkRunning => _server?.running ?? false;
  bool get autoSync => prefs.getBool(_autoSyncKey) ?? true;
  DeviceInfo? get self => _self;
  int get port => _server?.port ?? SyncProtocol.httpPort;
  SyncCrypto? get crypto => _crypto;

  Future<void> setAutoSync(bool v) async {
    await prefs.setBool(_autoSyncKey, v);
    notifyListeners();
  }

  // --------------------------------------------------------------- setup

  Future<void> init() async {
    final raw = prefs.getString(_secretKey);
    if (raw != null) {
      _secret = base64Decode(raw);
      _crypto = await SyncCrypto.fromSecret(_secret!);
    }
    await refreshSelf();
  }

  Future<void> refreshSelf() async {
    if (!repo.isSetUp) return;
    final me = await repo.me();
    _self = DeviceInfo(deviceId: repo.identity.deviceId, memberId: me.id, name: me.name);
  }

  Future<void> startNetwork() async {
    if (!repo.isSetUp) return;
    await refreshSelf();
    final self = _self!;
    if (_server == null) {
      _server = SyncServer(
        repo: repo,
        attachments: attachments,
        self: self,
        crypto: () => _crypto,
        onPeerSeen: _registerPeer,
      );
      try {
        await _server!.start();
      } catch (e) {
        lastError = 'Could not start sync server: $e';
        _server = null;
      }
    }
    if (_discovery == null && _server != null) {
      _discovery = LanDiscovery(self: self, httpPort: _server!.port);
      try {
        await _discovery!.start();
        _sub = _discovery!.sightings.listen(_onSighting);
      } catch (e) {
        lastError = 'Could not start discovery: $e';
        _discovery = null;
      }
    }
    notifyListeners();
  }

  Future<void> stopNetwork() async {
    await _sub?.cancel();
    _sub = null;
    await _discovery?.stop();
    _discovery = null;
    await _server?.stop();
    _server = null;
    sightings.clear();
    notifyListeners();
  }

  /// Restart discovery + server (e.g. after the user renamed themselves).
  Future<void> restartNetwork() async {
    await stopNetwork();
    await startNetwork();
  }

  Future<void> announce() async => _discovery?.announce();

  Future<List<String>> myAddresses() async =>
      (await LanDiscovery.localAddresses()).map((a) => a.address).toList();

  // ------------------------------------------------------------- sightings

  Future<void> _onSighting(PeerSighting s) async {
    sightings[s.deviceId] = s;
    final peer = await repo.peerByDevice(s.deviceId);
    if (peer != null) {
      await repo.upsertPeer(peer.copyWith(
        name: s.name,
        lastAddress: s.hostPort,
        lastSeenAt: Dates.nowMs(),
      ));
    }
    notifyListeners();
    if (peer == null || !isPaired || !autoSync || phase == SyncPhase.syncing) return;
    final last = _lastAutoAttempt[s.deviceId] ?? 0;
    if (Dates.nowMs() - last < 45 * 1000) return;
    _lastAutoAttempt[s.deviceId] = Dates.nowMs();
    try {
      await syncWith(s.address.address, s.port, expectedDeviceId: s.deviceId);
    } catch (_) {
      // Surfaced via lastError / sync log.
    }
  }

  Future<void> _registerPeer(DeviceInfo info, String address) async {
    final existing = await repo.peerByDevice(info.deviceId);
    await repo.upsertPeer((existing ??
            Peer(
              deviceId: info.deviceId,
              memberId: info.memberId,
              name: info.name,
              lastAddress: null,
              lastSeenAt: null,
              lastSyncAt: null,
              pairedAt: Dates.nowMs(),
            ))
        .copyWith(name: info.name, lastAddress: address, lastSeenAt: Dates.nowMs()));
  }

  // ----------------------------------------------------------------- sync

  Future<SyncResult> syncWith(String host, int port, {String? expectedDeviceId}) async {
    final c = _crypto;
    if (c == null) throw const SyncException('Pair the phones first');
    if (phase == SyncPhase.syncing) throw const SyncException('A sync is already running');
    phase = SyncPhase.syncing;
    statusText = 'Syncing with $host…';
    lastError = null;
    notifyListeners();
    try {
      final client = SyncClient(repo: repo, attachments: attachments, self: _self!, crypto: c);
      final r = await client.sync(host, port, expectedDeviceId: expectedDeviceId);
      lastResult = r;
      statusText = r.summary;
      return r;
    } catch (e) {
      lastError = e.toString();
      statusText = null;
      rethrow;
    } finally {
      phase = SyncPhase.idle;
      notifyListeners();
    }
  }

  /// Sync with every paired peer we can currently see or last knew an
  /// address for. Returns the first successful result.
  Future<SyncResult?> syncNow() async {
    final peers = await repo.peers();
    if (peers.isEmpty) throw const SyncException('No paired phone yet');
    await announce();
    // Give beacons a moment if we haven't heard anyone.
    if (sightings.isEmpty) await Future<void>.delayed(const Duration(seconds: 2));
    Object? lastErr;
    for (final p in peers) {
      final s = sightings[p.deviceId];
      final candidates = <String>[
        if (s != null) s.hostPort,
        if (p.lastAddress != null) p.lastAddress!,
      ];
      for (final hp in candidates.toSet()) {
        final parts = hp.split(':');
        try {
          return await syncWith(parts[0], int.tryParse(parts.length > 1 ? parts[1] : '') ?? SyncProtocol.httpPort,
              expectedDeviceId: p.deviceId);
        } catch (e) {
          lastErr = e;
        }
      }
    }
    if (lastErr != null) throw SyncException(_friendly(lastErr));
    return null;
  }

  static String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Connection refused') || s.contains('timed out')) {
      return "Can't reach the other phone. Make sure Duo Finance is open on it and both are on the same Wi-Fi or hotspot.";
    }
    return s;
  }

  // -------------------------------------------------------------- pairing

  /// JSON shown in the QR code. Generates the shared secret if needed.
  Future<String> pairingPayload() async {
    if (_secret == null) {
      _secret = SyncCrypto.newSecret();
      _crypto = await SyncCrypto.fromSecret(_secret!);
      await prefs.setString(_secretKey, base64Encode(_secret!));
      notifyListeners();
    }
    await refreshSelf();
    return jsonEncode({
      'app': SyncProtocol.app,
      'v': SyncProtocol.version,
      's': base64Encode(_secret!),
      'd': _self!.deviceId,
      'm': _self!.memberId,
      'n': _self!.name,
      'a': await myAddresses(),
      'p': port,
    });
  }

  /// Called on the phone that scanned the QR code. Stores the secret,
  /// records the peer and tries an immediate sync.
  Future<SyncResult?> completePairing(String payload) async {
    Map<String, dynamic> j;
    try {
      j = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      throw const SyncException('That is not a Duo Finance pairing code');
    }
    if (j['app'] != SyncProtocol.app) throw const SyncException('That is not a Duo Finance pairing code');
    final secret = base64Decode(j['s'] as String);
    final deviceId = j['d'] as String;
    if (deviceId == repo.identity.deviceId) throw const SyncException('You scanned your own code');
    _secret = Uint8List.fromList(secret);
    _crypto = await SyncCrypto.fromSecret(_secret!);
    await prefs.setString(_secretKey, base64Encode(_secret!));
    final info = DeviceInfo(deviceId: deviceId, memberId: j['m'] as String, name: j['n'] as String);
    await _registerPeer(info, '');
    notifyListeners();

    final port = (j['p'] as num?)?.toInt() ?? SyncProtocol.httpPort;
    final addresses = ((j['a'] as List?) ?? const []).cast<String>();
    final sighted = sightings[deviceId];
    final candidates = [if (sighted != null) sighted.address.address, ...addresses];
    for (final host in candidates) {
      try {
        return await syncWith(host, port, expectedDeviceId: deviceId);
      } catch (_) {
        // try next address
      }
    }
    return null; // paired, but not reachable right now
  }

  Future<void> unpair() async {
    _secret = null;
    _crypto = null;
    await prefs.remove(_secretKey);
    for (final p in await repo.peers()) {
      await repo.removePeer(p.deviceId);
    }
    notifyListeners();
  }

  // -------------------------------------------------------------- bundles

  Future<Uint8List> createBundle({String? peerDeviceId}) async {
    final c = _crypto;
    if (c == null) throw const SyncException('Pair the phones first');
    final b = SyncBundle(repo: repo, attachments: attachments, self: _self!, crypto: c);
    final bytes = await b.create(peerDeviceId: peerDeviceId);
    await repo.addSyncLog(SyncLogEntry(
      id: newId(),
      peerName: peerDeviceId == null ? 'Anyone' : ((await repo.peerByDevice(peerDeviceId))?.name ?? 'Partner'),
      startedAt: Dates.nowMs(),
      finishedAt: Dates.nowMs(),
      method: SyncMethod.bundleOut,
      outcome: SyncOutcome.ok,
      sent: 0,
      received: 0,
      attachmentsSent: 0,
      attachmentsReceived: 0,
      detail: 'Created sync file (${(bytes.length / 1024).toStringAsFixed(0)} KB)',
    ));
    return bytes;
  }

  Future<BundleImportResult> importBundle(Uint8List bytes) async {
    final c = _crypto;
    if (c == null) throw const SyncException('Pair the phones first');
    final b = SyncBundle(repo: repo, attachments: attachments, self: _self!, crypto: c);
    final r = await b.import(bytes);
    lastResult = null;
    statusText = 'Imported ${r.applied} changes from ${r.from.name}';
    notifyListeners();
    return r;
  }

  @override
  void dispose() {
    stopNetwork();
    super.dispose();
  }
}
