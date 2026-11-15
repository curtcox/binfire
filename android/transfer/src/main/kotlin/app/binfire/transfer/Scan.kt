package app.binfire.transfer

import app.binfire.core.Base64Url
import app.binfire.core.BinfireConfig
import app.binfire.core.BinfireError
import app.binfire.core.BinfireException
import app.binfire.core.Links
import app.binfire.core.Route
import java.security.SecureRandom

/** One result of [ScanSession.accept] (`spec/qr.md`, "Scan session"). */
sealed class ScanResult {
    /** A frame of an incomplete transfer arrived. [received] counts distinct indexes. */
    data class Progress(val received: Int, val count: Long) : ScanResult()

    /** A `BF1:` text that could not be used. */
    data class FrameError(val error: BinfireError) : ScanResult()

    /** Every frame arrived: the verified payload (a bundle container). */
    class Bundle(val payload: ByteArray) : ScanResult()

    /** Not a frame: the `routeReceived` route of the text. */
    data class RouteResult(val route: Route) : ScanResult()
}

/**
 * Every decoded text of one scan sheet, live or from an image, goes through one
 * session (`spec/qr.md`). It holds at most one multi-frame transfer at a time.
 */
class ScanSession(private val links: Links, private val limits: BinfireConfig.Limits) {
    private var current: Reassembler? = null

    fun accept(text: String): ScanResult {
        val t = Links.trimAsciiWhitespace(text)
        if (!t.startsWith(Frames.QR_PREFIX)) return ScanResult.RouteResult(links.routeReceived(t))

        val rest = t.substring(Frames.QR_PREFIX.length)
        if (rest.length > MAX_FRAME_BASE64) return ScanResult.FrameError(BinfireError.BAD_FRAME)
        val bytes = Base64Url.decode(rest) ?: return ScanResult.FrameError(BinfireError.BAD_FRAME)
        val frame = try {
            Frames.decode(bytes)
        } catch (e: BinfireException) {
            return ScanResult.FrameError(e.error) // the current transfer is kept
        }

        val r = current?.takeIf { it.id == frame.id } ?: Reassembler(limits).also { current = it }
        val complete = try {
            r.add(frame)
        } catch (e: BinfireException) {
            current = null
            return ScanResult.FrameError(e.error)
        }
        if (!complete) return ScanResult.Progress(r.received, frame.count)
        current = null
        return ScanResult.Bundle(r.payload!!)
    }

    companion object {
        /** Longest base64url part of a `BF1:` text that is decoded. */
        const val MAX_FRAME_BASE64 = 2048
    }
}

/** Multi-frame QR send (`spec/qr.md`, "Multi-frame QR (send)"). */
object MultiFrameQr {
    /** The `url` bundle payload for the raw app [url]. */
    fun payload(url: String, name: String? = null): ByteArray = app.binfire.transfer.Bundle.url(url, name).encode()

    /** The frames of [payload] (chunk size 512) with transfer [id]. */
    fun frames(payload: ByteArray, id: Long = randomId()): List<ByteArray> = Frames.encode(payload, id, Frames.QR_CHUNK_SIZE)

    /** The `BF1:` texts for the raw app [url], in display order. */
    fun texts(url: String, id: Long = randomId(), name: String? = null): List<String> =
        frames(payload(url, name), id).map { Frames.toQrText(it) }

    /** 8 random bytes. */
    fun randomId(): Long = SecureRandom().nextLong()
}
