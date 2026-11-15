import 'dart:convert';
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

  test('hashbin.maxCostCents comes from the shipped config', () {
    final shipped = jsonDecode(File('../config/binfire.config.json').readAsStringSync()) as Map<String, Object?>;
    final want = (shipped['hashbin'] as Map<String, Object?>)['maxCostCents'];
    expect(want, 25);
    final cfg = BinfireConfig.parse(File(BinfireConfig.assetPath).readAsStringSync());
    expect(cfg.hashbin.maxCostCents, want);
    expect(cfg.withHashbinOverrides(api: 'http://localhost:8787', clientId: 'app_mock').hashbin.maxCostCents, want);
  });

  test('hashbin.maxCostCents is parsed, defaulted and validated', () {
    Map<String, Object?> json(Object? cap) => {
          'linkDomain': 'binfire.app',
          'scheme': 'binfire',
          'hashbin': {'content': 'https://256t.us', 'maxCostCents': ?cap},
        };
    expect(BinfireConfig.fromJson(json(40)).hashbin.maxCostCents, 40);
    expect(BinfireConfig.fromJson(json(null)).hashbin.maxCostCents, HashbinConfig.defaultMaxCostCents);
    expect(() => BinfireConfig.fromJson(json(0)), throwsFormatException);
    expect(() => BinfireConfig.fromJson(json(-5)), throwsFormatException);
    expect(() => BinfireConfig.fromJson(json('25')), throwsFormatException);
    expect(() => BinfireConfig.fromJson(json(2.5)), throwsFormatException);
  });

  test('partial limits fall back to defaults', () {
    final l = BinfireLimits.fromJson({'maxSiteFiles': 4});
    expect(l.maxSiteFiles, 4);
    expect(l.maxStateBytes, BinfireLimits.defaults.maxStateBytes);
  });
}
