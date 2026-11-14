package app.binfire.core

/**
 * A small URL parser that follows the WHATWG URL Standard closely enough to
 * classify URLs the way a browser would, without platform URL types (which
 * normalize escapes differently; see `spec/links.md`).
 *
 * The raw query and raw fragment are split out of the input text itself and are
 * never re-encoded, so targets can be rebuilt byte for byte.
 */
class ParsedUrl internal constructor(
    /** The text that was parsed (after stripping leading/trailing C0 controls and spaces, and tab/CR/LF). */
    val text: String,
    /** Lower-cased scheme without `:`. */
    val scheme: String,
    /** True when the URL has an authority (`scheme://…`). */
    val hasAuthority: Boolean,
    /** The userinfo before `@`, or `null` when there is none. */
    val userinfo: String?,
    /** Host: lower-cased and percent-decoded for special schemes, as written otherwise. Empty when absent. */
    val host: String,
    /** Port, or `null` when absent or the scheme's default. */
    val port: Int?,
    /** Path. For special schemes, dot segments are resolved and it always starts with `/`. */
    val path: String,
    /** Substring after the first `?` and before the first `#`, or `null` when there is no `?`. */
    val rawQuery: String?,
    /** Substring after the first `#`, or `null` when there is no `#`. */
    val rawFragment: String?,
) {
    /** `?query` (or empty) as written. */
    val querySuffix: String get() = rawQuery?.let { "?$it" } ?: ""

    /** `#fragment` (or empty) as written. */
    val fragmentSuffix: String get() = rawFragment?.let { "#$it" } ?: ""

    /** Query parameters, decoded like `URLSearchParams`. */
    val queryParams: QueryParams get() = QueryParams.parse(rawQuery ?: "")

    companion object {
        private val SPECIAL_PORTS = mapOf("http" to 80, "https" to 443, "ws" to 80, "wss" to 443, "ftp" to 21, "file" to null)
        private val SCHEME = Regex("^[A-Za-z][A-Za-z0-9+.\\-]*:")

        /** Parses an absolute URL, or returns `null` when `new URL(text)` would throw. */
        fun parse(input: String): ParsedUrl? {
            val text = clean(input)
            val m = SCHEME.find(text) ?: return null
            val scheme = m.value.dropLast(1).lowercase()
            var rest = text.substring(m.value.length)

            val hashAt = rest.indexOf('#')
            val rawFragment = if (hashAt >= 0) rest.substring(hashAt + 1) else null
            if (hashAt >= 0) rest = rest.substring(0, hashAt)
            val qAt = rest.indexOf('?')
            val rawQuery = if (qAt >= 0) rest.substring(qAt + 1) else null
            if (qAt >= 0) rest = rest.substring(0, qAt)

            val special = scheme in SPECIAL_PORTS
            return if (special) {
                rest = rest.replace('\\', '/')
                if (scheme == "file") {
                    val body = rest.trimStart('/')
                    val slash = body.indexOf('/')
                    val host = if (rest.startsWith("//")) (if (slash >= 0) body.substring(0, slash) else body).lowercase() else ""
                    val path = if (rest.startsWith("//")) (if (slash >= 0) body.substring(slash) else "/") else "/" + body
                    return ParsedUrl(text, scheme, true, null, host, null, normalizePath(path), rawQuery, rawFragment)
                }
                val body = rest.trimStart('/')
                val slash = body.indexOf('/')
                val authority = if (slash >= 0) body.substring(0, slash) else body
                val path = if (slash >= 0) body.substring(slash) else "/"
                val auth = parseAuthority(authority, special = true, defaultPort = SPECIAL_PORTS[scheme]) ?: return null
                if (auth.host.isEmpty()) return null
                ParsedUrl(text, scheme, true, auth.userinfo, auth.host, auth.port, normalizePath(path), rawQuery, rawFragment)
            } else if (rest.startsWith("//")) {
                val body = rest.substring(2)
                val slash = body.indexOf('/')
                val authority = if (slash >= 0) body.substring(0, slash) else body
                val path = if (slash >= 0) body.substring(slash) else ""
                val auth = parseAuthority(authority, special = false, defaultPort = null) ?: return null
                ParsedUrl(text, scheme, true, auth.userinfo, auth.host, auth.port, path, rawQuery, rawFragment)
            } else {
                ParsedUrl(text, scheme, false, null, "", null, rest, rawQuery, rawFragment)
            }
        }

        /** The URL standard strips leading/trailing C0 controls and spaces, and removes tab, LF and CR anywhere. */
        private fun clean(s: String): String {
            var a = 0
            var b = s.length
            while (a < b && s[a] <= ' ') a++
            while (b > a && s[b - 1] <= ' ') b--
            val t = s.substring(a, b)
            return if (t.any { it == '\t' || it == '\n' || it == '\r' }) t.filterNot { it == '\t' || it == '\n' || it == '\r' } else t
        }

        private class Authority(val userinfo: String?, val host: String, val port: Int?)

        private fun parseAuthority(authority: String, special: Boolean, defaultPort: Int?): Authority? {
            val at = authority.lastIndexOf('@')
            val userinfo = if (at >= 0) authority.substring(0, at) else null
            val hostPort = if (at >= 0) authority.substring(at + 1) else authority
            val hostRaw: String
            val portText: String?
            if (hostPort.startsWith("[")) {
                val close = hostPort.indexOf(']')
                if (close < 0) return null
                hostRaw = hostPort.substring(0, close + 1)
                val after = hostPort.substring(close + 1)
                portText = when {
                    after.isEmpty() -> null
                    after.startsWith(":") -> after.substring(1)
                    else -> return null
                }
            } else {
                val colon = hostPort.indexOf(':')
                hostRaw = if (colon >= 0) hostPort.substring(0, colon) else hostPort
                portText = if (colon >= 0) hostPort.substring(colon + 1) else null
            }
            var port: Int? = null
            if (!portText.isNullOrEmpty()) {
                if (!portText.all { it in '0'..'9' }) return null
                val n = portText.trimStart('0').ifEmpty { "0" }
                if (n.length > 5 || n.toInt() > 65535) return null
                port = n.toInt()
            }
            if (port != null && port == defaultPort) port = null
            val host = if (special) {
                if (hostRaw.startsWith("[")) hostRaw.lowercase() else {
                    val decoded = percentDecodeUtf8(hostRaw).lowercase()
                    if (decoded.any { isForbiddenDomainChar(it) }) return null
                    decoded
                }
            } else {
                if (hostRaw.any { isForbiddenHostChar(it) }) return null
                hostRaw
            }
            return Authority(userinfo, host, port)
        }

        private fun isForbiddenHostChar(c: Char): Boolean =
            c == '\u0000' || c == '\t' || c == '\n' || c == '\r' || c == ' ' || c == '#' || c == '/' || c == ':' ||
                c == '<' || c == '>' || c == '?' || c == '@' || c == '[' || c == '\\' || c == ']' || c == '^' || c == '|'

        private fun isForbiddenDomainChar(c: Char): Boolean =
            isForbiddenHostChar(c) || c < ' ' || c == '%' || c == '\u007f'

        private fun isSingleDot(s: String) = s == "." || s.equals("%2e", ignoreCase = true)
        private fun isDoubleDot(s: String) = s == ".." || s.equals(".%2e", true) || s.equals("%2e.", true) || s.equals("%2e%2e", true)

        /** Resolves `.` and `..` segments and percent-encodes like the URL standard's path state. */
        private fun normalizePath(path: String): String {
            val segments = path.removePrefix("/").split('/')
            val out = ArrayList<String>()
            segments.forEachIndexed { i, seg ->
                val last = i == segments.lastIndex
                when {
                    isDoubleDot(seg) -> { if (out.isNotEmpty()) out.removeAt(out.size - 1); if (last) out.add("") }
                    isSingleDot(seg) -> if (last) out.add("")
                    else -> out.add(encodePathSegment(seg))
                }
            }
            return "/" + out.joinToString("/")
        }

        private fun encodePathSegment(s: String): String {
            if (s.all { it.code in 0x21..0x7e && it !in "\"#<>?`{}" }) return s
            val sb = StringBuilder()
            for (b in Utf8.encode(s)) {
                val v = b.toInt() and 0xff
                if (v in 0x21..0x7e && v.toChar() !in "\"#<>?`{}") sb.append(v.toChar()) else sb.append('%').append(HEX[v shr 4]).append(HEX[v and 15])
            }
            return sb.toString()
        }

        private const val HEX = "0123456789ABCDEF"
    }
}

