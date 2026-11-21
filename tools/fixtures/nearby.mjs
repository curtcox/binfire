// ble.json and audio.json: BLE pairing codes and which texts fit an audio frame.
// Called by tools/gen-fixtures.mjs.
import * as R from '../lib/ref.mjs';
import { D, write, cidA, cidB, enc } from './context.mjs';

export default function genNearby() {
  const nonces = [['00'.repeat(16), '00'.repeat(16)], ['000102030405060708090a0b0c0d0e0f', 'f0e0d0c0b0a090807060504030201000'], ['ffffffffffffffffffffffffffffffff', '0123456789abcdef0123456789abcdef']];
  write('ble.json', { codes: nonces.map(([s, r]) => ({ senderNonceHex: s, receiverNonceHex: r, code: R.bleCode(s, r) })) });

  const audioPayloads = [
    [cidB, true], [cidA, true], [`https://${D}/c#${cidB}`, true], [`https://${D}/s#${cidB}`, true],
    [`https://${D}/a/python#${cidA}`, true], [`https://${D}/a/python#v1.` + 'A'.repeat(200), false],
    [`https://${D}/open#u=${enc('https://python.hashbin.page/#x')}`, false], ['https://example.com/', false],
    ['https://python.hashbin.page/#v1.abc', false], ['hello', false],
  ].map(([t, ok]) => ({ text: t, ok }));
  write('audio.json', { payloads: audioPayloads, waveforms: [] });
}
