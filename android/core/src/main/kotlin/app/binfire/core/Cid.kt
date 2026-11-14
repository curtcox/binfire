package app.binfire.core

import java.security.MessageDigest

/** 256t content identifiers (`spec/cid.md`). */
object Cid {
    /** Largest length a CID prefix can hold (`2^48 - 1`). */
    const val MAX_LENGTH: Long = (1L shl 48) - 1

    /** Largest content length stored inline in the CID. */
    const val INLINE_MAX = 64

    /** Computes the CID of [bytes]. */
    fun computeCid(bytes: ByteArray): String {
        val n = bytes.size.toLong()
        val prefix = ByteArray(6) { i -> (n ushr (8 * (5 - i))).toByte() }
        val suffix = if (bytes.size <= INLINE_MAX) bytes else sha512(bytes)
        return Base64Url.encode(prefix) + Base64Url.encode(suffix)
    }

    /**
     * The content length declared by [cid]'s 8-character prefix, or `-1` if the
     * prefix is not canonical base64url. Does not check the rest of the CID.
     */
    fun cidLength(cid: String): Long {
        val prefix = Base64Url.decode(cid.take(8)) ?: return -1
        if (prefix.size != 6) return -1
        var n = 0L
        for (b in prefix) n = (n shl 8) or (b.toLong() and 0xff)
        return n
    }

    /** True when [cid] declares at most [INLINE_MAX] bytes, so the content is in the CID itself. */
    fun isInline(cid: String): Boolean = cidLength(cid) in 0..INLINE_MAX

    /** Validates [cid] by the rules in `spec/cid.md`. A leading `#` makes it invalid. */
    fun isCid(cid: String): Boolean {
        if (cid.length < 8 || cid.length > 94) return false
        for (c in cid) if (!(c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c == '_' || c == '-')) return false
        val n = cidLength(cid)
        if (n < 0) return false
        val suffix = Base64Url.decode(cid.substring(8)) ?: return false
        return if (n <= INLINE_MAX) {
            cid.length.toLong() == 8 + (4 * n + 2) / 3 && suffix.size.toLong() == n
        } else {
            cid.length == 94 && suffix.size == 64
        }
    }

    /** The content of an inline CID, or `null` when [cid] is invalid or hashed. */
    fun inlineContent(cid: String): ByteArray? =
        if (isCid(cid) && isInline(cid)) Base64Url.decode(cid.substring(8)) else null

    /** True when `computeCid(bytes) == cid`. Callers bound [bytes] by `cidLength(cid)` first. */
    fun verify(cid: String, bytes: ByteArray): Boolean = computeCid(bytes) == cid

    private fun sha512(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-512").digest(bytes)
}
