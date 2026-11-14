import { confirmationCode } from '../src/core/ble';
import { hex, loadFixture } from './fixtures';

const fx = loadFixture('ble.json');

describe('ble.json', () => {
  test.each(fx.codes as { senderNonceHex: string; receiverNonceHex: string; code: string }[])(
    'code $code',
    ({ senderNonceHex, receiverNonceHex, code }) => {
      expect(confirmationCode(hex(senderNonceHex), hex(receiverNonceHex))).toBe(code);
    },
  );
});
