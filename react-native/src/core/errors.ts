/** Every error code named in spec/. Ports must not invent codes for listed cases. */
export type ErrorCode =
  // cid.md
  | 'invalid-cid'
  | 'too-large'
  | 'not-found'
  | 'unavailable'
  | 'rate-limited'
  | 'http-error'
  | 'mismatch'
  // state.md (lz)
  | 'invalid'
  // links.md
  | 'unknown-app'
  | 'bad-link'
  | 'unknown-link'
  // transfer.md
  | 'bad-magic'
  | 'bad-bundle'
  | 'bad-version'
  | 'bad-frame'
  | 'inconsistent'
  // site-manifest.md
  | 'bad-manifest'
  | 'too-many-files'
  | 'bad-path'
  | 'duplicate-path'
  | 'size-mismatch'
  | 'missing-entry';

/** An expected failure with a spec error code. `message` equals `code` unless detail is given. */
export class BinfireError extends Error {
  readonly code: ErrorCode;

  constructor(code: ErrorCode, detail?: string) {
    super(detail ? `${code}: ${detail}` : code);
    this.name = 'BinfireError';
    this.code = code;
  }
}

/** True when `e` is a BinfireError (optionally with the given code). */
export function isBinfireError(e: unknown, code?: ErrorCode): e is BinfireError {
  return e instanceof BinfireError && (code === undefined || e.code === code);
}
