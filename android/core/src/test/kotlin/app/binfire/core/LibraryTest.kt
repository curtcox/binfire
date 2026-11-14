package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class LibraryTest {
    private val t0 = Instant.parse("2026-11-14T15:00:00.123Z")

    @Test
    fun recentIsNewestFirstAndDeduplicatedByUrl() {
        val lib = Library()
            .addRecent("https://a/#1", "python", t0)
            .addRecent("https://a/#2", "python", t0.plusSeconds(1))
            .addRecent("https://a/#1", "python", t0.plusSeconds(2))
        assertEquals(listOf("https://a/#1", "https://a/#2"), lib.recent.map { it.url })
        assertEquals("2026-11-14T15:00:02Z", lib.recent[0].visitedAt)
    }

    @Test
    fun recentIsCappedAt100() {
        var lib = Library()
        for (i in 0 until 150) lib = lib.addRecent("https://a/#$i", "python", t0.plusSeconds(i.toLong()))
        assertEquals(Library.MAX_RECENT, lib.recent.size)
        assertEquals("https://a/#149", lib.recent.first().url)
        assertEquals("https://a/#50", lib.recent.last().url)
    }

    @Test
    fun oversizedUrlIsNotAddedToRecent() {
        val big = "https://a/#" + "x".repeat(Library.MAX_RECENT_URL_BYTES.toInt())
        val lib = Library().addRecent("https://a/#1", "python", t0).addRecent(big, "python", t0)
        assertEquals(listOf("https://a/#1"), lib.recent.map { it.url })
        val atLimit = "https://a/#" + "x".repeat(Library.MAX_RECENT_URL_BYTES.toInt() - 11)
        assertEquals(atLimit, Library().addRecent(atLimit, "python", t0).recent.single().url)
        // Big URLs can still be saved by name.
        assertEquals(big, Library().save("big", big, "python", t0).saved.single().url)
    }

    @Test
    fun recentIsCappedAt16MiBDroppingOldest() {
        val mib = 1024 * 1024
        var lib = Library()
        // 20 URLs of just under 1 MiB each: only the newest 16 fit in 16 MiB.
        for (i in 0 until 20) {
            val url = "https://a/#%02d".format(i) + "x".repeat(mib - 20)
            lib = lib.addRecent(url, "python", t0.plusSeconds(i.toLong()))
        }
        assertEquals(16, lib.recent.size)
        assertTrue(lib.recent.first().url.startsWith("https://a/#19"))
        assertTrue(lib.recent.last().url.startsWith("https://a/#04"))
        assertTrue(lib.recent.sumOf { Utf8.length(it.url) } <= Library.MAX_RECENT_BYTES)
        assertEquals(lib, Library.fromJson(lib.toJson()))
    }

    @Test
    fun savedIsNewestFirstAndAllowsDuplicateUrls() {
        val lib = Library()
            .save("one", "https://a/#x", "python", t0, id = "1")
            .save("two", "https://a/#x", "python", t0.plusSeconds(5), id = "2")
        assertEquals(listOf("two", "one"), lib.saved.map { it.name })
        assertEquals("2026-11-14T15:00:05Z", lib.saved[0].savedAt)
        assertEquals(listOf("one"), lib.deleteSaved("2").saved.map { it.name })
    }

    @Test
    fun jsonRoundTrip() {
        val lib = Library()
            .save("Mine \"quoted\"", "https://a/?q=1#é", "python", t0, id = "abc")
            .addRecent("https://a/#1", "python", t0)
            .copy(sites = listOf(SiteEntry("AAAAAAAA", "Site", "2026-11-14T15:00:00Z")))
        assertEquals(lib, Library.fromJson(lib.toJson()))
        val json = Json.parse(lib.toJson()).asJsonObject()!!
        assertEquals(1.0, json["version"])
    }

    @Test
    fun badInputGivesEmptyLibraryOrSkipsEntries() {
        assertEquals(Library(), Library.fromJson("not json"))
        assertEquals(Library(), Library.fromJson("{\"version\":2,\"saved\":[]}"))
        val lib = Library.fromJson(
            "{\"version\":1,\"saved\":[{\"id\":\"1\"},{\"id\":\"2\",\"name\":\"n\",\"url\":\"u\",\"app\":\"a\",\"savedAt\":\"t\"}]," +
                "\"recent\":[{\"url\":\"u\",\"app\":\"a\"},{\"url\":\"u\",\"app\":\"a\"},7]}",
        )
        assertEquals(listOf("2"), lib.saved.map { it.id })
        assertEquals(1, lib.recent.size)
        assertTrue(lib.sites.isEmpty())
    }

    @Test
    fun withoutRunRemovesOnlyRun() {
        val cases = mapOf(
            "https://p/?run=0#x" to "https://p/#x",
            "https://p/?view=code&run=0#x" to "https://p/?view=code#x",
            "https://p/?run=0&view=a%20b" to "https://p/?view=a%20b",
            "https://p/?run=0&run=1" to "https://p/",
            "https://p/?xrun=0#run=0" to "https://p/?xrun=0#run=0",
            "https://p/#a?run=0" to "https://p/#a?run=0",
            "https://p/?r%75n=0&a=1" to "https://p/?a=1",
            "https://p/?run" to "https://p/",
        )
        for ((input, expected) in cases) assertEquals(input, expected, UrlState.withoutRun(input))
        for ((input, _) in cases) assertTrue(UrlState.classify(UrlState.withoutRun(input))!!.run)
    }
}
