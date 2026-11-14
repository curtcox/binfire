package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HashBinFixtureTest {
    private val fixture = Fixtures.load("hashbin.json")

    @Test
    fun pkce() {
        val cases = fixture.objects("pkce")
        assertTrue(cases.isNotEmpty())
        for (c in cases) assertEquals(c.str("challenge"), HashBin.pkceChallenge(c.str("verifier")))
    }

    @Test
    fun saveBytes() {
        val cases = fixture.objects("saveBytes")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val got = HashBin.saveBytes(c.str("url"), Fixtures.config.limits.maxStateBytes)
            val label = c.label()
            assertEquals(label, c.str("kind"), got.kind)
            when (got) {
                is SaveBytes.Text -> assertEquals(label, c["text"], got.text)
                is SaveBytes.Json -> assertEquals(label, c["text"], got.text)
                is SaveBytes.Cid -> assertEquals(label, c["cid"], got.cid)
                is SaveBytes.None -> assertEquals(label, c["error"], got.error?.code)
            }
        }
    }
}
