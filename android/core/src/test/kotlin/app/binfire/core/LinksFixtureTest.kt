package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LinksFixtureTest {
    private val fixture = Fixtures.load("links.json")

    private val links: Links by lazy {
        @Suppress("UNCHECKED_CAST")
        val c = fixture["config"] as Map<String, Any?>
        val base = Fixtures.config
        Links(
            Fixtures.registry,
            base.copy(linkDomain = c.str("linkDomain"), scheme = c.str("scheme"), hashbin = base.hashbin.copy(content = c.str("content"))),
        )
    }

    @Test
    fun route() {
        val cases = fixture.objects("route")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            @Suppress("UNCHECKED_CAST")
            val expect = c["expect"] as Map<String, Any?>
            val got = links.route(c.str("input")).toJson()
            for ((k, v) in expect) assertEquals("${c.label()} [$k]", v, got[k])
        }
    }

    @Test
    fun makeLink() {
        for (c in fixture.objects("makeLink")) assertEquals(c.label(), c["link"] as String?, links.makeLink(c.str("url")))
        assertNull(links.makeLink("https://example.com/"))
    }

    @Test
    fun withRunZero() {
        for (c in fixture.objects("withRunZero")) assertEquals(c.label(), c.str("result"), UrlState.withRunZero(c.str("url")))
    }

    @Test
    fun makeCidLink() {
        for (c in fixture.objects("makeCIDLink")) assertEquals(c.str("link"), links.makeCidLink(c.str("cid"), c["app"] as String?))
    }

    @Test
    fun makeSiteLink() {
        for (c in fixture.objects("makeSiteLink")) assertEquals(c.str("link"), links.makeSiteLink(c.str("cid")))
    }

    @Test
    fun encodeURIComponent() {
        for (c in fixture.objects("encodeURIComponent")) assertEquals(c.str("encoded"), Links.encodeURIComponent(c.str("text")))
    }

    @Test
    fun oversizedInputIsRejected() {
        val big = "x".repeat((Fixtures.config.limits.maxStateBytes + 4097).toInt())
        assertEquals(Route.Error(BinfireError.TOO_LARGE), links.route(big))
    }
}