/** Query parameters decoded the way `URLSearchParams` decodes them. */
class QueryParams private constructor(
    /** All name/value pairs in order. */
    val pairs: List<Pair<String, String>>,
) {
    /** The first value for [name], or `null` (`URLSearchParams.get`). */
    operator fun get(name: String): String? = pairs.firstOrNull { it.first == name }?.second

    /** True when [name] is present (`URLSearchParams.has`). */
    fun has(name: String): Boolean = pairs.any { it.first == name }

    companion object {
        /**
         * Parses `application/x-www-form-urlencoded` text. When [stripLeadingQuestionMark]
         * is true, one leading `?` is ignored, like `new URLSearchParams(string)`.
         */
        fun parse(text: String, stripLeadingQuestionMark: Boolean = false): QueryParams {
            val s = if (stripLeadingQuestionMark && text.startsWith("?")) text.substring(1) else text
            val pairs = ArrayList<Pair<String, String>>()
            for (part in s.split('&')) {
                if (part.isEmpty()) continue
                val eq = part.indexOf('=')
                val name = if (eq >= 0) part.substring(0, eq) else part
                val value = if (eq >= 0) part.substring(eq + 1) else ""
                pairs.add(formDecode(name) to formDecode(value))
            }
            return QueryParams(pairs)
        }

        private fun formDecode(s: String): String = percentDecodeUtf8(s.replace('+', ' '))
    }
}

