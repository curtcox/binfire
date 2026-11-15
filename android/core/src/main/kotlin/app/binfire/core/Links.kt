package app.binfire.core

/** The result of [Links.route] (`spec/links.md`). */
sealed class Route {
    /** The `action` string used in fixtures and logs. */
    abstract val action: String

    /** Load [url] in app [app]'s WebView. [state], [run] and [view] come from `classifyState(url)`. */
    data class OpenApp(val app: String, val url: String, val state: StateKind, val run: Boolean, val view: String?) : Route() {
        override val action get() = "open-app"
    }

    /**
     * Fetch and verify [cid], then choose an app by document type unless [app] (a slug hint) is set.
     * [run] is `false` for received content (`routeReceived`): the app then opens
     * `withRunZero(canonicalOrigin + "#" + cid)`. `null` (not received) opens it as is.
     */
    data class LoadCid(val cid: String, val app: String?, val run: Boolean? = null) : Route() {
        override val action get() = "load-cid"
    }

    /** Load a packaged site by its manifest [cid]. */
    data class OpenSite(val cid: String) : Route() {
        override val action get() = "open-site"
    }

    /** Not something binfire opens. Offer "Open in browser" (for http(s)) and "Copy"; never auto-navigate. */
    data class ShowText(val text: String) : Route() {
        override val action get() = "show-text"
    }

    /** A malformed binfire link, or input that is too large. */
    data class Error(val error: BinfireError) : Route() {
        override val action get() = "error"
    }

    /** The route as the JSON object described in the spec. */
    fun toJson(): Map<String, Any?> = when (this) {
        is OpenApp -> linkedMapOf("action" to action, "app" to app, "url" to url, "state" to state.code, "run" to run, "view" to view)
        is LoadCid -> linkedMapOf<String, Any?>("action" to action, "cid" to cid, "app" to app).also { m -> run?.let { m["run"] = it } }
        is OpenSite -> linkedMapOf("action" to action, "cid" to cid)
        is ShowText -> linkedMapOf("action" to action, "text" to text)
        is Error -> linkedMapOf("action" to action, "error" to error.code)
    }
}

/**
 * Routing of any input text and building of binfire links (`spec/links.md`).
 * Link domain, scheme, content host and limits come from [config].
 */
class Links(val registry: Registry, val config: BinfireConfig) {
    private val domain = config.linkDomain.lowercase()
    /** The public scheme and this port's own scheme, which route identically. */
    private val customSchemes = setOf(config.scheme.lowercase(), config.ownScheme.lowercase()).filter { it.isNotEmpty() }.toSet()
    private val content = ParsedUrl.parse(config.hashbin.content)

    /** Routes [text] from paste, share, a tapped link, a scan, audio or a `url` transfer. */
    fun route(text: String): Route = route(text, allowShare = true)

    /**
     * `routeShared(text)`: for shared and pasted text, which often wraps a link in
     * words. Returns `route(text)` unless that is `show-text`; then the first
     * link-like token (after stripping surrounding punctuation) whose route is
     * not `show-text` wins. Otherwise `show-text` with the whole trimmed text.
     */
    fun routeShared(text: String): Route = routeShared(text, allowShare = true)

    /**
     * `routeReceived(text)`: for text that arrives over QR, BLE, audio or a received
     * bundle. Received content never runs automatically: `open-app` URLs get
     * `run=0` (and `run` is recomputed), and `load-cid` gets `run: false`.
     */
    fun routeReceived(text: String): Route = when (val r = route(text)) {
        is Route.OpenApp -> {
            val url = UrlState.withRunZero(r.url)
            r.copy(url = url, run = UrlState.classify(url)?.run ?: false)
        }
        is Route.LoadCid -> r.copy(run = false)
        else -> r
    }

    private fun routeShared(text: String, allowShare: Boolean): Route {
        val whole = route(text, allowShare)
        if (whole !is Route.ShowText) return whole
        for (raw in text.split(' ', '\t', '\n', '\u000C', '\r')) {
            if (raw.isEmpty()) continue
            val token = cleanSharedToken(raw)
            if (!isLinkToken(token)) continue
            val r = route(token, allowShare)
            if (r !is Route.ShowText) return r
        }
        return Route.ShowText(trimAsciiWhitespace(text))
    }

