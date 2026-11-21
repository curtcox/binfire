package app.binfire.android

import app.binfire.core.BinfireError

// User-facing messages for core error codes, used by BinfireViewModel.

internal fun errorMessage(error: BinfireError): String = when (error) {
    BinfireError.UNKNOWN_APP -> "This link is for an app binfire doesn't know."
    BinfireError.BAD_LINK -> "This binfire link is malformed."
    BinfireError.UNKNOWN_LINK -> "This binfire link isn't one binfire understands."
    BinfireError.INVALID_CID -> "This link doesn't contain a valid document ID."
    BinfireError.TOO_LARGE -> "This text is too large to open."
    else -> "This link can't be opened (${error.code})."
}

/** Human messages for `loadCID` errors (`spec/cid.md`, "Opening a loaded document"). */
internal fun cidErrorMessage(error: BinfireError): String = when (error) {
    BinfireError.NETWORK -> "Couldn't reach HashBin. Check your connection and try again."
    BinfireError.NOT_FOUND -> "This document wasn't found. It may have expired."
    BinfireError.UNAVAILABLE -> "This document is unavailable for legal reasons."
    BinfireError.RATE_LIMITED -> "HashBin is busy (rate limited). Try again in a minute."
    BinfireError.TOO_LARGE -> "This document is too large to open."
    BinfireError.MISMATCH -> "This document failed verification: its content doesn't match its ID."
    BinfireError.INVALID_CID -> "This link doesn't contain a valid document ID."
    BinfireError.HTTP_ERROR -> "HashBin returned an error. Try again later."
    else -> "This document can't be opened (${error.code})."
}

/** Human messages for Native Save errors (`spec/hashbin.md`). */
internal fun saveErrorMessage(error: BinfireError): String = when (error) {
    BinfireError.INSUFFICIENT_BALANCE -> "Your HashBin balance is too low. Add funds on HashBin, then try again."
    BinfireError.COST_EXCEEDED -> "HashBin would charge more than binfire's limit, so nothing was saved."
    BinfireError.TOO_LARGE -> "This document is too large for HashBin."
    BinfireError.MISMATCH -> "HashBin returned an ID that doesn't match the document, so the link wasn't used."
    BinfireError.NETWORK -> "Couldn't reach HashBin. Check your connection and try again."
    BinfireError.FAILED -> "Signing in to HashBin didn't work. Try again."
    BinfireError.HTTP_ERROR -> "HashBin returned an error. Try again later."
    else -> "Saving to HashBin failed (${error.code})."
}

/** Messages for scan frames and received bundles (`spec/qr.md`). */
internal fun frameErrorMessage(error: BinfireError): String = when (error) {
    BinfireError.TOO_LARGE -> "This transfer is too large."
    BinfireError.MISMATCH -> "The received data failed verification. Scan again from the start."
    BinfireError.INCONSISTENT -> "The frames don't belong together. Scan again from the start."
    BinfireError.BAD_MAGIC, BinfireError.BAD_VERSION -> "This multi-frame code isn't one binfire can read (${error.code})."
    else -> "Couldn't read this frame (${error.code})."
}

internal fun bundleErrorMessage(error: BinfireError): String = when (error) {
    BinfireError.TOO_LARGE -> "What was received is too large to open."
    BinfireError.MISMATCH -> "What was received failed verification."
    else -> "What was received can't be opened (${error.code})."
}
