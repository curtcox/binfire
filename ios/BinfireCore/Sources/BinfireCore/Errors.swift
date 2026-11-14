/// An error carrying one of the short kebab-case codes listed in `spec/`.
///
/// `code` (the raw value) is the exact string the specs and fixtures use.
public enum BinfireError: String, Error, Sendable, CaseIterable, CustomStringConvertible {
    // cid.md
    case invalidCID = "invalid-cid"
    case tooLarge = "too-large"
    case notFound = "not-found"
    case unavailable = "unavailable"
    case rateLimited = "rate-limited"
    case httpError = "http-error"
    case mismatch = "mismatch"
    // state.md (lz)
    case invalid = "invalid"
    // links.md
    case unknownApp = "unknown-app"
    case badLink = "bad-link"
    case unknownLink = "unknown-link"
    // transfer.md
    case badMagic = "bad-magic"
    case badBundle = "bad-bundle"
    case badVersion = "bad-version"
    case badFrame = "bad-frame"
    case inconsistent = "inconsistent"
    // site-manifest.md
    case badManifest = "bad-manifest"
    case tooManyFiles = "too-many-files"
    case badPath = "bad-path"
    case duplicatePath = "duplicate-path"
    case sizeMismatch = "size-mismatch"
    case missingEntry = "missing-entry"
    // Loading bundled data files (not covered by a spec case).
    case badConfig = "bad-config"
    case badRegistry = "bad-registry"

    /// The kebab-case code, e.g. `"invalid-cid"`.
    public var code: String { rawValue }
    public var description: String { rawValue }
}
