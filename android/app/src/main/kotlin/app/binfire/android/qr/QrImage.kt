package app.binfire.android.qr

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.EncodeHintType
import com.google.zxing.WriterException
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.google.zxing.qrcode.encoder.ByteMatrix
import com.google.zxing.qrcode.encoder.Encoder
import java.io.File

/**
 * QR images (`spec/qr.md`, "Rendering"): ZXing's encoder with FK's ECC rule (the
 * smallest version that fits at level L, then the strongest level that still
 * fits that version), drawn black on white with a 4-module quiet zone.
 */
object QrImage {
    const val QUIET_ZONE = 4

    /** Pixels per module in exported PNGs (the spec asks for at least 8). */
    const val EXPORT_SCALE = 10

    /** Links and `BF1:` texts are ASCII, so no ECI header is added; anything else is UTF-8. */
    private fun hintsFor(text: String): Map<EncodeHintType, Any> =
        if (text.all { it.code < 0x80 }) emptyMap() else mapOf(EncodeHintType.CHARACTER_SET to "UTF-8")

    /** A bitmap of [text] at [scale] pixels per module, quiet zone included, or `null` when it doesn't fit. */
    fun bitmap(text: String, scale: Int = 1): Bitmap? {
        val m = matrix(text) ?: return null
        val n = m.width + 2 * QUIET_ZONE
        val size = n * scale
        val pixels = IntArray(size * size) { Color.WHITE }
        for (y in 0 until m.height) for (x in 0 until m.width) {
            if (m.get(x, y).toInt() != 1) continue
            val px = (x + QUIET_ZONE) * scale
            val py = (y + QUIET_ZONE) * scale
            for (dy in 0 until scale) {
                val row = (py + dy) * size + px
                for (dx in 0 until scale) pixels[row + dx] = Color.BLACK
            }
        }
        return Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
    }

    /** The module matrix for [text], or `null` when it doesn't fit one QR code. */
    fun matrix(text: String): ByteMatrix? {
        val base = hintsFor(text)
        val smallest = try {
            Encoder.encode(text, ErrorCorrectionLevel.L, base)
        } catch (_: WriterException) {
            return null
        }
        val version = smallest.version.versionNumber
        for (level in listOf(ErrorCorrectionLevel.H, ErrorCorrectionLevel.Q, ErrorCorrectionLevel.M)) {
            try {
                return Encoder.encode(text, level, base + (EncodeHintType.QR_VERSION to version)).matrix
            } catch (_: WriterException) {
                // Doesn't fit this version at this level: try a weaker one.
            }
        }
        return smallest.matrix
    }

    /** Writes [text]'s QR as a PNG into [dir] and returns the file, or `null` when it doesn't fit. */
    fun writePng(text: String, dir: File): File? {
        val bmp = bitmap(text, EXPORT_SCALE) ?: return null
        dir.mkdirs()
        val file = File(dir, "binfire-qr.png")
        file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        return file
    }
}
