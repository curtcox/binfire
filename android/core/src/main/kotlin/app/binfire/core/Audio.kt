package app.binfire.core

/** Data-over-sound payload rules (`spec/audio.md`). */
object Audio {
    /** ggwave's payload limit, in UTF-8 bytes. */
    const val MAX_PAYLOAD_BYTES = 140

    /**
     * True when [text] fits in [MAX_PAYLOAD_BYTES] and routes to `load-cid`,
     * `open-site`, or `open-app` via an `https://D/a/` link.
     */
    fun audioPayloadOK(text: String, links: Links): Boolean {
        if (Utf8.length(text) > MAX_PAYLOAD_BYTES) return false
        return when (links.route(text)) {
            is Route.LoadCid, is Route.OpenSite -> true
            is Route.OpenApp -> links.isHttpsAppLink(text)
            else -> false
        }
    }
}
