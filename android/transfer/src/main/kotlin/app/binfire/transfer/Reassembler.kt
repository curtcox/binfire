package app.binfire.transfer

import app.binfire.core.BinfireConfig
import app.binfire.core.BinfireError
import app.binfire.core.Cid

/**
 * Collects chunk frames in any order and rebuilds the payload
 * (`spec/transfer.md`, "Reassembly"). After [add] throws, discard the instance.
 */
class Reassembler(private val maxTransferBytes: Long) {
    constructor(limits: BinfireConfig.Limits) : this(limits.maxTransferBytes)

    private var first: Frame? = null
    private val chunks = HashMap<Long, Frame>()
    private var storedBytes = 0L
    private var result: ByteArray? = null

    /** Transfer id, once the first frame has arrived. */
    val id: Long? get() = first?.id

    /** Payload CID, once the first frame has arrived. */
    val cid: String? get() = first?.cid

    /** Number of frames expected, once known. */
    val count: Long? get() = first?.count

    /** Payload length, once known. */
    val total: Long? get() = first?.total

    /** Number of distinct frames received. */
    val received: Int get() = chunks.size

    /** True when every frame arrived and the payload verified. */
    val isComplete: Boolean get() = result != null

    /** The verified payload, or `null` until [isComplete]. */
    val payload: ByteArray? get() = result

    /** Decodes [bytes] as a frame and adds it. See [add]. */
    fun addBytes(bytes: ByteArray): Boolean = add(Frames.decode(bytes))

    /**
     * Adds a frame. Returns `true` when the transfer is complete. Throws
     * `BinfireException` with `too-large`, `inconsistent`, `bad-frame` or `mismatch`.
     */
    fun add(frame: Frame): Boolean {
        val f0 = first
        if (f0 == null) {
            if (frame.total > maxTransferBytes) bad(BinfireError.TOO_LARGE)
            first = frame
        } else if (frame.id != f0.id || frame.count != f0.count || frame.total != f0.total || frame.cid != f0.cid) {
            bad(BinfireError.INCONSISTENT)
        }
        val previous = chunks[frame.index]
        if (previous != null) {
            if (previous.offset != frame.offset || !previous.data.contentEquals(frame.data)) bad(BinfireError.INCONSISTENT)
            return isComplete
        }
        if (storedBytes + frame.data.size > frame.total) bad(BinfireError.BAD_FRAME, "more data than total")
        chunks[frame.index] = frame
        storedBytes += frame.data.size
        if (chunks.size.toLong() == frame.count) finish(frame.total, frame.cid)
        return isComplete
    }

    /** Indexes that have not arrived, in ascending order, at most [max] of them. */
    fun missing(max: Int = Int.MAX_VALUE): List<Long> {
        val n = count ?: return emptyList()
        val out = ArrayList<Long>()
        var i = 0L
        while (i < n && out.size < max) {
            if (i !in chunks) out.add(i)
            i++
        }
        return out
    }

    private fun finish(total: Long, cid: String) {
        val sorted = chunks.values.sortedBy { it.offset }
        var expected = 0L
        for (c in sorted) {
            if (c.offset != expected) bad(BinfireError.BAD_FRAME, "chunks do not tile the payload")
            expected += c.data.size
        }
        if (expected != total) bad(BinfireError.BAD_FRAME, "chunks do not tile the payload")
        val out = ByteArray(total.toInt())
        for (c in sorted) c.data.copyInto(out, c.offset.toInt())
        if (!Cid.verify(cid, out)) bad(BinfireError.MISMATCH)
        result = out
    }
}
