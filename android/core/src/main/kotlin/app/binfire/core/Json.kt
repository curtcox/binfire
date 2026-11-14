package app.binfire.core

/** Thrown by [Json.parse] for text that `JSON.parse` would reject. */
class JsonException(message: String) : Exception(message)

/**
 * A strict JSON reader and writer with JavaScript semantics.
 *
 * The specs say "JSON.parse", so untrusted input must be read exactly the way a
 * browser reads it. org.json is lenient (it accepts unquoted words, single
 * quotes and comments) and rejects duplicate keys, so binfire uses this instead.
 *
 * Values map to Kotlin as: object → `Map<String, Any?>` (insertion ordered, the
 * last duplicate key wins), array → `List<Any?>`, string → [String], number →
 * [Double], `true`/`false` → [Boolean], `null` → `null`.
 */
object Json {
    /** Maximum nesting depth. Deeper input is rejected instead of overflowing the stack. */
    const val MAX_DEPTH = 512

    /** Parses [text] like `JSON.parse`. Throws [JsonException]. */
    fun parse(text: String): Any? {
        val p = Parser(text)
        p.ws()
        val v = p.value(0)
        p.ws()
        if (p.i != text.length) p.err("unexpected trailing text")
        return v
    }

    /** Like [parse], but returns `null` on failure and requires a JSON object. */
    fun parseObject(text: String): Map<String, Any?>? = try {
        @Suppress("UNCHECKED_CAST")
        parse(text) as? Map<String, Any?>
    } catch (_: JsonException) {
        null
    }

    /** Serializes like `JSON.stringify` (no whitespace). Supports the types [parse] returns plus other [Number]s. */
    fun stringify(value: Any?): String = StringBuilder().also { write(it, value) }.toString()

    private fun write(sb: StringBuilder, v: Any?) {
        when (v) {
            null -> sb.append("null")
            is String -> quote(sb, v)
            is Boolean -> sb.append(v)
            is Double -> sb.append(numberText(v))
            is Float -> sb.append(numberText(v.toDouble()))
            is Number -> sb.append(v.toLong())
            is Map<*, *> -> {
                sb.append('{')
                var first = true
                for ((k, value) in v) {
                    if (!first) sb.append(',')
                    first = false
                    quote(sb, k.toString())
                    sb.append(':')
                    write(sb, value)
                }
                sb.append('}')
            }
            is List<*> -> {
                sb.append('[')
                v.forEachIndexed { i, e -> if (i > 0) sb.append(','); write(sb, e) }
                sb.append(']')
            }
            else -> throw IllegalArgumentException("not JSON-serializable: ${v::class}")
        }
    }

    private fun numberText(d: Double): String = when {
        d.isNaN() || d.isInfinite() -> "null"
        d == Math.rint(d) && Math.abs(d) < 1e21 -> d.toLong().toString()
        else -> d.toString()
    }

    private fun quote(sb: StringBuilder, s: String) {
        sb.append('"')
        var i = 0
        while (i < s.length) {
            val c = s[i]
            when {
                c == '"' -> sb.append("\\\"")
                c == '\\' -> sb.append("\\\\")
                c == '\b' -> sb.append("\\b")
                c == '\u000C' -> sb.append("\\f")
                c == '\n' -> sb.append("\\n")
                c == '\r' -> sb.append("\\r")
                c == '\t' -> sb.append("\\t")
                c < ' ' -> sb.append("\\u").append(String.format("%04x", c.code))
                c.isHighSurrogate() && i + 1 < s.length && s[i + 1].isLowSurrogate() -> {
                    sb.append(c).append(s[i + 1]); i++
                }
                c.isSurrogate() -> sb.append("\\u").append(String.format("%04x", c.code))
                else -> sb.append(c)
            }
            i++
        }
        sb.append('"')
    }

    private class Parser(val s: String) {
        var i = 0

        fun err(msg: String): Nothing = throw JsonException("$msg at $i")

        fun ws() {
            while (i < s.length) {
                val c = s[i]
                if (c == ' ' || c == '\t' || c == '\n' || c == '\r') i++ else break
            }
        }

