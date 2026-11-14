// Test helpers: read shared/fixtures/*.json straight from the repo (never copied).
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const FIXTURES = join(__dirname, '..', '..', 'shared', 'fixtures');

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function loadFixture(name: string): any {
  return JSON.parse(readFileSync(join(FIXTURES, name), 'utf8'));
}

/** A fixture byte value: `{ text }` (UTF-8) or `{ b64 }` (base64url). Always a plain Uint8Array. */
export function fixtureBytes(v: { text?: string; b64?: string }): Uint8Array {
  if (v.text !== undefined) return new Uint8Array(Buffer.from(v.text, 'utf8'));
  return b64(v.b64!);
}

export function b64(text: string): Uint8Array {
  return new Uint8Array(Buffer.from(text, 'base64url'));
}

export function hex(text: string): Uint8Array {
  return new Uint8Array(Buffer.from(text, 'hex'));
}

/** The error code thrown by `fn`, or null if it returned. */
export function errorCode(fn: () => unknown): string | null {
  try {
    fn();
    return null;
  } catch (e) {
    const code = (e as { code?: unknown }).code;
    if (typeof code !== 'string') throw e;
    return code;
  }
}

/** Wraps each case as `{ i, c }` so test names can use `$i`. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function indexed(cases: any[]): { i: number; c: any }[] {
  return cases.map((c, i) => ({ i, c }));
}
