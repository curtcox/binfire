package app.binfire.core

/** The kind of state an app URL carries (`spec/state.md`). [code] is the fixture string. */
enum class StateKind(val code: String) {
    PUBLISH("publish"),
    CID("cid"),
    V1("v1"),
    UNSUPPORTED_VERSION("unsupported-version"),
    SRC("src"),
    H1("h1"),
    FRAGMENT("fragment"),
    DOC("doc"),
    COMPRESSED("compressed"),
    EXAMPLE("example"),
    NONE("none");

    override fun toString(): String = code
}

/** The classification of an app URL. */
data class UrlStateInfo(
    val state: StateKind,
    /** `false` only when the query has `run=0`. */
    val run: Boolean,
    /** The `view` query value, or `null`. */
    val view: String?,
    /** The CID when [state] is [StateKind.CID]. */
    val cid: String?,
    /** UTF-8 length of the whole URL string. */
    val bytes: Long,
)

/** `classifyState(url)` from `spec/state.md`. */
object UrlState {
    private val VERSIONED = Regex("^v[0-9]+\\.")

    /**
     * Classifies [url], which should already match a registry app. Returns `null`
     * only when [url] is not an absolute URL.
     */
    fun classify(url: String): UrlStateInfo? = ParsedUrl.parse(url)?.let { classify(url, it) }

    internal fun classify(original: String, u: ParsedUrl): UrlStateInfo {
        val hash = u.rawFragment ?: ""
        val params = u.queryParams
        var cid: String? = null
        val state = when {
            QueryParams.parse(hash, stripLeadingQuestionMark = true).has("hashbin_publish") -> StateKind.PUBLISH
            Cid.isCid(hash) -> { cid = hash; StateKind.CID }
            hash.startsWith("v1.") -> StateKind.V1
            VERSIONED.containsMatchIn(hash) -> StateKind.UNSUPPORTED_VERSION
            hash.startsWith("src=") -> StateKind.SRC
            hash.startsWith("h1=") -> StateKind.H1
            hash.isNotEmpty() -> StateKind.FRAGMENT
            params.has("doc") -> StateKind.DOC
            params.has("compressed") -> StateKind.COMPRESSED
            params.has("example") -> StateKind.EXAMPLE
            else -> StateKind.NONE
        }
        return UrlStateInfo(state, params["run"] != "0", params["view"], cid, Utf8.length(original))
    }

    /**
     * [url] with every `run` parameter removed from the raw query (used by the
     * Run button). Other parameters keep their raw text and order; an emptied
     * query drops its `?`. Nothing else changes.
     */
    fun withoutRun(url: String): String {
        val hashAt = url.indexOf('#')
        val beforeHash = if (hashAt >= 0) url.substring(0, hashAt) else url
        val fragment = if (hashAt >= 0) url.substring(hashAt) else ""
        val qAt = beforeHash.indexOf('?')
        if (qAt < 0) return url
        val parts = beforeHash.substring(qAt + 1).split('&')
        val kept = parts.filter { part ->
            val name = part.substringBefore('=')
            part.isEmpty() || QueryParams.parse(name + "=").pairs.firstOrNull()?.first != "run"
        }
        if (kept.size == parts.size) return url
        val query = kept.filter { it.isNotEmpty() }.joinToString("&")
        return beforeHash.substring(0, qAt) + (if (query.isEmpty()) "" else "?$query") + fragment
    }

    /**
     * `withRunZero(url)` from `spec/links.md`: adds `run=0` to the raw query unless
     * the query already has a `run` key. Nothing else changes.
     */
    fun withRunZero(url: String): String {
        val hashAt = url.indexOf('#')
        val beforeHash = if (hashAt >= 0) url.substring(0, hashAt) else url
        val fragment = if (hashAt >= 0) url.substring(hashAt) else ""
        val qAt = beforeHash.indexOf('?')
        if (qAt < 0) return "$beforeHash?run=0$fragment"
        if (QueryParams.parse(beforeHash.substring(qAt + 1)).has("run")) return url
        return "$beforeHash&run=0$fragment"
    }
}
