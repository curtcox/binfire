package app.binfire.transfer

import app.binfire.core.Base64Url
import app.binfire.core.BinfireError
import app.binfire.core.Cid
import app.binfire.core.Qr

/**
 * One chunk frame (`spec/transfer.md`, "Chunk frames"). The uint32 fields are
 * held as [Long] so the whole unsigned range is representable.
 */
class Frame(
    /** Transfer id: 8 random bytes, big-endian. */
    val id: Long,
    val index: Long,
    val count: Long,
    /** Byte offset of [data] in the payload. */
    val offset: Long,
    /** Payload length. */
    val total: Long,
    /** Payload CID. */
    val cid: String,
    val data: ByteArray,
) {
    /** Serializes this frame (version 1, flags 0). */
    fun encode(): ByteArray {
        val c = cid.toByteArray(Charsets.US_ASCII)
        require(c.size in 8..94) { "cid length" }
        val out = ByteArray(Frames.HEADER_BYTES + c.size + data.size)
        out[0] = 'B'.code.toByte()
        out[1] = 'F'.code.toByte()
        out[2] = Frames.VERSION.toByte()
        out[3] = 0
        for (i in 0 until 8) out[4 + i] = (id ushr (8 * (7 - i))).toByte()
        putUInt32(out, 12, index)
        putUInt32(out, 16, count)
        putUInt32(out, 20, offset)
        putUInt32(out, 24, total)
        out[28] = c.size.toByte()
        c.copyInto(out, Frames.HEADER_BYTES)
        data.copyInto(out, Frames.HEADER_BYTES + c.size)
        return out
    }
}

/** Chunk frame encoding and decoding, plus the `BF1:` QR text form. */
object Frames {
    const val VERSION = 1

    /** Fixed header size before the CID. */
    const val HEADER_BYTES = 29

    /** Data chunk size for multi-frame QR. */
    const val QR_CHUNK_SIZE = 512

    /** Prefix of a multi-frame QR text. */
    const val QR_PREFIX = Qr.FRAME_PREFIX

    /** Splits [payload] into frames, deterministically (`encodeFrames`). */
    fun encode(payload: ByteArray, id: Long, chunkSize: Int): List<ByteArray> {
        require(chunkSize > 0) { "chunkSize must be positive" }
        val cid = Cid.computeCid(payload)
        val total = payload.size
        val count = maxOf(1, (total + chunkSize - 1) / chunkSize)
        return (0 until count).map { i ->
            val offset = i.toLong() * chunkSize
            val end = minOf(offset + chunkSize, total.toLong())
            Frame(id, i.toLong(), count.toLong(), offset, total.toLong(), cid, payload.copyOfRange(offset.toInt(), end.toInt())).encode()
        }
    }

    /** Parses and checks one frame (`decodeFrame`). Throws `BinfireException`. */
    fun decode(bytes: ByteArray): Frame {
        if (bytes.size < 2 || bytes[0] != 'B'.code.toByte() || bytes[1] != 'F'.code.toByte()) bad(BinfireError.BAD_MAGIC)
        if (bytes.size >= 3 && bytes[2].toInt() != VERSION) bad(BinfireError.BAD_VERSION)
        if (bytes.size >= 4 && bytes[3].toInt() != 0) bad(BinfireError.BAD_VERSION)
        if (bytes.size < HEADER_BYTES) bad(BinfireError.BAD_FRAME, "truncated header")
        var id = 0L
        for (i in 0 until 8) id = (id shl 8) or (bytes[4 + i].toLong() and 0xff)
        val index = getUInt32(bytes, 12)
        val count = getUInt32(bytes, 16)
        val offset = getUInt32(bytes, 20)
        val total = getUInt32(bytes, 24)
        val cidLen = bytes[28].toInt() and 0xff
        if (cidLen !in 8..94 || bytes.size < HEADER_BYTES + cidLen) bad(BinfireError.BAD_FRAME, "truncated cid")
        val cid = String(bytes, HEADER_BYTES, cidLen, Charsets.ISO_8859_1)
        if (!Cid.isCid(cid)) bad(BinfireError.BAD_FRAME, "invalid cid")
        val data = bytes.copyOfRange(HEADER_BYTES + cidLen, bytes.size)
        if (index >= count) bad(BinfireError.BAD_FRAME, "index >= count")
        if (offset + data.size > total) bad(BinfireError.BAD_FRAME, "chunk past total")
        if (total != Cid.cidLength(cid)) bad(BinfireError.BAD_FRAME, "total disagrees with cid")
        return Frame(id, index, count, offset, total, cid, data)
    }

    /** `BF1:` + base64url(frame). */
    fun toQrText(frame: ByteArray): String = QR_PREFIX + Base64Url.encode(frame)

    /** True when [text] is a multi-frame QR text, which goes to a [Reassembler], never to `route`. */
    fun isQrText(text: String): Boolean = text.startsWith(QR_PREFIX)

    /** The frame bytes of a `BF1:` text. Throws `bad-frame` when it is not one. */
    fun fromQrText(text: String): ByteArray {
        if (!isQrText(text)) bad(BinfireError.BAD_FRAME, "not a BF1: text")
        return Base64Url.decode(text.substring(QR_PREFIX.length)) ?: bad(BinfireError.BAD_FRAME, "bad base64url")
    }

    /** Parses a 16-hex-digit transfer id. */
    fun idFromHex(hex: String): Long {
        require(hex.length == 16) { "id must be 16 hex digits" }
        return java.lang.Long.parseUnsignedLong(hex, 16)
    }
}