    private fun isLinkToken(token: String): Boolean =
        token.startsWith("https://", ignoreCase = true) || token.startsWith("http://", ignoreCase = true) ||
            customSchemes.any { token.startsWith("$it://", ignoreCase = true) } || Cid.isCid(token.removePrefix("#"))

    private fun route(text: String, allowShare: Boolean): Route {
        val t = trimAsciiWhitespace(text)
        if (t.any { it.code <= 0x1f || it.code == 0x7f }) return Route.ShowText(t)
        if (Utf8.length(t) > config.limits.maxStateBytes + 4096) return Route.Error(BinfireError.TOO_LARGE)

        val bare = t.removePrefix("#")
        if (Cid.isCid(bare)) return Route.LoadCid(bare, null)

        val u = ParsedUrl.parse(t) ?: return Route.ShowText(t)
        if (isBinfireLink(u)) return routeBinfireLink(u, allowShare)

        contentCid(u)?.let { return Route.LoadCid(it, null) }

        registry.match(u)?.let { return openApp(it.app, t, u) }
        return Route.ShowText(t)
    }

    /**
     * A share link for an app URL: `https://D/a/<slug>…` when [url] is on the
     * app's canonical base path and its raw query and fragment are URI-safe,
     * else `https://D/open#u=…`. `null` when [url]
     * is not a registered app URL.
     */
    fun makeLink(url: String): String? {
        val u = ParsedUrl.parse(url) ?: return null
        val m = registry.match(u) ?: return null
        val basePath = ParsedUrl.parse(m.base)?.path
        return if (m.isCanonical && u.path == basePath && isUriSafe(u.rawQuery) && isUriSafe(u.rawFragment)) {
            "https://${config.linkDomain}/a/${m.app.slug}${u.querySuffix}${u.fragmentSuffix}"
        } else {
            "https://${config.linkDomain}/open#u=${encodeURIComponent(url)}"
        }
    }

