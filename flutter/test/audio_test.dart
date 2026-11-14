import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final f = fixture('audio.json');
  final links = Links(BinfireConfig.parse(_configText()), sharedRegistry());

  group('payloads', () {
    for (final c in objects(f['payloads'])) {
      final text = c['text'] as String;
      test(text.length > 60 ? '${text.substring(0, 60)}…' : text, () {
        expect(audioPayloadOK(text, links), c['ok']);
      });
    }
  });
  // `waveforms` arrive in M7.
}

String _configText() {
  final cfg = fixture('links.json')['config'] as Map<String, Object?>;
  return '{"linkDomain":"${cfg['linkDomain']}","scheme":"${cfg['scheme']}","hashbin":{"content":"${cfg['content']}"}}';
}
