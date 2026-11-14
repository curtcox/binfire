/// Error type shared by every binfire core module.
library;

/// A failure with one of the kebab-case error codes listed in `spec/`.
///
/// Fixtures name these codes, so ports must not invent new ones for listed
/// cases. Compare [code] against the constants in [ErrorCodes].
class BinfireException implements Exception {
  /// Creates an exception with a spec error [code] and an optional [detail]
  /// for logs (never shown as the code).
  const BinfireException(this.code, [this.detail]);

  /// The spec error code, for example `too-large`.
  final String code;

  /// Extra human-readable context, or `null`.
  final String? detail;

  @override
  String toString() =>
      detail == null ? 'BinfireException($code)' : 'BinfireException($code: $detail)';
}

/// The error codes used across the specs.
abstract final class ErrorCodes {
  // cid.md
  static const invalidCid = 'invalid-cid';
  static const tooLarge = 'too-large';
  static const notFound = 'not-found';
  static const unavailable = 'unavailable';
  static const rateLimited = 'rate-limited';
  static const httpError = 'http-error';
  static const mismatch = 'mismatch';

  // state.md (lz)
  static const invalid = 'invalid';

  // links.md
  static const unknownApp = 'unknown-app';
  static const badLink = 'bad-link';
  static const unknownLink = 'unknown-link';

  // transfer.md
  static const badMagic = 'bad-magic';
  static const badBundle = 'bad-bundle';
  static const badVersion = 'bad-version';
  static const badFrame = 'bad-frame';
  static const inconsistent = 'inconsistent';

  // site-manifest.md
  static const badManifest = 'bad-manifest';
  static const tooManyFiles = 'too-many-files';
  static const badPath = 'bad-path';
  static const duplicatePath = 'duplicate-path';
  static const sizeMismatch = 'size-mismatch';
  static const missingEntry = 'missing-entry';
}
