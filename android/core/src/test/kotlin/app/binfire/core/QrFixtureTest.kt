package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class QrFixtureTest {
    private val fixture = Fixtures.load("qr.json")

    @Test
    fun thresholds() {
        @Suppress("UNCHECKED_CAST")
        val t = fixture["thresholds"] as Map<String, Any?>
        assertEquals(Qr.OK_MAX.toLong(), t.long("okMax"))
        assertEquals(Qr.DENSE_MAX.toLong(), t.long("denseMax"))
    }

    @Test
    fun plans() {
        val cases = fixture.objects("plans")
        assertTrue(cases.isNotEmpty())
        for (c in cases) assertEquals("${c["bytes"]}", c.str("plan"), Qr.plan(c.long("bytes")).code)
    }
}
