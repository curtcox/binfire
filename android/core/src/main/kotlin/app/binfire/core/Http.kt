package app.binfire.core

import java.io.ByteArrayOutputStream
import java.io.Closeable
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

/** An HTTP response whose [body] is read as a stream. Close it when done. */
class HttpResponse(val status: Int, val body: InputStream, private val onClose: () -> Unit = {}) : Closeable {
    override fun close() {
        try {
            body.close()
        } catch (_: IOException) {
        }
        onClose()
    }

    /** Reads at most [cap] bytes of [body]; returns `null` when more arrive. */
    fun readCapped(cap: Long): ByteArray? = readCapped(body, cap)
}

/**
 * The HTTP abstraction used by core (CID loading and the HashBin client), so
 * unit tests can drive it with a fake. Implementations throw [IOException] for
 * network failures (DNS, TLS, offline, timeout) and return every HTTP status,
 * including errors, as a response.
 */
fun interface Http {
    fun request(method: String, url: String, headers: Map<String, String>, body: ByteArray?): HttpResponse
}

/** Reads at most [cap] bytes from [input]; returns `null` when more than [cap] bytes arrive. */
fun readCapped(input: InputStream, cap: Long): ByteArray? {
    val out = ByteArrayOutputStream(minOf(cap, 64 * 1024L).toInt().coerceAtLeast(16))
    val buf = ByteArray(16 * 1024)
    var total = 0L
    while (true) {
        val n = input.read(buf)
        if (n < 0) break
        total += n
        if (total > cap) return null
        out.write(buf, 0, n)
    }
    return out.toByteArray()
}

/**
 * [Http] over `java.net.HttpURLConnection`: no cookies (no `CookieHandler` is
 * consulted unless the process installs one, and binfire does not), no cache, no
 * `Referer`, and 30 s connect and read timeouts (`spec/cid.md`).
 */
class UrlConnectionHttp(private val timeoutMs: Int = 30_000) : Http {
    override fun request(method: String, url: String, headers: Map<String, String>, body: ByteArray?): HttpResponse {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = method
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.useCaches = false
            conn.instanceFollowRedirects = method == "GET"
            for ((k, v) in headers) conn.setRequestProperty(k, v)
            if (body != null) {
                conn.doOutput = true
                conn.setFixedLengthStreamingMode(body.size)
                conn.outputStream.use { it.write(body) }
            }
            val status = conn.responseCode
            val stream = (if (status >= 400) conn.errorStream else conn.inputStream) ?: java.io.ByteArrayInputStream(ByteArray(0))
            return HttpResponse(status, stream) { conn.disconnect() }
        } catch (e: IOException) {
            conn.disconnect()
            throw e
        } catch (e: RuntimeException) {
            // Malformed URLs and similar surface as network failures to callers.
            conn.disconnect()
            throw IOException(e)
        }
    }
}
