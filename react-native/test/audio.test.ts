import { audioPayloadOK } from '../src/core/audio';
import { loadFixture } from './fixtures';

const fx = loadFixture('audio.json');

describe('audio.json', () => {
  test.each(fx.payloads as { text: string; ok: boolean }[])('$text → $ok', ({ text, ok }) => {
    expect(audioPayloadOK(text)).toBe(ok);
  });
  // `waveforms` is empty until M7.
});
