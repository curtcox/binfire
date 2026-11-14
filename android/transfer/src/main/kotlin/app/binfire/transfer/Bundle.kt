package app.binfire.transfer

import app.binfire.core.BinfireConfig
import app.binfire.core.BinfireError
import app.binfire.core.BinfireException
import app.binfire.core.Cid
import app.binfire.core.Json
import app.binfire.core.ParsedUrl
import app.binfire.core.SiteManifest
import app.binfire.core.Sites
import app.binfire.core.Utf8
import app.binfire.core.asJsonArray
import app.binfire.core.asJsonObject

/** Payload kinds (`spec/transfer.md`). */
enum class BundleKind(val code: String) {
    URL("url"),
    CID("cid"),
    SITE("site");

    override fun toString(): String = code

    companion object {
        fun fromCode(code: String): BundleKind? = entries.firstOrNull { it.code == code }
    }
}

/** One entry of a bundle: content bytes and their CID. */
class BundleEntry(val cid: String, val bytes: ByteArray) {
    /** Builds an entry for [bytes], computing the CID. */
    constructor(bytes: ByteArray) : this(Cid.computeCid(bytes), bytes)
}

/**
 * A decoded (verified) or to-be-encoded bundle. Use [Bundle.url], [Bundle.cid]
 * or [Bundle.site] to build one, [encode] to serialize it, and [Bundle.decode]
 * to read and verify received bytes.
 */
