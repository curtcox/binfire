// Bluetooth LE handshake helpers (spec/ble-gatt.md).
import { sha256 } from '@noble/hashes/sha2.js';
import { asciiBytes, concatBytes } from './bytes';

/** Nonces are 16 raw bytes. */
export const BLE_NONCE_BYTES = 16;

const CODE_LABEL = asciiBytes('binfire-ble-v1');

/**
 * The 4-digit confirmation code both sides show:
 * `uint32_be(SHA-256("binfire-ble-v1" || senderNonce || receiverNonce)[0..4]) mod 10000`.
 * Throws RangeError when a nonce is not 16 bytes.
 */
export function confirmationCode(senderNonce: Uint8Array, receiverNonce: Uint8Array): string {
  if (senderNonce.length !== BLE_NONCE_BYTES || receiverNonce.length !== BLE_NONCE_BYTES)
    throw new RangeError('BLE nonces must be 16 bytes');
  const d = sha256(concatBytes(CODE_LABEL, senderNonce, receiverNonce));
  const n = ((d[0] << 24) >>> 0) + (d[1] << 16) + (d[2] << 8) + d[3];
  return String(n % 10000).padStart(4, '0');
}
