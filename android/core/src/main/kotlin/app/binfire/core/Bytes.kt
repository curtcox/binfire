package app.binfire.core

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets

/**
 * UTF-8 with JavaScript semantics. Kotlin strings, like JavaScript strings, are
 * UTF-16 code units and may hold lone surrogates. The JVM encoder turns those
 * into `?`, but JavaScript (`TextEncoder`, `Buffer.byteLength`) uses U+FFFD.
 */
object Utf8 {
    /** UTF-8 byte length of [s], counting each lone surrogate as 3 bytes (U+FFFD). */
    fun length(s: CharSequence): Long {
        var n = 0L
        var i = 0
        while (i < s.length) {
            val c = s[i]
            n += when {
                c.code < 0x80 -> 1
                c.code < 0x800 -> 2
                c.isHighSurrogate() && i + 1 < s.length && s[i + 1].isLowSurrogate() -> { i++; 4 }
                else -> 3
            }
            i++
        }
        return n
    }

    /** Encodes like `TextEncoder`: lone surrogates become U+FFFD. */
    fun encode(s: String): ByteArray {
        if (!hasLoneSurrogate(s)) return s.toByteArray(StandardCharsets.UTF_8)
        return wellFormed(s).toByteArray(StandardCharsets.UTF_8)
    }

    /**
     * Decodes like `new TextDecoder("utf-8", { fatal: true })`: returns `null` for
     * malformed input, and drops one leading byte order mark.
     */
    fun decodeStrict(bytes: ByteArray): String? {
        val text = try {
            StandardCharsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: CharacterCodingException) {
            return null
        }
        return if (text.startsWith('﻿')) text.substring(1) else text
    }

    /** True when [s] contains a surrogate that is not part of a pair. */
    fun hasLoneSurrogate(s: CharSequence): Boolean {
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c.isHighSurrogate()) {
                if (i + 1 < s.length && s[i + 1].isLowSurrogate()) i++ else return true
            } else if (c.isLowSurrogate()) return true
            i++
        }
        return false
    }

    /** [s] with lone surrogates replaced by U+FFFD (`String.prototype.toWellFormed`). */
    fun wellFormed(s: String): String {
        if (!hasLoneSurrogate(s)) return s
        val sb = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c.isHighSurrogate() && i + 1 < s.length && s[i + 1].isLowSurrogate()) {
                sb.append(c).append(s[i + 1]); i += 2; continue
            }
            sb.append(if (c.isSurrogate()) '�' else c)
            i++
        }
        return sb.toString()
    }
}

/** RFC 4648 section 5 base64url without padding, with the strict decoder from `spec/README.md`. */
object Base64Url {
    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    private val VALUES = IntArray(128) { -1 }.also { t -> ALPHABET.forEachIndexed { i, c -> t[c.code] = i } }

    /** Encodes [bytes] without padding. */
    fun encode(bytes: ByteArray): String {
        val sb = StringBuilder((bytes.size * 4 + 2) / 3)
        var i = 0
        while (i + 3 <= bytes.size) {
            val v = (bytes[i].toInt() and 0xff shl 16) or (bytes[i + 1].toInt() and 0xff shl 8) or (bytes[i + 2].toInt() and 0xff)
            sb.append(ALPHABET[v ushr 18]).append(ALPHABET[v ushr 12 and 63]).append(ALPHABET[v ushr 6 and 63]).append(ALPHABET[v and 63])
            i += 3
        }
        when (bytes.size - i) {
            1 -> {
                val v = bytes[i].toInt() and 0xff
                sb.append(ALPHABET[v ushr 2]).append(ALPHABET[v shl 4 and 63])
            }
            2 -> {
                val v = (bytes[i].toInt() and 0xff shl 8) or (bytes[i + 1].toInt() and 0xff)
                sb.append(ALPHABET[v ushr 10]).append(ALPHABET[v ushr 4 and 63]).append(ALPHABET[v shl 2 and 63])
            }
        }
        return sb.toString()
    }

    /**
     * Decodes [text], or returns `null` when it has padding, characters outside
     * the alphabet, a length with `len % 4 == 1`, or non-canonical trailing bits.
     */
    fun decode(text: CharSequence): ByteArray? {
        val n = text.length
        if (n % 4 == 1) return null
        val out = ByteArray(n / 4 * 3 + maxOf(0, n % 4 - 1))
        var acc = 0
        var bits = 0
        var o = 0
        for (k in 0 until n) {
            val c = text[k].code
            val v = if (c < 128) VALUES[c] else -1
            if (v < 0) return null
            acc = (acc shl 6) or v
            bits += 6
            if (bits >= 8) {
                bits -= 8
                out[o++] = (acc ushr bits).toByte()
                acc = acc and ((1 shl bits) - 1)
            }
        }
        if (acc != 0) return null // non-canonical trailing bits
        return out
    }
}

/** Lower-case hex helpers. */
object Hex {
    /** Lower-case hex of [bytes]. */
    fun encode(bytes: ByteArray): String = bytes.joinToString("") { String.format("%02x", it.toInt() and 0xff) }

    /** Decodes an even-length hex string. Throws [IllegalArgumentException] otherwise. */
    fun decode(hex: String): ByteArray {
        require(hex.length % 2 == 0) { "odd hex length" }
        return ByteArray(hex.length / 2) { i ->
            val hi = Character.digit(hex[2 * i], 16)
            val lo = Character.digit(hex[2 * i + 1], 16)
            require(hi >= 0 && lo >= 0) { "bad hex" }
            (hi * 16 + lo).toByte()
        }
    }
}
