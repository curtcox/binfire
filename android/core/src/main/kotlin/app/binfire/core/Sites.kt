package app.binfire.core

import java.security.MessageDigest

/** One file in a site manifest. */
data class SiteFile(val cid: String, val type: String, val size: Long)

/** A validated site manifest (`spec/site-manifest.md`). */
data class SiteManifest(
    val name: String,
    /** Key of [files] that is served first. */
    val entry: String,
    /** Path → file, in manifest order. */
    val files: Map<String, SiteFile>,
    /** The optional `source` object. binfire only displays it. */
    val source: Map<String, Any?>?,
) {
    /** Sum of all file sizes. */
    val totalBytes: Long get() = files.values.sumOf { it.size }
}

/** Packaged static sites: manifest validation, paths and site IDs. */
object Sites {
    /** Largest manifest accepted, in bytes. */
    const val MAX_MANIFEST_BYTES = 1024 * 1024

    private const val MAX_NAME = 200
    private const val MAX_TYPE = 100

    /**
     * Validates manifest [bytes] against [limits] in the order the spec lists.
     * Throws [BinfireException] with the spec's code on the first failure.
     */
    fun validateManifest(bytes: ByteArray, limits: BinfireConfig.Limits): SiteManifest {
        // 1. Size, UTF-8, JSON object.
        if (bytes.size > MAX_MANIFEST_BYTES) fail(BinfireError.BAD_MANIFEST, "manifest larger than 1 MiB")
        val text = Utf8.decodeStrict(bytes) ?: fail(BinfireError.BAD_MANIFEST, "not UTF-8")
        val root = Json.parseObject(text) ?: fail(BinfireError.BAD_MANIFEST, "not a JSON object")
        // 2. Format and version.
        if (root["format"] != "binfire-site" || root["version"].asJsonInteger() != 1L) fail(BinfireError.BAD_MANIFEST, "format or version")
        // 3. Name.
        val name = root["name"] as? String
        if (name.isNullOrEmpty() || name.codePointCount(0, name.length) > MAX_NAME) fail(BinfireError.BAD_MANIFEST, "name")
        // 4. Files object.
        val filesObj = root["files"].asJsonObject() ?: fail(BinfireError.BAD_MANIFEST, "files must be an object")
        if (filesObj.isEmpty() || filesObj.size > limits.maxSiteFiles) fail(BinfireError.TOO_MANY_FILES)
        // 5. Paths.
        for (path in filesObj.keys) if (!isValidPath(path)) fail(BinfireError.BAD_PATH, path)
        val lowered = HashSet<String>()
        for (path in filesObj.keys) if (!lowered.add(asciiLowercase(path))) fail(BinfireError.DUPLICATE_PATH, path)
        // 6. Each file.
        val files = LinkedHashMap<String, SiteFile>()
        var total = 0L
        for ((path, value) in filesObj) {
            val f = value.asJsonObject() ?: fail(BinfireError.BAD_MANIFEST, "file entry for $path")
            val cid = f["cid"] as? String
            if (cid == null || !Cid.isCid(cid)) fail(BinfireError.INVALID_CID, path)
            val type = f["type"] as? String
            if (type == null || !isValidType(type)) fail(BinfireError.BAD_MANIFEST, "type for $path")
            val size = f["size"].asJsonInteger()
            if (size == null || size != Cid.cidLength(cid)) fail(BinfireError.SIZE_MISMATCH, path)
            if (size > limits.maxSiteFileBytes) fail(BinfireError.TOO_LARGE, path)
            total += size
            files[path] = SiteFile(cid, type, size)
        }
        // 7. Total size.
        if (total > limits.maxSiteTotalBytes) fail(BinfireError.TOO_LARGE, "total")
        // 8. Entry.
        val entry = root["entry"] as? String
        if (entry == null || entry !in files) fail(BinfireError.MISSING_ENTRY)
        // 9. Source.
        val source = if (root.containsKey("source")) {
            root["source"].asJsonObject() ?: fail(BinfireError.BAD_MANIFEST, "source must be an object")
        } else {
            null
        }
        return SiteManifest(name, entry, files, source)
    }

    /** True when [path] is a valid manifest path (`spec/site-manifest.md`, "Paths"). */
    fun isValidPath(path: String): Boolean {
        if (Utf8.hasLoneSurrogate(path)) return false
        val bytes = Utf8.length(path)
        if (bytes < 1 || bytes > 1024) return false
        if (path.startsWith("/") || path.endsWith("/")) return false
        for (segment in path.split('/')) {
            val n = Utf8.length(segment)
            if (n < 1 || n > 255) return false
            if (segment == "." || segment == "..") return false
            for (c in segment) {
                if (c == '\\' || c == ':' || c == '?' || c == '#' || c.code <= 0x1f || c.code == 0x7f) return false
            }
        }
        return true
    }

    /** `lowercase(base32(SHA-256(ascii(manifestCid))))`: 52 characters, one DNS label. */
    fun siteId(manifestCid: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(manifestCid.toByteArray(Charsets.US_ASCII))
        return base32Lower(digest)
    }

    /** The Android WebView origin for a site: `https://<siteId>.site.binfire.invalid/`. */
    fun androidOrigin(manifestCid: String): String = "https://${siteId(manifestCid)}.site.binfire.invalid/"

    private fun isValidType(type: String): Boolean =
        type.isNotEmpty() && type.codePointCount(0, type.length) <= MAX_TYPE && type.none { it.code <= 0x20 || it.code == 0x7f }

    private fun asciiLowercase(s: String): String =
        buildString(s.length) { for (c in s) append(if (c in 'A'..'Z') c + 32 else c) }

    private const val B32 = "abcdefghijklmnopqrstuvwxyz234567"

    private fun base32Lower(bytes: ByteArray): String {
        val sb = StringBuilder((bytes.size * 8 + 4) / 5)
        var buffer = 0
        var bits = 0
        for (b in bytes) {
            buffer = (buffer shl 8) or (b.toInt() and 0xff)
            bits += 8
            while (bits >= 5) {
                sb.append(B32[(buffer ushr (bits - 5)) and 31])
                bits -= 5
            }
            buffer = buffer and ((1 shl bits) - 1)
        }
        if (bits > 0) sb.append(B32[(buffer shl (5 - bits)) and 31])
        return sb.toString()
    }
}
