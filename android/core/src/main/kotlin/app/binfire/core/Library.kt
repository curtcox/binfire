package app.binfire.core

import java.time.Instant
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.UUID

/** A named saved state. */
data class SavedState(val id: String, val name: String, val url: String, val app: String, val savedAt: String)

/** A recently visited state. */
data class RecentEntry(val url: String, val app: String, val visitedAt: String)

/** A packaged site in the library (M6). */
data class SiteEntry(val cid: String, val name: String, val addedAt: String)

/**
 * The user's library (`spec/ui.md`, "Library data"). Immutable: every change
 * returns a new [Library]. Persist with [toJson] and [Library.fromJson].
 */
data class Library(
    /** Newest first, no cap; the same URL may be saved under several names. */
    val saved: List<SavedState> = emptyList(),
    /** Newest first, unique by URL, at most [MAX_RECENT]. */
    val recent: List<RecentEntry> = emptyList(),
    val sites: List<SiteEntry> = emptyList(),
) {
    /**
     * Records a visit: moves or adds [url] to the front of [recent], then drops the
     * oldest entries beyond [MAX_RECENT] or [MAX_RECENT_BYTES]. A URL over
     * [MAX_RECENT_URL_BYTES] is not recorded (it can still be saved by name).
     */
    fun addRecent(url: String, app: String, at: Instant = Instant.now()): Library {
        if (Utf8.length(url) > MAX_RECENT_URL_BYTES) return this
        if (recent.firstOrNull()?.let { it.url == url && it.app == app } == true) {
            return copy(recent = listOf(recent[0].copy(visitedAt = timestamp(at))) + recent.drop(1))
        }
        val rest = recent.filter { it.url != url }
        return copy(recent = capRecent(listOf(RecentEntry(url, app, timestamp(at))) + rest))
    }

    /** Adds a named save at the front of [saved]. */
    fun save(
        name: String,
        url: String,
        app: String,
        at: Instant = Instant.now(),
        id: String = UUID.randomUUID().toString(),
    ): Library = copy(saved = listOf(SavedState(id, name, url, app, timestamp(at))) + saved)

    /** Removes the saved state with [id]. */
    fun deleteSaved(id: String): Library = copy(saved = saved.filter { it.id != id })

    /** Removes [url] from [recent]. */
    fun deleteRecent(url: String): Library = copy(recent = recent.filter { it.url != url })

    /** The persisted JSON form (`version: 1`). */
    fun toJson(): String = Json.stringify(
        linkedMapOf(
            "version" to 1.0,
            "saved" to saved.map { linkedMapOf("id" to it.id, "name" to it.name, "url" to it.url, "app" to it.app, "savedAt" to it.savedAt) },
            "recent" to recent.map { linkedMapOf("url" to it.url, "app" to it.app, "visitedAt" to it.visitedAt) },
            "sites" to sites.map { linkedMapOf("cid" to it.cid, "name" to it.name, "addedAt" to it.addedAt) },
        ),
    )

    companion object {
        /** Cap on the number of [recent] entries. */
        const val MAX_RECENT = 100

        /** Cap on the total UTF-8 bytes of all [recent] URLs (16 MiB). */
        const val MAX_RECENT_BYTES: Long = 16L * 1024 * 1024

        /** URLs larger than this (1 MiB) are not added to [recent]. */
        const val MAX_RECENT_URL_BYTES: Long = 1024L * 1024

        /** Keeps the newest entries that fit both recent caps. */
        private fun capRecent(entries: List<RecentEntry>): List<RecentEntry> {
            var bytes = 0L
            val out = ArrayList<RecentEntry>(minOf(entries.size, MAX_RECENT))
            for (e in entries) {
                if (out.size == MAX_RECENT) break
                bytes += Utf8.length(e.url)
                if (bytes > MAX_RECENT_BYTES) break
                out.add(e)
            }
            return out
        }

        /** `2026-11-14T15:00:00Z`: UTC, whole seconds. */
        fun timestamp(at: Instant): String = DateTimeFormatter.ISO_INSTANT.format(at.truncatedTo(ChronoUnit.SECONDS))

        /**
         * Reads persisted JSON. Malformed entries are skipped, and unreadable or
         * unknown-version input gives an empty library, so a bad file never
         * stops the app from starting. Recents are re-deduplicated and re-capped.
         */
        fun fromJson(text: String): Library {
            val root = Json.parseObject(text) ?: return Library()
            if (root["version"].asJsonInteger() != 1L) return Library()
            fun list(key: String) = root[key].asJsonArray().orEmpty().mapNotNull { it.asJsonObject() }
            fun Map<String, Any?>.s(k: String) = this[k] as? String
            val saved = list("saved").mapNotNull { o ->
                SavedState(o.s("id") ?: return@mapNotNull null, o.s("name") ?: return@mapNotNull null, o.s("url") ?: return@mapNotNull null,
                    o.s("app") ?: return@mapNotNull null, o.s("savedAt") ?: "")
            }
            val seen = HashSet<String>()
            val recent = list("recent").mapNotNull { o ->
                val url = o.s("url") ?: return@mapNotNull null
                if (Utf8.length(url) > MAX_RECENT_URL_BYTES || !seen.add(url)) return@mapNotNull null
                RecentEntry(url, o.s("app") ?: return@mapNotNull null, o.s("visitedAt") ?: "")
            }.let { capRecent(it) }
            val sites = list("sites").mapNotNull { o ->
                SiteEntry(o.s("cid") ?: return@mapNotNull null, o.s("name") ?: "", o.s("addedAt") ?: "")
            }
            return Library(saved, recent, sites)
        }
    }
}
