package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BleFixtureTest {
    private val fixture = Fixtures.load("ble.json")

    @Test
    fun confirmationCodes() {
        val cases = fixture.objects("codes")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val code = Ble.confirmationCode(Hex.decode(c.str("senderNonceHex")), Hex.decode(c.str("receiverNonceHex")))
            assertEquals(c.str("code"), code)
        }
    }
}
