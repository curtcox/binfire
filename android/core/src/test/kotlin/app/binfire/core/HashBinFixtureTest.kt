package app.binfire.core

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.IOException

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

    @Test
    fun loadCid() {
        val cases = fixture.objects("fetch")
        assertTrue(cases.size >= 10)
        for (c in cases) {
            val label = c.label()
            var calls = 0
            val fetch = CidFetch { cid ->
                calls++
                assertEquals(label, c.str("cid"), cid)
                HttpResponse(c.long("status").toInt(), ByteArrayInputStream(Base64Url.decode(c.str("bodyB64"))!!))
            }
            try {
                val bytes = CidLoader.loadCid(c.str("cid"), c.long("limit"), fetch)
                assertEquals(label, true, c["ok"])
                assertArrayEquals(label, Base64Url.decode(c.str("bodyB64")), bytes)
            } catch (e: BinfireException) {
                assertEquals(label, c["error"], e.code)
            }
            assertEquals(label, if (c["request"] == true) 1 else 0, calls)
        }
    }

    @Test
    fun loadCidNetworkFailure() {
        val cid = fixture.objects("fetch").first { it["name"] == "verified body" }.str("cid")
        try {
            CidLoader.loadCid(cid, 1L shl 20, CidFetch { throw IOException("offline") })
            fail("expected network")
        } catch (e: BinfireException) {
            assertEquals("network", e.code)
        }
    }

    @Test
    fun longLinkThreshold() {
        assertEquals(fixture.long("longLinkBytes"), HashBin.LONG_LINK_BYTES)
        assertFalse(HashBin.isLongLink("a".repeat(2000)))
        assertTrue(HashBin.isLongLink("a".repeat(2001)))
        assertTrue(HashBin.isLongLink("\u00e9".repeat(1001)))
    }
}
