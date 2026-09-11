/// Wire-level constants shared by the server, client, discovery and bundles.
class SyncProtocol {
  SyncProtocol._();

  static const app = 'duo-finance';
  static const version = 1;

  /// TCP port for the on-device HTTP sync server.
  static const httpPort = 47470;

  /// UDP port for LAN discovery beacons.
  static const discoveryPort = 47471;

  /// Magic header at the start of an offline sync bundle file.
  static const bundleMagic = 'DUOSYNC1';
  static const bundleExtension = 'duosync';

  /// Reject sealed messages whose timestamp is further than this from now.
  static const maxSkew = Duration(minutes: 10);
}

/// Who a sync message is from.
class DeviceInfo {
  final String deviceId;
  final String memberId;
  final String name;
  const DeviceInfo({required this.deviceId, required this.memberId, required this.name});

  Map<String, dynamic> toJson() => {'deviceId': deviceId, 'memberId': memberId, 'name': name};

  static DeviceInfo fromJson(Map<String, dynamic> j) => DeviceInfo(
        deviceId: j['deviceId'] as String,
        memberId: j['memberId'] as String,
        name: j['name'] as String,
      );
}

class SyncException implements Exception {
  final String message;
  const SyncException(this.message);
  @override
  String toString() => message;
}
