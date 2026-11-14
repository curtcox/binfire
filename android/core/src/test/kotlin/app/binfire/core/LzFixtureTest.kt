package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class LzFixtureTest {
    private val fixture = Fixtures.load("lz.json")

    @Test
    fun roundtrip() {
        val cases = fixture.objects("roundtrip")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            assertEquals(c.label(), c.str("compressed"), Lz.compress(c.str("text")))
            assertEquals(c.label(), c.str("text"), Lz.decompress(c.str("compressed")))
        }
    }

    @Test
    fun invalid() {
        for (c in fixture.objects("invalid")) {
            try {
                Lz.decompress(c.str("compressed"), c.long("limit"))
                fail("${c.label()} decoded")
            } catch (e: BinfireException) {
                assertEquals(c.label(), c.str("error"), e.code)
            }
        }
    }

    @Test
    fun spaces() {
        for (c in fixture.objects("spaces")) assertEquals(c.label(), c.str("text"), Lz.decompress(c.str("compressed")))
    }

    /** Reference outputs from tools/vendor/lz-string-1.5.0.mjs for JS-specific edge cases. */
    @Test
    fun javascriptEdgeCases() {
        val cases = mapOf(
            "__proto__" to "PrAOCcHsBdJI",
            "__proto____proto__ x __proto__ __proto__" to "PrAOCcHsBdJEIzsABADxQqsSbN5IA",
            "a\ud800b\udc00c" to "IaAA2EaAA7DGQ",
            "constructor toString constructor" to "MYewdgzgLgTgrsKIYAIkGVYEswHMWiSwJIxA",
        )
        for ((text, compressed) in cases) {
            assertEquals(text, compressed, Lz.compress(text))
            assertEquals(text, text, Lz.decompress(compressed))
        }
    }
}
