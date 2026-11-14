package app.binfire.core

import java.security.MessageDigest

/** What Native Save uploads for a state URL (`spec/hashbin.md`, "What is saved for a state"). */
sealed class SaveBytes {
    /** The kind string used in fixtures. */
    abstract val kind: String

    /** binfire cannot extract the document. [error] is the lz code when a `v1` payload failed to decode. */
    data class None(val error: BinfireError? = null) : SaveBytes() {
        override val kind get() = "none"
    }

    /** A `v1` payload that is a JSON string: upload [text] as UTF-8 with [CONTENT_TYPE]. */
    data class Text(val text: String) : SaveBytes() {
        override val kind get() = "text"
        val bytes: ByteArray get() = Utf8.encode(text)

        companion object {
            const val CONTENT_TYPE = "text/plain; charset=utf-8"
        }
    }

    /** Any other `v1` payload: upload the payload [text] as UTF-8 with [CONTENT_TYPE]. */
    data class Json(val text: String) : SaveBytes() {
        override val kind get() = "json"
        val bytes: ByteArray get() = Utf8.encode(text)

        companion object {
            const val CONTENT_TYPE = "application/json"
        }
    }

    /** The state is already a CID: nothing is uploaded. */
    data class Cid(val cid: String) : SaveBytes() {
        override val kind get() = "cid"
    }
}

/** Pure helpers for HashBin Native Save (`spec/hashbin.md`). */
object HashBin {
    /** PKCE S256 challenge: `base64url(SHA-256(ascii(verifier)))`. */
    fun pkceChallenge(verifier: String): String =
        Base64Url.encode(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))

    /** What to save for app state [url]. `v1` payloads are decoded with [limitBytes] (normally `maxStateBytes`). */
    fun saveBytes(url: String, limitBytes: Long): SaveBytes {
        val u = ParsedUrl.parse(url) ?: return SaveBytes.None()
        val info = UrlState.classify(url, u)
        return when (info.state) {
            StateKind.CID -> SaveBytes.Cid(info.cid!!)
            StateKind.V1 -> {
                val payload = (u.rawFragment ?: "").removePrefix("v1.")
                val text = try {
                    Lz.decompress(payload, limitBytes)
                } catch (e: BinfireException) {
                    return SaveBytes.None(e.error)
                }
                val value = try {
                    Json.parse(text)
                } catch (_: JsonException) {
                    null
                }
                if (value is String) SaveBytes.Text(value) else SaveBytes.Json(text)
            }
            else -> SaveBytes.None()
        }
    }
}
