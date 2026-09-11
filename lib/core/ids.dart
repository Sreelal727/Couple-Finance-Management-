import 'dart:math';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// A short, human-typeable code (used for the manual pairing fallback).
String shortCode(int length) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rng = Random.secure();
  return List.generate(length, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
}
