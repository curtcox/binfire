package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Covers `payloads`. `waveforms` is empty until M7. */
class AudioFixtureTest {
    private val fixture = Fixtures.load("audio.json")

    @Test
    fun payloads() {
        val links = Links(Fixtures.registry, Fixtures.config)
        val cases = fixture.objects("payloads")
        assertTrue(cases.isNotEmpty())
        for (c in cases) assertEquals(c.label(), c["ok"], Audio.audioPayloadOK(c.str("text"), links))
    }
}
