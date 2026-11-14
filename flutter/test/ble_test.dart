import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  for (final c in objects(fixture('ble.json')['codes'])) {
    test('${c['senderNonceHex']} / ${c['receiverNonceHex']}', () {
      expect(
        bleConfirmationCode(hex(c['senderNonceHex'] as String), hex(c['receiverNonceHex'] as String)),
        c['code'],
      );
    });
  }
}
