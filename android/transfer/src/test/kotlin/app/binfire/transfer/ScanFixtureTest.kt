package app.binfire.transfer

import app.binfire.core.Base64Url
import app.binfire.core.BinfireConfig
import app.binfire.core.Cid
import app.binfire.core.Json
import app.binfire.core.Links
import app.binfire.core.Registry
import app.binfire.core.asJsonInteger
import app.binfire.core.asJsonObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/** `qr.json` `scans` and the multi-frame send framing (`spec/qr.md`). */
class ScanFixtureTest {
    private fun prop(name: String) = File(System.getProperty(name) ?: error("system property $name not set (run through Gradle)"))

    private val fixture: Map<String, Any?> = Json.parse(File(prop("binfire.fixtures"), "qr.json").readText()).asJsonObject()!!
    private val config = BinfireConfig.parse(prop("binfire.config").readText())
    private val links = Links(Registry.parse(prop("binfire.registry").readText()), config)

    @Suppress("UNCHECKED_CAST")
    private fun objects(key: String) = fixture[key] as List<Map<String, Any?>>

    @Test
    fun scans() {
        val cases = objects("scans")
        assertTrue(cases.isNotEmpty())
        for (c in cases) {
            val name = c["name"] as String
            val session = ScanSession(links, config.limits)
            @Suppress("UNCHECKED_CAST")
            val texts = c["texts"] as List<String>
            @Suppress("UNCHECKED_CAST")
            val results = c["results"] as List<Map<String, Any?>>
            assertEquals(name, results.size, texts.size)
            texts.forEachIndexed { i, text ->
                val label = "$name #$i"
                val got = session.accept(text)
                val want = results[i]
                when (want["kind"]) {
                    "progress" -> {
                        if (got !is ScanResult.Progress) fail("$label: expected progress, got $got")
                        got as ScanResult.Progress
                        want["received"]?.let { assertEquals(label, it.asJsonInteger(), got.received.toLong()) }
                        want["count"]?.let { assertEquals(label, it.asJsonInteger(), got.count) }
                    }
                    "frame-error" -> {
                        if (got !is ScanResult.FrameError) fail("$label: expected frame-error, got $got")
                        want["error"]?.let { assertEquals(label, it, (got as ScanResult.FrameError).error.code) }
                    }
                    "bundle" -> {
                        if (got !is ScanResult.Bundle) fail("$label: expected bundle, got $got")
                        want["payloadB64"]?.let { assertArrayEquals(label, Base64Url.decode(it as String), (got as ScanResult.Bundle).payload) }
                    }
                    "route" -> {
                        if (got !is ScanResult.RouteResult) fail("$label: expected route, got $got")
                        val route = (got as ScanResult.RouteResult).route.toJson()
                        for ((k, v) in want["route"].asJsonObject()!!) assertEquals("$label [$k]", v, route[k])
                    }
                    else -> fail("$label: unknown kind ${want["kind"]}")
                }
            }
        }
    }

    /**
     * The three-frame scan case is a `url` bundle framed like a send. The fixture
     * uses a small chunk size (frame 1's offset) to get three frames.
     */
    @Test
    fun multiFrameSendReproducesFixtureFrames() {
        val case = objects("scans").first { it["name"] == "three-frame url bundle" }
        @Suppress("UNCHECKED_CAST")
        val payload = Base64Url.decode((case["results"] as List<Map<String, Any?>>).last()["payloadB64"] as String)!!
        val bundle = Bundle.decode(payload, config.limits)
        assertEquals(BundleKind.URL, bundle.kind)
        assertArrayEquals(payload, MultiFrameQr.payload(bundle.url!!, bundle.name))

        val images = objects("images").filter { (it["file"] as String).startsWith("frame-") }.sortedBy { it["file"] as String }
        val expected = images.map { it["text"] as String }
        assertEquals(3, expected.size)
        val id = Frames.decode(Frames.fromQrText(expected[0])).id
        val chunk = Frames.decode(Frames.fromQrText(expected[1])).offset.toInt()
        assertEquals(expected, Frames.encode(MultiFrameQr.payload(bundle.url!!, bundle.name), id, chunk).map { Frames.toQrText(it) })
        // The real send uses 512-byte chunks: this payload fits one frame.
        val sent = MultiFrameQr.texts(bundle.url!!, id, bundle.name)
        assertEquals(1, sent.size)
        assertArrayEquals(payload, Frames.decode(Frames.fromQrText(sent[0])).data)
    }

    @Test
    fun sendThenScanRoundTrips() {
        val url = "https://python.hashbin.page/#v1." + "x".repeat(3000)
        val texts = MultiFrameQr.texts(url)
        assertTrue(texts.size > 1)
        val session = ScanSession(links, config.limits)
        // Out of order, with a repeat, as a live scanner would see them.
        val order = texts.indices.reversed() + 0
        var last: ScanResult? = null
        for (i in order) last = session.accept(texts[i])
        // The repeat of a finished transfer starts a new one.
        assertTrue(last is ScanResult.Progress)
        val again = ScanSession(links, config.limits)
        val results = texts.map { again.accept(it) }
        val bundle = Bundle.decode((results.last() as ScanResult.Bundle).payload, config.limits)
        assertEquals(url, bundle.url)
    }

    @Test
    fun longestFrameTextFitsVersion20L() {
        val max = fixture["maxFrameText"].asJsonInteger()!!
        val payload = ByteArray(2000) { it.toByte() }
        assertEquals(94, Cid.computeCid(payload).length)
        val texts = MultiFrameQr.frames(payload).map { Frames.toQrText(it) }
        assertEquals(max, texts.maxOf { it.length }.toLong())
        assertTrue(texts.all { app.binfire.core.Qr.plan(it) == app.binfire.core.QrPlan.OK })
    }
}
