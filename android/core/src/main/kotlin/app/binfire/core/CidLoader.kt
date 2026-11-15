package app.binfire.core

import java.io.IOException

/** Fetches the content of a hashed CID: `GET {hashbin.content}/{cid}` (`spec/cid.md`, "Loading"). */
fun interface CidFetch {
    /** Throws [IOException] on network failure. */
    fun fetch(cid: String): HttpResponse

    companion object {
        /** A fetch over [http] from content base [contentBase] (for example `https://256t.us`). */
        fun http(contentBase: String, http: Http): CidFetch = CidFetch { cid ->
            http.request("GET", contentBase.trimEnd('/') + "/" + cid, emptyMap(), null)
        }
    }
}

/** `loadCID(cid, limit, fetch)` (`spec/cid.md`). */
object CidLoader {
    /**
     * Returns the verified bytes of [cid]. Throws [BinfireException] with
     * `invalid-cid`, `too-large`, `not-found`, `unavailable`, `rate-limited`,
     * `http-error`, `mismatch` or `network`. Inline CIDs and CIDs whose declared
     * length exceeds [limit] never call [fetch].
     */
    fun loadCid(cid: String, limit: Long, fetch: CidFetch): ByteArray {
        if (!Cid.isCid(cid)) fail(BinfireError.INVALID_CID)
        val length = Cid.cidLength(cid)
        if (length > limit) fail(BinfireError.TOO_LARGE)
        if (Cid.isInline(cid)) return Cid.inlineContent(cid) ?: fail(BinfireError.INVALID_CID)
        val bytes = try {
            fetch.fetch(cid).use { response ->
                when (response.status) {
                    in 200..299 -> response.readCapped(length) ?: fail(BinfireError.TOO_LARGE)
                    404 -> fail(BinfireError.NOT_FOUND)
                    451 -> fail(BinfireError.UNAVAILABLE)
                    429 -> fail(BinfireError.RATE_LIMITED)
                    else -> fail(BinfireError.HTTP_ERROR, "HTTP ${response.status}")
                }
            }
        } catch (e: IOException) {
            fail(BinfireError.NETWORK, e.message)
        }
        if (!Cid.verify(cid, bytes)) fail(BinfireError.MISMATCH)
        return bytes
    }
}