/**
 * Percent-decodes [s] as UTF-8 like the URL standard: invalid `%` sequences
 * stay as they are and malformed UTF-8 becomes U+FFFD.
 */
internal fun percentDecodeUtf8(s: String): String {
    if (s.indexOf('%') < 0) return s
    val bytes = Utf8.encode(s)
    val out = java.io.ByteArrayOutputStream(bytes.size)
    var i = 0
    while (i < bytes.size) {
        val b = bytes[i]
        if (b == '%'.code.toByte() && i + 2 < bytes.size) {
            val hi = Character.digit(bytes[i + 1].toInt().toChar(), 16)
            val lo = Character.digit(bytes[i + 2].toInt().toChar(), 16)
            if (hi >= 0 && lo >= 0 && bytes[i + 1] >= 0 && bytes[i + 2] >= 0) {
                out.write(hi * 16 + lo)
                i += 3
                continue
            }
        }
        out.write(b.toInt())
        i++
    }
    return String(out.toByteArray(), Charsets.UTF_8)
}

/**
 * JavaScript's `encodeURIComponent`: everything except `A–Z a–z 0–9 - _ . ! ~ * ' ( )`
 * is percent-encoded as UTF-8 with upper-case hex. Throws [IllegalArgumentException]
 * for a lone surrogate, where JavaScript throws `URIError`.
 */
fun encodeURIComponent(s: String): String {
    val hex = "0123456789ABCDEF"
    val sb = StringBuilder(s.length)
    var i = 0
    while (i < s.length) {
        val c = s[i]
        if (c in 'A'..'Z' || c in 'a'..'z' || c in '0'..'9' || c in "-_.!~*'()") {
            sb.append(c); i++; continue
        }
        val cp: Int
        if (c.isHighSurrogate() && i + 1 < s.length && s[i + 1].isLowSurrogate()) {
            cp = Character.toCodePoint(c, s[i + 1]); i += 2
        } else if (c.isSurrogate()) {
            throw IllegalArgumentException("lone surrogate at $i")
        } else {
            cp = c.code; i++
        }
        for (b in String(Character.toChars(cp)).toByteArray(Charsets.UTF_8)) {
            val v = b.toInt() and 0xff
            sb.append('%').append(hex[v shr 4]).append(hex[v and 15])
        }
    }
    return sb.toString()
}
