package app.binfire.transfer

import app.binfire.core.Base64Url
import app.binfire.core.BinfireConfig
import app.binfire.core.BinfireException
import app.binfire.core.Cid
import app.binfire.core.Json
import app.binfire.core.asJsonInteger
import app.binfire.core.asJsonObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

class TransferFixtureTest {
    private fun prop(name: String) = File(System.getProperty(name) ?: error("system property $name not set (run through Gradle)"))

    private val fixture: Map<String, Any?> = Json.parse(File(prop("binfire.fixtures"), "transfer.json").readText()).asJsonObject()!!

    /** Repo config limits, with `maxTransferBytes` from the fixture's `limits`. */
    private val limits: BinfireConfig.Limits by lazy {
        val base = BinfireConfig.parse(prop("binfire.config").readText()).limits
        val l = fixture["limits"].asJsonObject()!!
        base.copy(maxTransferBytes = l["maxTransferBytes"].asJsonInteger()!!)
    }

    @Suppress("UNCHECKED_CAST")
    private fun objects(key: String) = fixture[key] as List<Map<String, Any?>>

    private fun b64(s: Any?): ByteArray = Base64Url.decode(s as String) ?: error("bad b64 in fixture")

    @Suppress("UNCHECKED_CAST")
    private fun frames(c: Map<String, Any?>) = (c["frames"] as List<String>).map { b64(it) }

    private inline fun expectError(label: String, code: Any?, block: () -> Unit) {
        try {
            block()
            fail("$label: expected $code")
        } catch (e: BinfireException) {
            assertEquals(label, code, e.code)
        }
    }

    @Test
    fun bundles() {
        val cases = objects("bundles")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val label = c["name"] as String
            val b = Bundle.decode(b64(c["b64"]), limits)
            val expect = c["expect"].asJsonObject()!!
            assertEquals(label, expect["kind"], b.kind.code)
            assertEquals(label, expect["url"], b.url)
            assertEquals(label, expect["cid"], b.cid)
            assertEquals(label, expect["app"], b.app)
            assertEquals(label, expect["name"], b.name)
            assertEquals(label, expect["entries"], b.entries.map { it.cid })
            assertEquals(label, b.kind == BundleKind.SITE, b.manifest != null)
            // Our own encoding of the decoded bundle must decode to the same thing.
            val again = Bundle.decode(b.encode(), limits)
            assertEquals(label, b.entries.map { it.cid }, again.entries.map { it.cid })
            assertEquals(label, b.url, again.url)
            assertEquals(label, b.name, again.name)
        }
    }

    @Test
    fun bundleErrors() {
        for (c in objects("bundleErrors")) {
            expectError(c["name"] as String, c["error"]) { Bundle.decode(b64(c["b64"]), limits) }
        }
    }

    @Test
    fun builders() {
        val doc = "{\"format\":\"x\"}".toByteArray()
        val b = Bundle.decode(Bundle.cid(doc, app = "python", name = "Doc").encode(), limits)
        assertEquals(Cid.computeCid(doc), b.cid)
        assertArrayEquals(doc, b.entries.single().bytes)
        assertEquals("https://x.example/", Bundle.decode(Bundle.url("https://x.example/").encode(), limits).url)
    }

    @Test
    fun framesEncodeExactlyAndReassembleInReverse() {
        val cases = objects("frames")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val label = c["name"] as String
            val payload = b64(c["payloadB64"])
            val expected = frames(c)
            val got = Frames.encode(payload, Frames.idFromHex(c["idHex"] as String), (c["chunkSize"] as Double).toInt())
            assertEquals(label, expected.size, got.size)
            expected.zip(got).forEach { (e, g) -> assertArrayEquals(label, e, g) }

            val r = Reassembler(limits)
            assertNull(r.payload)
            var done = false
            for ((i, f) in expected.reversed().withIndex()) {
                done = r.addBytes(f)
                assertEquals(label, i == expected.lastIndex, done)
                if (!done) assertFalse(r.missing().isEmpty())
            }
            assertTrue(label, done)
            assertTrue(r.missing().isEmpty())
            assertEquals(label, c["cid"], r.cid)
            assertArrayEquals(label, payload, r.payload)
            // Identical duplicates are ignored.
            assertTrue(r.addBytes(expected[0]))
        }
    }

    @Test
    fun missingListsIndexesNotYetReceived() {
        val payload = "0123456789".toByteArray()
        val fs = Frames.encode(payload, 7L, 2)
        val r = Reassembler(limits)
        r.addBytes(fs[3])
        r.addBytes(fs[1])
        assertEquals(listOf(0L, 2L, 4L), r.missing())
        assertEquals(listOf(0L, 2L), r.missing(max = 2))
        assertEquals(2, r.received)
    }

    @Test
    fun frameErrors() {
        for (c in objects("frameErrors")) {
            expectError(c["name"] as String, c["error"]) { Frames.decode(b64(c["b64"])) }
        }
    }

    @Test
    fun reassemblyErrors() {
        for (c in objects("reassemblyErrors")) {
            val r = Reassembler(limits)
            expectError(c["name"] as String, c["error"]) { for (f in frames(c)) r.addBytes(f) }
        }
    }

    @Test
    fun qrText() {
        val qr = fixture["qr"].asJsonObject()!!
        assertEquals(qr["prefix"], Frames.QR_PREFIX)
        val example = qr["example"] as String
        assertTrue(Frames.isQrText(example))
        val bytes = Frames.fromQrText(example)
        assertEquals(example, Frames.toQrText(bytes))
        val firstTen = frames(objects("frames").first { it["name"] == "ten bytes in chunks of four" })[0]
        assertArrayEquals(firstTen, bytes)
        expectError("not BF1", "bad-frame") { Frames.fromQrText("https://binfire.app/") }
    }
}
