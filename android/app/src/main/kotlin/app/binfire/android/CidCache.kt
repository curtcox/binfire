package app.binfire.android

/** A small LRU of verified document bytes, bounded by total size. */
internal class CidCache(private val maxBytes: Long) {
    private val map = LinkedHashMap<String, ByteArray>(16, 0.75f, true)
    private var bytes = 0L

    @Synchronized
    fun get(cid: String): ByteArray? = map[cid]

    @Synchronized
    fun put(cid: String, value: ByteArray) {
        if (value.size > maxBytes) return
        map.remove(cid)?.let { bytes -= it.size }
        map[cid] = value
        bytes += value.size
        val it = map.entries.iterator()
        while (bytes > maxBytes && it.hasNext()) {
            val e = it.next()
            bytes -= e.value.size
            it.remove()
        }
    }
}
