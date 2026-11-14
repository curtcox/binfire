package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class SiteManifestFixtureTest {
    private val fixture = Fixtures.load("site-manifest.json")

    /** The fixture's `limits`, with any limit it doesn't name taken from the repo config. */
    private val limits: BinfireConfig.Limits by lazy {
        @Suppress("UNCHECKED_CAST")
        val l = fixture["limits"] as Map<String, Any?>
        val base = Fixtures.config.limits
        fun pick(key: String, fallback: Long) = l[key].asJsonInteger() ?: fallback
        BinfireConfig.Limits(
            maxStateBytes = pick("maxStateBytes", base.maxStateBytes),
            maxSiteFileBytes = pick("maxSiteFileBytes", base.maxSiteFileBytes),
            maxSiteTotalBytes = pick("maxSiteTotalBytes", base.maxSiteTotalBytes),
            maxSiteFiles = pick("maxSiteFiles", base.maxSiteFiles),
            maxTransferBytes = pick("maxTransferBytes", base.maxTransferBytes),
        )
    }

    @Test
    fun valid() {
        val cases = fixture.objects("valid")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val bytes = c.bytes()
            val m = Sites.validateManifest(bytes, limits)
            val cid = Cid.computeCid(bytes)
            assertEquals(c.label(), c.str("cid"), cid)
            assertEquals(c.label(), c.str("siteId"), Sites.siteId(cid))
            assertEquals(c.label(), c.str("entry"), m.entry)
            assertEquals(c.label(), c.long("files"), m.files.size.toLong())
        }
    }

    @Test
    fun invalid() {
        for (c in fixture.objects("invalid")) {
            try {
                Sites.validateManifest(c.bytes(), limits)
                fail("${c.label()} validated")
            } catch (e: BinfireException) {
                assertEquals(c.label(), c.str("error"), e.code)
            }
        }
    }

    @Test
    fun paths() {
        for (c in fixture.objects("paths")) assertEquals(c.str("path").take(60), c["ok"], Sites.isValidPath(c.str("path")))
    }

    @Test
    fun siteIds() {
        for (c in fixture.objects("siteIds")) {
            val id = Sites.siteId(c.str("cid"))
            assertEquals(c.str("siteId"), id)
            assertEquals(52, id.length)
        }
    }
}