    /** True when [s] holds only RFC 3986 query/fragment characters and `%XX` escapes. */
    private fun isUriSafe(s: String?): Boolean {
        if (s == null) return true
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '%') {
                if (i + 2 >= s.length || Character.digit(s[i + 1], 16) < 0 || Character.digit(s[i + 2], 16) < 0 ||
                    s[i + 1].code > 0x7f || s[i + 2].code > 0x7f
                ) return false
                i += 3
                continue
            }
            if (!(c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c in "-._~!$&'()*+,;=:@/?")) return false
            i++
        }
        return true
    }

    /** `https://D/c#<cid>`, or `https://D/c?app=<slug>#<cid>` with a hint. */
    fun makeCidLink(cid: String, slug: String? = null): String =
        "https://${config.linkDomain}/c" + (slug?.let { "?app=${encodeURIComponent(it)}" } ?: "") + "#$cid"

    /** `https://D/s#<cid>` for a site manifest. */
    fun makeSiteLink(cid: String): String = "https://${config.linkDomain}/s#$cid"

    /** True when [text] (trimmed) is an `https://D/a/…` link. Used by audio payload rules. */
    fun isHttpsAppLink(text: String): Boolean {
        val u = ParsedUrl.parse(trimAsciiWhitespace(text)) ?: return false
        return u.scheme == "https" && isBinfireLink(u) && linkPath(u).split('/').firstOrNull() == "a"
    }

    private fun isBinfireLink(u: ParsedUrl): Boolean =
        u.scheme in customSchemes || (u.scheme == "https" && u.host == domain && u.port == null && u.userinfo == null)

    private fun linkPath(u: ParsedUrl): String =
        (if (u.scheme in customSchemes) u.host + u.path else u.path).trim('/')

    private fun routeBinfireLink(u: ParsedUrl, allowShare: Boolean): Route {
        val path = linkPath(u)
        val segments = path.split('/')
        return when {
            segments.size == 2 && segments[0] == "a" -> {
                val app = registry.app(segments[1]) ?: return Route.Error(BinfireError.UNKNOWN_APP)
                val target = app.canonicalOrigin + u.querySuffix + u.fragmentSuffix
                val tu = ParsedUrl.parse(target) ?: return Route.Error(BinfireError.BAD_LINK)
                openApp(app, target, tu)
            }
            path == "open" -> {
                val fragment = u.rawFragment ?: return Route.Error(BinfireError.BAD_LINK)
                val target = QueryParams.parse(fragment, stripLeadingQuestionMark = true)["u"]
                    ?: return Route.Error(BinfireError.BAD_LINK)
                val tu = ParsedUrl.parse(target) ?: return Route.Error(BinfireError.BAD_LINK)
                val m = registry.match(tu) ?: return Route.ShowText(target)
                openApp(m.app, target, tu)
            }
            path == "c" -> {
                val cid = u.rawFragment?.takeIf { Cid.isCid(it) } ?: return Route.Error(BinfireError.INVALID_CID)
                val hint = u.queryParams["app"]?.takeIf { registry.app(it) != null }
                Route.LoadCid(cid, hint)
            }
            path == "s" -> {
                val cid = u.rawFragment?.takeIf { Cid.isCid(it) } ?: return Route.Error(BinfireError.INVALID_CID)
                Route.OpenSite(cid)
            }
            // Custom scheme only: how share extensions hand text to the app. Not recursive.
            path == "share" && u.scheme in customSchemes && allowShare -> {
                val fragment = u.rawFragment ?: return Route.Error(BinfireError.BAD_LINK)
                val text = QueryParams.parse(fragment, stripLeadingQuestionMark = true)["t"]
                    ?: return Route.Error(BinfireError.BAD_LINK)
                routeShared(text, allowShare = false)
            }
            else -> Route.Error(BinfireError.UNKNOWN_LINK)
        }
    }

    /** `https://<content host>/<CID>` with exactly one path segment that is a valid CID. */
    private fun contentCid(u: ParsedUrl): String? {
        val c = content ?: return null
        if (u.scheme != c.scheme || u.host != c.host || u.port != c.port || u.userinfo != null) return null
        val prefix = c.path.trimEnd('/') + "/"
        if (!u.path.startsWith(prefix)) return null
        val rest = u.path.substring(prefix.length)
        return rest.takeIf { '/' !in it && Cid.isCid(it) }
    }

    private fun openApp(app: RegistryApp, url: String, u: ParsedUrl): Route {
        val s = UrlState.classify(url, u)
        return Route.OpenApp(app.slug, url, s.state, s.run, s.view)
    }

    companion object {
        private val BRACKETS = listOf('(' to ')', '[' to ']', '{' to '}')

        /**
         * Strips punctuation around a shared token: leading `< ( [ { " '`, trailing
         * `> . , ; : ! ? " '`, and a trailing `)`/`]`/`}` only while the token has
         * more closing than opening brackets of that kind (so `#print(1)` survives).
         */
        fun cleanSharedToken(token: String): String {
            var s = token.trimStart('<', '(', '[', '{', '"', '\'')
            while (true) {
                val before = s
                s = s.trimEnd('>', '.', ',', ';', ':', '!', '?', '"', '\'')
                for ((open, close) in BRACKETS) {
                    while (s.endsWith(close) && s.count { it == close } > s.count { it == open }) s = s.dropLast(1)
                }
                if (s == before) return s
            }
        }

        /** JavaScript's `encodeURIComponent` (see the top-level [app.binfire.core.encodeURIComponent]). */
        fun encodeURIComponent(s: String): String = app.binfire.core.encodeURIComponent(s)

        /** Trims ASCII whitespace (tab, LF, FF, CR, space) from both ends. */
        fun trimAsciiWhitespace(s: String): String {
            fun ws(c: Char) = c == ' ' || c == '\t' || c == '\n' || c == '\u000C' || c == '\r'
            var a = 0
            var b = s.length
            while (a < b && ws(s[a])) a++
            while (b > a && ws(s[b - 1])) b--
            return s.substring(a, b)
        }
    }
}