class Bundle(
    val kind: BundleKind,
    /** The state URL, for [BundleKind.URL]. */
    val url: String? = null,
    /** The document CID ([BundleKind.CID]) or manifest CID ([BundleKind.SITE]). */
    val cid: String? = null,
    /** Optional app slug hint, for [BundleKind.CID]. */
    val app: String? = null,
    /** Optional display name, at most 200 code points. */
    val name: String? = null,
    /** Entries in container order. */
    val entries: List<BundleEntry> = emptyList(),
    /** The validated manifest, for a decoded [BundleKind.SITE] bundle. */
    val manifest: SiteManifest? = null,
) {
    /** Serializes to a bundle container (`.binfire` file contents). */
    fun encode(): ByteArray {
        val header = LinkedHashMap<String, Any?>()
        header["kind"] = kind.code
        url?.let { header["url"] = it }
        cid?.let { header["cid"] = it }
        app?.let { header["app"] = it }
        name?.let { header["name"] = it }
        header["entries"] = entries.map { mapOf("cid" to it.cid) }
        val head = Utf8.encode(Json.stringify(header))
        val size = 8L + head.size + entries.sumOf { it.bytes.size.toLong() }
        require(size <= Int.MAX_VALUE) { "bundle too large to encode in memory" }
        val out = ByteArray(size.toInt())
        MAGIC.copyInto(out, 0)
        putUInt32(out, 4, head.size.toLong())
        head.copyInto(out, 8)
        var at = 8 + head.size
        for (e in entries) {
            e.bytes.copyInto(out, at)
            at += e.bytes.size
        }
        return out
    }

    companion object {
        /** `"BFB1"`. */
        val MAGIC = byteArrayOf(0x42, 0x46, 0x42, 0x31)

        /** Largest header length. */
        const val MAX_HEADER = 1048576

        /** MIME type of `.binfire` files. */
        const val MIME_TYPE = "application/vnd.binfire.bundle"

        private const val MAX_NAME = 200

        /** A `url` bundle. */
        fun url(url: String, name: String? = null) = Bundle(BundleKind.URL, url = url, name = name)

        /** A `cid` bundle carrying [bytes]. */
        fun cid(bytes: ByteArray, app: String? = null, name: String? = null): Bundle {
            val e = BundleEntry(bytes)
            return Bundle(BundleKind.CID, cid = e.cid, app = app, name = name, entries = listOf(e))
        }

        /** A `site` bundle: the manifest bytes first, then each distinct file. */
        fun site(manifestBytes: ByteArray, files: List<ByteArray>, name: String? = null): Bundle {
            val m = BundleEntry(manifestBytes)
            val rest = files.map { BundleEntry(it) }.distinctBy { it.cid }.filter { it.cid != m.cid }
            return Bundle(BundleKind.SITE, cid = m.cid, name = name, entries = listOf(m) + rest)
        }

        /**
         * Decodes and verifies a bundle container, checking in the order the spec
         * lists. Throws [BinfireException] with the spec's code.
         */
        fun decode(bytes: ByteArray, limits: BinfireConfig.Limits): Bundle {
            // 1. Magic and header length.
            if (bytes.size < 4 || !MAGIC.indices.all { bytes[it] == MAGIC[it] }) bad(BinfireError.BAD_MAGIC)
            if (bytes.size < 8) bad(BinfireError.BAD_BUNDLE, "no header length")
            val hlen = getUInt32(bytes, 4)
            if (hlen < 2 || hlen > MAX_HEADER || bytes.size < 8 + hlen) bad(BinfireError.BAD_BUNDLE, "header length")
            val headerEnd = 8 + hlen.toInt()

            // 2. Header JSON.
            val text = Utf8.decodeStrict(bytes.copyOfRange(8, headerEnd)) ?: bad(BinfireError.BAD_BUNDLE, "header not UTF-8")
            val h = Json.parseObject(text) ?: bad(BinfireError.BAD_BUNDLE, "header not a JSON object")
            val kind = (h["kind"] as? String)?.let { BundleKind.fromCode(it) } ?: bad(BinfireError.BAD_BUNDLE, "kind")
            val entryCids = (h["entries"].asJsonArray() ?: bad(BinfireError.BAD_BUNDLE, "entries"))
                .map { it.asJsonObject()?.get("cid") as? String ?: bad(BinfireError.BAD_BUNDLE, "entry") }
            val url = if (kind == BundleKind.URL) {
                (h["url"] as? String)?.takeIf { ParsedUrl.parse(it) != null } ?: bad(BinfireError.BAD_BUNDLE, "url")
            } else null
            val cid = if (kind != BundleKind.URL) h["cid"] as? String ?: bad(BinfireError.BAD_BUNDLE, "cid") else null
            val app = if (kind == BundleKind.CID) optionalString(h, "app") else null
            val name = optionalString(h, "name")
            if (name != null && name.codePointCount(0, name.length) > MAX_NAME) bad(BinfireError.BAD_BUNDLE, "name too long")

            // 3. Entry CIDs and sizes.
            for (c in entryCids) if (!Cid.isCid(c)) bad(BinfireError.INVALID_CID, c)
            if (cid != null && !Cid.isCid(cid)) bad(BinfireError.INVALID_CID, cid)
            var sum = 0L
            for (c in entryCids) {
                sum += Cid.cidLength(c)
                if (sum > limits.maxTransferBytes) bad(BinfireError.TOO_LARGE)
            }
            if (bytes.size.toLong() != headerEnd + sum) bad(BinfireError.BAD_BUNDLE, "container length")

            // 4. Verify each entry.
            val entries = ArrayList<BundleEntry>(entryCids.size)
            var at = headerEnd
            for (c in entryCids) {
                val n = Cid.cidLength(c).toInt()
                val b = bytes.copyOfRange(at, at + n)
                at += n
                if (!Cid.verify(c, b)) bad(BinfireError.MISMATCH, c)
                entries.add(BundleEntry(c, b))
            }

            // 5. Per kind.
            var manifest: SiteManifest? = null
            when (kind) {
                BundleKind.URL -> if (entries.isNotEmpty()) bad(BinfireError.BAD_BUNDLE, "url bundle with entries")
                BundleKind.CID -> if (entries.size != 1 || entries[0].cid != cid) bad(BinfireError.BAD_BUNDLE, "cid entries")
                BundleKind.SITE -> {
                    if (entries.isEmpty() || entries[0].cid != cid) bad(BinfireError.BAD_BUNDLE, "manifest not first")
                    val m = Sites.validateManifest(entries[0].bytes, limits)
                    val distinct = HashSet<String>()
                    for (e in entries) if (!distinct.add(e.cid)) bad(BinfireError.BAD_BUNDLE, "duplicate entry")
                    val fileCids = m.files.values.map { it.cid }.toSet()
                    for (f in fileCids) if (f !in distinct) bad(BinfireError.BAD_BUNDLE, "missing file $f")
                    for (e in entries.drop(1)) if (e.cid !in fileCids) bad(BinfireError.BAD_BUNDLE, "entry outside manifest")
                    manifest = m
                }
            }
            return Bundle(kind, url, cid, app, name, entries, manifest)
        }

        private fun optionalString(h: Map<String, Any?>, key: String): String? {
            val v = h[key] ?: return null
            return v as? String ?: bad(BinfireError.BAD_BUNDLE, key)
        }
    }
}

internal fun bad(error: BinfireError, message: String? = null): Nothing = throw BinfireException(error, message)

internal fun getUInt32(b: ByteArray, at: Int): Long =
    ((b[at].toLong() and 0xff) shl 24) or ((b[at + 1].toLong() and 0xff) shl 16) or
        ((b[at + 2].toLong() and 0xff) shl 8) or (b[at + 3].toLong() and 0xff)

internal fun putUInt32(b: ByteArray, at: Int, v: Long) {
    b[at] = (v ushr 24).toByte()
    b[at + 1] = (v ushr 16).toByte()
    b[at + 2] = (v ushr 8).toByte()
    b[at + 3] = v.toByte()
}
