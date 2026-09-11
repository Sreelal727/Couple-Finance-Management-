import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'protocol.dart';

/// Another phone running the app that was heard on the local network.
class PeerSighting {
  final String deviceId;
  final String name;
  final InternetAddress address;
  final int port;
  final DateTime seenAt;
  const PeerSighting({
    required this.deviceId,
    required this.name,
    required this.address,
    required this.port,
    required this.seenAt,
  });

  String get hostPort => '${address.address}:$port';
}

/// Zero-config LAN discovery using plain UDP broadcast. Every couple of
/// seconds each phone shouts "I'm here" on port 47471; any phone that hears a
/// beacon learns the other's IP and sync port. No mDNS, no plugins, works on
/// home Wi-Fi and on a phone hotspot alike.
class LanDiscovery {
  LanDiscovery({required this.self, required this.httpPort});

  final DeviceInfo self;
  final int httpPort;

  RawDatagramSocket? _socket;
  Timer? _beacon;
  final _controller = StreamController<PeerSighting>.broadcast();
  bool get running => _socket != null;

  Stream<PeerSighting> get sightings => _controller.stream;

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      SyncProtocol.discoveryPort,
      reuseAddress: true,
      reusePort: true,
    );
    socket.broadcastEnabled = true;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null) return;
      _handle(dg);
    });
    _socket = socket;
    _beacon = Timer.periodic(const Duration(seconds: 2), (_) => announce());
    await announce();
  }

  void _handle(Datagram dg) {
    try {
      final j = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (j['app'] != SyncProtocol.app) return;
      final id = j['d'] as String?;
      if (id == null || id == self.deviceId) return;
      _controller.add(
        PeerSighting(
          deviceId: id,
          name: (j['n'] as String?) ?? 'Unknown',
          address: dg.address,
          port: (j['p'] as num?)?.toInt() ?? SyncProtocol.httpPort,
          seenAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // Not one of ours.
    }
  }

  Future<void> announce() async {
    final s = _socket;
    if (s == null) return;
    final payload = utf8.encode(
      jsonEncode({
        'app': SyncProtocol.app,
        'v': SyncProtocol.version,
        'd': self.deviceId,
        'n': self.name,
        'p': httpPort,
      }),
    );
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    for (final addr in await localAddresses()) {
      // Directed broadcast for a /24, which covers almost every home router and
      // every Android hotspot. The global broadcast above covers the rest.
      final parts = addr.address.split('.');
      if (parts.length == 4) targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
    }
    for (final t in targets) {
      try {
        s.send(payload, t, SyncProtocol.discoveryPort);
      } catch (_) {
        // Some interfaces refuse broadcast; ignore.
      }
    }
  }

  /// IPv4 addresses of this phone (Wi-Fi, hotspot), excluding loopback.
  static Future<List<InternetAddress>> localAddresses() async {
    final out = <InternetAddress>[];
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final i in ifaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback && !a.isLinkLocal) out.add(a);
        }
      }
    } catch (_) {}
    return out;
  }

  Future<void> stop() async {
    _beacon?.cancel();
    _beacon = null;
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
