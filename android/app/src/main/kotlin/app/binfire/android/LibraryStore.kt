package app.binfire.android

import android.os.Handler
import android.os.Looper
import app.binfire.core.Library
import java.io.File
import java.util.concurrent.Executors

/**
 * Persists the [Library] as JSON in app-private storage (`files/library.json`).
 * Writes are debounced, because FK apps call `replaceState` on every edit, and
 * done off the main thread with an atomic rename.
 */
class LibraryStore(private val file: File) {
    private val main = Handler(Looper.getMainLooper())
    private val io = Executors.newSingleThreadExecutor()
    private var pending: Library? = null
    private val flush = Runnable { pending?.let { write(it) }; pending = null }

    /** Reads the library, or an empty one when there is no readable file. */
    fun load(): Library = try {
        if (file.exists()) Library.fromJson(file.readText()) else Library()
    } catch (_: Exception) {
        Library()
    }

    /** Schedules a write of [library]. */
    fun save(library: Library) {
        pending = library
        main.removeCallbacks(flush)
        main.postDelayed(flush, DEBOUNCE_MS)
    }

    /** Writes any pending change now (call when the app goes to the background). */
    fun flushNow() {
        main.removeCallbacks(flush)
        flush.run()
    }

    private fun write(library: Library) {
        val json = library.toJson()
        io.execute {
            try {
                val tmp = File(file.parentFile, file.name + ".tmp")
                tmp.writeText(json)
                if (!tmp.renameTo(file)) {
                    file.writeText(json)
                    tmp.delete()
                }
            } catch (_: Exception) {
                // A failed write keeps the previous file; the next change retries.
            }
        }
    }

    private companion object {
        const val DEBOUNCE_MS = 500L
    }
}
