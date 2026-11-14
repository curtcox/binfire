package app.binfire.core

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CidFixtureTest {
    private val fixture = Fixtures.load("cid.json")

    @Test
    fun compute() {
        val cases = fixture.objects("compute") + fixture.objects("reference")
        assertTrue(cases.size > 80)
        for (c in cases) {
            val bytes = c.bytes()
            assertEquals(c.label(), c.str("cid"), Cid.computeCid(bytes))
            assertTrue(Cid.verify(c.str("cid"), bytes))
            assertEquals(bytes.size.toLong(), Cid.cidLength(c.str("cid")))
            if (bytes.size <= 64) assertArrayEquals(bytes, Cid.inlineContent(c.str("cid")))
        }
    }

    @Test
    fun valid() {
        @Suppress("UNCHECKED_CAST")
        for (cid in fixture["valid"] as List<String>) assertTrue(cid, Cid.isCid(cid))
    }

    @Test
    fun invalid() {
        for (c in fixture.objects("invalid")) {
            assertFalse(c.str("why"), Cid.isCid(c.str("cid")))
            assertNull(Cid.inlineContent(c.str("cid")))
        }
    }

    @Test
    fun verify() {
        for (c in fixture.objects("verify")) {
            assertEquals(c.label(), c["ok"] as Boolean, Cid.verify(c.str("cid"), c.bytes()))
        }
    }

    @Test
    fun lengths() {
        for (c in fixture.objects("lengths")) {
            assertEquals(c.long("length"), Cid.cidLength(c.str("cid")))
            assertEquals(c.long("length") <= 64, Cid.isInline(c.str("cid")))
        }
    }

    @Test
    fun base64UrlIsStrict() {
        assertNull(Base64Url.decode("QQ=="))
        assertNull(Base64Url.decode("QR"))
        assertNull(Base64Url.decode("Q"))
        assertNull(Base64Url.decode("Q+"))
        assertArrayEquals(byteArrayOf(0x41), Base64Url.decode("QQ"))
        assertEquals("_-8", Base64Url.encode(byteArrayOf(-1, -17)))
        assertArrayEquals(byteArrayOf(-1, -17), Base64Url.decode("_-8"))
    }
}
