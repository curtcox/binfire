package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EnvelopeFixtureTest {
    private val fixture = Fixtures.load("envelope.json")

    @Test
    fun documentTypeAndApps() {
        val cases = fixture.objects("cases")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val type = Envelope.documentType(c.bytes())
            assertEquals(c.label(), c["documentType"] as String?, type)
            val apps = type?.let { Envelope.appsForDocumentType(Fixtures.registry, it).map { a -> a.slug } } ?: emptyList()
            assertEquals(c.label(), c["apps"], apps)
        }
    }

    @Test
    fun byteOrderMarkIsDroppedLikeTextDecoder() {
        assertEquals("source", Envelope.documentType(byteArrayOf(-17, -69, -65) + "\"x\"".toByteArray()))
    }
}
