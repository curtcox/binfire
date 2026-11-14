package app.binfire.core

/**
 * lz-string 1.5.0 `compressToEncodedURIComponent` and Fragment Kit's bounded,
 * strict decoder (`spec/state.md`, reference `tools/lib/lz.mjs`).
 *
 * Text is a sequence of UTF-16 code units, exactly as in JavaScript. Kotlin
 * strings are the same, so lone surrogates survive a round trip.
 */
object Lz {
    private const val KEY = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$"

    /** Default decode limit used by Fragment Kit (5 MiB). */
    const val DEFAULT_LIMIT: Long = 5L * 1024 * 1024

    /** lz-string 1.5.0 `compressToEncodedURIComponent(text)`. */
    fun compress(text: String): String {
        val out = StringBuilder()
        val dictionary = HashMap<String, Int>()
        val toCreate = HashSet<String>()
        var w = ""
        var enlargeIn = 2
        var dictSize = 3
        var numBits = 2
        var value = 0
        var position = 0

        fun bits(count: Int, v: Int) {
            var x = v
            for (i in 0 until count) {
                value = (value shl 1) or (x and 1)
                if (position == 5) {
                    position = 0
                    out.append(KEY[value])
                    value = 0
                } else {
                    position++
                }
                x = x shr 1
            }
        }

        fun enlarge() {
            enlargeIn--
            if (enlargeIn == 0) {
                enlargeIn = 1 shl numBits
                numBits++
            }
        }

        fun emit(phrase: String) {
            if (phrase in toCreate) {
                val code = phrase[0].code
                if (code < 256) {
                    bits(numBits, 0)
                    bits(8, code)
                } else {
                    bits(numBits, 1)
                    bits(16, code)
                }
                enlarge()
                toCreate.remove(phrase)
            } else {
                bits(numBits, dictionary.getValue(phrase))
            }
            enlarge()
        }

        for (ch in text) {
            val c = ch.toString()
            if (c !in dictionary) {
                dictionary[c] = dictSize++
                toCreate.add(c)
            }
            val wc = w + c
            if (wc in dictionary) {
                w = wc
            } else {
                emit(w)
                val code = dictSize++
                // lz-string keeps its dictionary in a plain JS object, where assigning the
                // key "__proto__" is silently ignored. Reproduce that so output is identical.
                if (wc != "__proto__") dictionary[wc] = code
                w = c
            }
        }
        if (w.isNotEmpty()) emit(w)
        bits(numBits, 2)
        // Flush the last character.
        while (true) {
            value = value shl 1
            if (position == 5) {
                out.append(KEY[value])
                break
            }
            position++
        }
        return out.toString()
    }

    /**
     * Decodes [input] with Fragment Kit's bounds. [limitBytes] bounds both the
     * UTF-16 length and the UTF-8 size of the output.
     *
     * Throws [BinfireException] with [BinfireError.TOO_LARGE] or [BinfireError.INVALID].
     */
    fun decompress(input: String, limitBytes: Long = DEFAULT_LIMIT): String {
        if (input.length > Math.ceil(limitBytes * 4.0).toLong() + 64) fail(BinfireError.TOO_LARGE)
        val result = decodeSource(input, limitBytes)
        if (result == null || compress(result) != input.replace(' ', '+')) fail(BinfireError.INVALID)
        if (result.length > limitBytes || Utf8.length(result) > limitBytes) fail(BinfireError.TOO_LARGE)
        return result
    }

    private fun decodeSource(raw: String, limit: Long): String? {
        if (raw.isEmpty()) return null
        val input = raw.replace(' ', '+')
        for (ch in input) if (KEY.indexOf(ch) < 0) return null
        var position = 32
        var index = 1
        var value = KEY.indexOf(input[0])

        fun bits(count: Int): Long {
            var result = 0L
            for (p in 0 until count) {
                if (value and position != 0) result += 1L shl p
                position = position shr 1
                if (position == 0) {
                    position = 32
                    value = if (index < input.length) KEY.indexOf(input[index]) else -1
                    index++
                    if (value < 0) value = 0
                }
            }
            return result
        }

        // Entries 0..2 are placeholders, as in the reference.
        val dictionary = ArrayList<String?>().apply { add(null); add(null); add(null) }
        var next = bits(2)
        val c = when (next) {
            0L -> bits(8).toInt().toChar().toString()
            1L -> bits(16).toInt().toChar().toString()
            2L -> return ""
            else -> return null
        }
        dictionary.add(c)
        var w = c
        var enlarge = 4L
        var numBits = 3
        var length = 1L
        if (length > limit) fail(BinfireError.TOO_LARGE)
        val output = StringBuilder(c)
        while (true) {
            if (index > input.length) return null
            next = bits(numBits)
            if (next == 0L || next == 1L) {
                dictionary.add(bits(if (next == 0L) 8 else 16).toInt().toChar().toString())
                next = (dictionary.size - 1).toLong()
                enlarge--
            } else if (next == 2L) {
                return output.toString()
            }
            if (enlarge == 0L) {
                enlarge = 1L shl numBits
                numBits++
            }
            val dictSize = dictionary.size
            var entry = if (next < dictSize) dictionary[next.toInt()] else null
            if (entry == null) {
                if (next != dictSize.toLong()) return null
                entry = w + w[0]
            }
            length += entry.length
            if (length > limit) fail(BinfireError.TOO_LARGE)
            output.append(entry)
            dictionary.add(w + entry[0])
            enlarge--
            w = entry
            if (enlarge == 0L) {
                enlarge = 1L shl numBits
                numBits++
            }
        }
    }
}
