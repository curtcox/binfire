package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class ConfigAndJsonTest {
    @Test
    fun bundledAssetsMatchRepoConfigAndRegistry() {
        val bundled = BinfireConfig.parse(File(Fixtures.assetsDir, "binfire.config.json").readText())
        assertEquals(Fixtures.config, bundled)
        assertEquals("binfire.app", bundled.linkDomain)
        val registry = Registry.parse(File(Fixtures.assetsDir, "apps.json").readText())
        assertEquals(Fixtures.registry.apps, registry.apps)
    }

    @Test
    fun jsonIsStrictLikeJsonParse() {
        for (bad in listOf("", "not json", "{a:1}", "{'a':1}", "[1,]", "{\"a\":1,}", "01", "1.", ".5", "+1", "\"\t\"", "nul", "[1] x", "/*c*/1", "\"\\x\"")) {
            try {
                Json.parse(bad)
                fail("accepted: $bad")
            } catch (_: JsonException) {
            }
        }
        assertEquals(mapOf("a" to 2.0), Json.parse("{\"a\":1,\"a\":2}"))
        assertEquals(listOf(1.0, -0.5, 1000.0, "\ud800", true, null), Json.parse(" [1,-0.5,1e3,\"\\ud800\",true,null] "))
        assertNull(Json.parseObject("[]"))
        assertNotNull(Json.parseObject("{}"))
        assertEquals("{\"a\":[1,\"x\\n\\u0001\",null,1.5]}", Json.stringify(mapOf("a" to listOf(1.0, "x\n\u0001", null, 1.5))))
    }
}
