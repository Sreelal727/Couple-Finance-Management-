import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PIN + optional fingerprint/face lock. The PIN is never stored; only a
/// salted hash is. Locks on launch and after the app has been in the
/// background for longer than [timeout].
class LockService extends ChangeNotifier {
  LockService(this.prefs);

  final SharedPreferences prefs;
  final _auth = LocalAuthentication();

  static const _hashKey = 'lock_pin_hash';
  static const _saltKey = 'lock_pin_salt';
  static const _bioKey = 'lock_biometric';
  static const _timeoutKey = 'lock_timeout_s';

  bool _locked = true;
  int? _backgroundedAt;

  bool get enabled => prefs.getString(_hashKey) != null;
  bool get biometricEnabled => prefs.getBool(_bioKey) ?? false;
  bool get locked => enabled && _locked;
  Duration get timeout => Duration(seconds: prefs.getInt(_timeoutKey) ?? 30);

  Future<bool> get biometricsAvailable async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<void> setPin(String pin) async {
    final salt = base64Encode(List.generate(16, (_) => Random.secure().nextInt(256)));
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(pin, salt));
    _locked = false;
    notifyListeners();
  }

  Future<void> disable() async {
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
    await prefs.remove(_bioKey);
    _locked = false;
    notifyListeners();
  }

  Future<void> setBiometric(bool v) async {
    await prefs.setBool(_bioKey, v);
    notifyListeners();
  }

  Future<void> setTimeout(Duration d) async {
    await prefs.setInt(_timeoutKey, d.inSeconds);
    notifyListeners();
  }

  bool verifyPin(String pin) {
    final salt = prefs.getString(_saltKey);
    final hash = prefs.getString(_hashKey);
    if (salt == null || hash == null) return true;
    final ok = _hash(pin, salt) == hash;
    if (ok) {
      _locked = false;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> tryBiometric() async {
    if (!biometricEnabled) return false;
    try {
      final ok = await _auth.authenticate(localizedReason: 'Unlock Duo Finance', biometricOnly: true);
      if (ok) {
        _locked = false;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  void onBackground() => _backgroundedAt = DateTime.now().millisecondsSinceEpoch;

  void onForeground() {
    if (!enabled || _locked) return;
    final at = _backgroundedAt;
    if (at == null) return;
    if (DateTime.now().millisecondsSinceEpoch - at > timeout.inMilliseconds) {
      _locked = true;
      notifyListeners();
    }
  }

  void lockNow() {
    if (!enabled) return;
    _locked = true;
    notifyListeners();
  }

  static String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin')).toString();
}
