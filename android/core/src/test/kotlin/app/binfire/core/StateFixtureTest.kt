package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StateFixtureTest {
    private val fixture = Fixtures.load("state.json")

    @Test
    fun classifyEveryCase() {
        val cases = fixture.objects("cases")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val url = c.str("url")
            val label = c["source"]?.toString() ?: url.take(120)
            assertEquals(label, c.str("app"), Fixtures.registry.appForUrl(url)?.slug)
            val s = UrlState.classify(url)!!
            assertEquals(label, c.str("state"), s.state.code)
            assertEquals(label, c["run"], s.run)
            assertEquals(label, c["view"], s.view)
            assertEquals(label, c["cid"], s.cid)
            assertEquals(label, c.long("bytes"), s.bytes)
        }
    }
}
