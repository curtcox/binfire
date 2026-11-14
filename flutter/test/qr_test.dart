import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final f = fixture('qr.json');
  final t = f['thresholds'] as Map<String, Object?>;

  test('thresholds', () {
    expect(qrOkMaxBytes, t['okMax']);
    expect(qrDenseMaxBytes, t['denseMax']);
  });

  group('plans', () {
    for (final c in objects(f['plans'])) {
      test('${c['bytes']}', () => expect(qrPlanForBytes(c['bytes'] as int).code, c['plan']));
    }
  });
}
