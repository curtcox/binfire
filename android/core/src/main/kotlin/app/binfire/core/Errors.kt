package app.binfire.core

/**
 * Every error code named in `spec/`. [code] is the exact kebab-case string the
 * specs and fixtures use. Ports must not invent codes for listed cases.
 */
enum class BinfireError(val code: String) {
    // cid.md
    INVALID_CID("invalid-cid"),
    TOO_LARGE("too-large"),
    NOT_FOUND("not-found"),
    UNAVAILABLE("unavailable"),
    RATE_LIMITED("rate-limited"),
    HTTP_ERROR("http-error"),
    MISMATCH("mismatch"),

    // state.md (lz)
    INVALID("invalid"),

    // links.md
    UNKNOWN_APP("unknown-app"),
    BAD_LINK("bad-link"),
    UNKNOWN_LINK("unknown-link"),

    // site-manifest.md
    BAD_MANIFEST("bad-manifest"),
    TOO_MANY_FILES("too-many-files"),
    BAD_PATH("bad-path"),
    DUPLICATE_PATH("duplicate-path"),
    SIZE_MISMATCH("size-mismatch"),
    MISSING_ENTRY("missing-entry"),

    // transfer.md
    BAD_MAGIC("bad-magic"),
    BAD_BUNDLE("bad-bundle"),
    BAD_VERSION("bad-version"),
    BAD_FRAME("bad-frame"),
    INCONSISTENT("inconsistent"),

    // hashbin.md
    FAILED("failed"),
    CANCELLED("cancelled"),
    INSUFFICIENT_BALANCE("insufficient-balance"),
    COST_EXCEEDED("cost-exceeded");

    override fun toString(): String = code

    companion object {
        /** The error with this [code], or `null`. */
        fun fromCode(code: String): BinfireError? = entries.firstOrNull { it.code == code }
    }
}

/** Thrown by core and transfer functions. [error] carries the spec's code. */
class BinfireException(val error: BinfireError, message: String? = null) :
    Exception(message?.let { "${error.code}: $it" } ?: error.code) {
    /** The kebab-case code, for example `"too-large"`. */
    val code: String get() = error.code
}

internal fun fail(error: BinfireError, message: String? = null): Nothing = throw BinfireException(error, message)
