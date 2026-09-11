import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Everything that leaves the phone during sync is gzip-compressed and then
/// sealed with AES-256-GCM. The key is derived from the pairing secret that
/// was exchanged via QR code, so only the two paired phones can read or forge
/// sync traffic, even on a shared Wi-Fi network.
class SyncCrypto {
  SyncCrypto._(this._key);

  final SecretKey _key;
  static final _aes = AesGcm.with256bits();

  static Uint8List newSecret() {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => rng.nextInt(256)));
  }

  static Future<SyncCrypto> fromSecret(List<int> secret) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: utf8.encode('duo-finance'),
      info: utf8.encode('sync-v1'),
    );
    return SyncCrypto._(key);
  }

  Future<Uint8List> sealJson(Object json) => seal(utf8.encode(jsonEncode(json)));

  Future<Uint8List> seal(List<int> plain) async {
    final compressed = gzip.encode(plain);
    final box = await _aes.encrypt(compressed, secretKey: _key);
    return Uint8List.fromList(box.concatenation());
  }

  Future<Uint8List> open(List<int> sealed) async {
    if (sealed.length < 28) throw const FormatException('sealed data too short');
    final box = SecretBox.fromConcatenation(sealed, nonceLength: 12, macLength: 16);
    final compressed = await _aes.decrypt(box, secretKey: _key);
    return Uint8List.fromList(gzip.decode(compressed));
  }

  Future<Map<String, dynamic>> openJson(List<int> sealed) async {
    final bytes = await open(sealed);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }
}
