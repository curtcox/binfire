/// Bluetooth LE handshake helpers (spec/ble-gatt.md).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// The 4-digit confirmation code both sides show:
/// `uint32_be(SHA-256("binfire-ble-v1" || senderNonce || receiverNonce)[0..4]) mod 10000`,
/// with leading zeros. Nonces are the raw 16 bytes.
String bleConfirmationCode(List<int> senderNonce, List<int> receiverNonce) {
  final digest = sha256.convert([...ascii.encode('binfire-ble-v1'), ...senderNonce, ...receiverNonce]).bytes;
  final n = (digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3];
  return (n % 10000).toString().padLeft(4, '0');
}
