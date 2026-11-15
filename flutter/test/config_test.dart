import 'dart:io';

import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runtime config asset parses', () {
    final cfg = BinfireConfig.parse(File(BinfireConfig.assetPath).readAsStringSync());
    expect(cfg.linkDomain, isNotEmpty);
    expect(cfg.scheme, isNotEmpty);
    expect(cfg.ownScheme, 'app.binfire.flutter');
    expect(cfg.hashbin.content, startsWith('https://'));
    expect(cfg.ble, isNotNull);
    expect(cfg.limits.maxTransferBytes, greaterThan(0));
  });

  test('partial limits fall back to defaults', () {
    final l = BinfireLimits.fromJson({'maxSiteFiles': 4});
    expect(l.maxSiteFiles, 4);
    expect(l.maxStateBytes, BinfireLimits.defaults.maxStateBytes);
  });
}
