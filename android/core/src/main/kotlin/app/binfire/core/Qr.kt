package app.binfire.core

/** How a link can be shown as a single QR code (`spec/qr.md`). */
enum class QrPlan(val code: String) {
    /** Fits version 20-L: show it. */
    OK("ok"),

    /** Fits up to version 40-L: show it with a "dense" note, and offer alternatives. */
    DENSE("dense"),

    /** Does not fit one QR code. */
    TOO_LONG("too-long");

    override fun toString(): String = code
}

/** QR sizing rules (`spec/qr.md`). */
object Qr {
    /** Largest byte count for [QrPlan.OK]. */
    const val OK_MAX = 858

    /** Largest byte count for [QrPlan.DENSE]. */
    const val DENSE_MAX = 2953

    /** Prefix of multi-frame QR texts. */
    const val FRAME_PREFIX = "BF1:"

    /** The plan for a link of [bytes] UTF-8 bytes. */
    fun plan(bytes: Long): QrPlan = when {
        bytes <= OK_MAX -> QrPlan.OK
        bytes <= DENSE_MAX -> QrPlan.DENSE
        else -> QrPlan.TOO_LONG
    }

    /** The plan for [text]. */
    fun plan(text: String): QrPlan = plan(Utf8.length(text))
}