        fun value(depth: Int): Any? {
            if (depth > MAX_DEPTH) err("nesting too deep")
            if (i >= s.length) err("unexpected end")
            return when (val c = s[i]) {
                '{' -> obj(depth)
                '[' -> arr(depth)
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> if (c == '-' || c in '0'..'9') num() else err("unexpected character")
            }
        }

        fun lit(word: String, v: Any?): Any? {
            if (!s.startsWith(word, i)) err("bad literal")
            i += word.length
            return v
        }

        fun obj(depth: Int): Map<String, Any?> {
            i++
            val m = LinkedHashMap<String, Any?>()
            ws()
            if (i < s.length && s[i] == '}') { i++; return m }
            while (true) {
                ws()
                if (i >= s.length || s[i] != '"') err("expected key")
                val k = str()
                ws()
                if (i >= s.length || s[i] != ':') err("expected ':'")
                i++
                ws()
                m[k] = value(depth + 1)
                ws()
                if (i >= s.length) err("unexpected end")
                when (s[i]) {
                    ',' -> i++
                    '}' -> { i++; return m }
                    else -> err("expected ',' or '}'")
                }
            }
        }

        fun arr(depth: Int): List<Any?> {
            i++
            val l = ArrayList<Any?>()
            ws()
            if (i < s.length && s[i] == ']') { i++; return l }
            while (true) {
                ws()
                l.add(value(depth + 1))
                ws()
                if (i >= s.length) err("unexpected end")
                when (s[i]) {
                    ',' -> i++
                    ']' -> { i++; return l }
                    else -> err("expected ',' or ']'")
                }
            }
        }

        fun str(): String {
            i++
            val sb = StringBuilder()
            while (true) {
                if (i >= s.length) err("unterminated string")
                val c = s[i++]
                when {
                    c == '"' -> return sb.toString()
                    c == '\\' -> {
                        if (i >= s.length) err("bad escape")
                        when (s[i++]) {
                            '"' -> sb.append('"')
                            '\\' -> sb.append('\\')
                            '/' -> sb.append('/')
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'u' -> {
                                if (i + 4 > s.length) err("bad \\u escape")
                                var code = 0
                                for (k in 0 until 4) {
                                    val d = Character.digit(s[i + k], 16)
                                    if (d < 0 || s[i + k].code > 0x7f) err("bad \\u escape")
                                    code = code * 16 + d
                                }
                                i += 4
                                sb.append(code.toChar())
                            }
                            else -> err("bad escape")
                        }
                    }
                    c < ' ' -> err("control character in string")
                    else -> sb.append(c)
                }
            }
        }

        fun num(): Double {
            val start = i
            if (s[i] == '-') i++
            if (i >= s.length) err("bad number")
            if (s[i] == '0') i++
            else if (s[i] in '1'..'9') while (i < s.length && s[i] in '0'..'9') i++
            else err("bad number")
            if (i < s.length && s[i] == '.') {
                i++
                val d = i
                while (i < s.length && s[i] in '0'..'9') i++
                if (i == d) err("bad number")
            }
            if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
                i++
                if (i < s.length && (s[i] == '+' || s[i] == '-')) i++
                val d = i
                while (i < s.length && s[i] in '0'..'9') i++
                if (i == d) err("bad number")
            }
            return s.substring(start, i).toDouble()
        }
    }
}

// Typed accessors for parsed JSON, used by the parsers in core and transfer.

/** The value as a JSON object, or `null`. */
@Suppress("UNCHECKED_CAST")
fun Any?.asJsonObject(): Map<String, Any?>? = this as? Map<String, Any?>

/** The value as a JSON array, or `null`. */
fun Any?.asJsonArray(): List<Any?>? = this as? List<Any?>

/** The value as a JSON integer (a finite number with no fraction, like `Number.isInteger`), or `null`. */
fun Any?.asJsonInteger(): Long? {
    val d = this as? Double ?: return null
    if (d.isNaN() || d.isInfinite() || d != Math.rint(d) || Math.abs(d) > 9.007199254740991E15) return null
    return d.toLong()
}
