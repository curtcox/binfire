package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RegistryFixtureTest {
    private val fixture = Fixtures.load("registry.json")

    @Test
    fun appForUrlMatchesEveryCase() {
        val cases = fixture.objects("cases")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            assertEquals(c.label(), c["app"] as String?, Fixtures.registry.appForUrl(c.str("url"))?.slug)
        }
    }

    @Test
    fun appsForDocumentTypeIsInFileOrder() {
        val r = Fixtures.registry
        for (app in r.apps) for (t in app.documentTypes) {
            assertEquals(r.apps.filter { t in it.documentTypes }, r.appsForDocumentType(t))
        }
    }
}
