package app.binfire.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.IOException
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class HashBinClientTest {
    class Call(val method: String, val url: String, val headers: Map<String, String>, val body: ByteArray?) {
        val json: Map<String, Any?> get() = Json.parseObject(String(body!!, Charsets.UTF_8))!!
    }

    /** A fake transport: records calls and answers with [handler]. */
    class FakeHttp(var handler: (Call) -> Pair<Int, String>) : Http {
        val calls: MutableList<Call> = Collections.synchronizedList(mutableListOf())
        override fun request(method: String, url: String, headers: Map<String, String>, body: ByteArray?): HttpResponse {
            val call = Call(method, url, headers, body)
            calls += call
            val (status, text) = handler(call)
            return HttpResponse(status, ByteArrayInputStream(text.toByteArray()))
        }
    }

    private var now = 1_000_000L
    private val store = MemoryTokenStore()

    private fun client(http: Http) = HashBinClient("https://hb.test/", "app_test", "app.binfire.android://oauth", http, store, { now })

    private fun tokens(a: String, r: String, expiresIn: Int = 900) =
        """{"access_token":"$a","refresh_token":"$r","token_type":"Bearer","expires_in":$expiresIn}"""

    private fun signedIn(access: String = "A0", refresh: String = "R0", expiresAt: Long = now + 900_000) =
        store.write(HashBinTokens(access, refresh, expiresAt).toJson())

    @Test
    fun authorizeUrlHasEveryParameter() {
        val req = client(FakeHttp { 500 to "" }).startSignIn()
        assertTrue(req.url.startsWith("https://hb.test/oauth/authorize?"))
        val q = HashBinClient.callbackParams(req.url)
        assertEquals("app_test", q["client_id"])
        assertEquals("app.binfire.android://oauth", q["redirect_uri"])
        assertEquals("code", q["response_type"])
        assertEquals("content:write balance:read", q["scope"])
        assertEquals("S256", q["code_challenge_method"])
        assertEquals(req.state, q["state"])
        assertEquals(HashBin.pkceChallenge(req.verifier), q["code_challenge"])
        // 32 random bytes in base64url: 43 characters.
        assertEquals(43, req.state.length)
        assertEquals(43, req.verifier.length)
        assertEquals(32, Base64Url.decode(req.verifier)!!.size)
    }

    @Test
    fun tokenExchangeStoresTokens() {
        val http = FakeHttp { 200 to tokens("A1", "R1") }
        val c = client(http)
        val req = c.startSignIn()
        c.finishSignIn(req, "app.binfire.android://oauth?code=C1&state=${req.state}")
        val call = http.calls.single()
        assertEquals("https://hb.test/oauth/token", call.url)
        assertEquals("application/json", call.headers["Content-Type"])
        val j = call.json
        assertEquals("authorization_code", j["grant_type"])
        assertEquals("app_test", j["client_id"])
        assertEquals("C1", j["code"])
        assertEquals("app.binfire.android://oauth", j["redirect_uri"])
        assertEquals(req.verifier, j["code_verifier"])
        assertTrue(c.isSignedIn)
        assertEquals("A1", c.accessToken())
        assertFalse("tokens must not leak through toString", HashBinTokens("A", "R", 1).toString().contains("R,"))
    }

    @Test
    fun stateMismatchFailsAndDeniedCancels() {
        val http = FakeHttp { 200 to tokens("A1", "R1") }
        val c = client(http)
        val req = c.startSignIn()
        expectCode("failed") { c.finishSignIn(req, "app.binfire.android://oauth?code=C1&state=other") }
        expectCode("failed") { c.finishSignIn(req, "app.binfire.android://oauth?code=C1") }
        expectCode("cancelled") { c.finishSignIn(req, "app.binfire.android://oauth?error=access_denied&state=${req.state}") }
        expectCode("failed") { c.finishSignIn(req, "app.binfire.android://oauth?error=server_error&state=${req.state}") }
        assertTrue(http.calls.isEmpty())
        http.handler = { 400 to """{"error":"invalid_grant"}""" }
        expectCode("failed") { c.finishSignIn(req, "app.binfire.android://oauth?code=C1&state=${req.state}") }
        assertFalse(c.isSignedIn)
    }

    @Test
    fun noTokensNeedsSignIn() {
        val http = FakeHttp { 200 to "" }
        expectSignIn { client(http).upload(byteArrayOf(1), "application/json", 5) }
        assertTrue(http.calls.isEmpty())
    }

    @Test
    fun refreshesSixtySecondsBeforeExpiryAndRotates() {
        signedIn(expiresAt = now + 61_000)
        val http = FakeHttp { 200 to tokens("A1", "R1") }
        val c = client(http)
        assertEquals("A0", c.accessToken())
        assertTrue(http.calls.isEmpty())
        now += 2_000 // 59 s left
        assertEquals("A1", c.accessToken())
        val j = http.calls.single().json
        assertEquals("refresh_token", j["grant_type"])
        assertEquals("app_test", j["client_id"])
        assertEquals("R0", j["refresh_token"])
        assertEquals("R1", HashBinTokens.fromJson(store.read()!!)!!.refreshToken)
        assertEquals(now + 900_000, HashBinTokens.fromJson(store.read()!!)!!.expiresAtMillis)
    }

    @Test
    fun concurrentCallersShareOneRefresh() {
        signedIn(expiresAt = now) // expired
        val gate = CountDownLatch(1)
        var issued = 0
        val http = FakeHttp { call ->
            gate.await(5, TimeUnit.SECONDS)
            val used = call.json["refresh_token"]
            if (used == "R0") {
                issued++
                200 to tokens("A1", "R1")
            } else {
                400 to """{"error":"invalid_grant"}"""
            }
        }
        val c = client(http)
        val pool = Executors.newFixedThreadPool(8)
        val results = (1..8).map { pool.submit<String> { c.accessToken() } }
        Thread.sleep(100)
        gate.countDown()
        val got = results.map { it.get(5, TimeUnit.SECONDS) }
        pool.shutdown()
        assertEquals(List(8) { "A1" }, got)
        assertEquals(1, http.calls.size)
        assertEquals(1, issued)
    }

    @Test
    fun invalidGrantOr401ClearsTokens() {
        for (answer in listOf(400 to """{"error":"invalid_grant"}""", 401 to "")) {
            signedIn(expiresAt = now)
            val c = client(FakeHttp { answer })
            expectSignIn { c.accessToken() }
            assertNull(store.read())
        }
    }

    @Test
    fun signOutClearsThenRevokes() {
        signedIn()
        val http = FakeHttp { 200 to "{}" }
        val c = client(http)
        c.signOut()
        assertNull(store.read())
        val call = http.calls.single()
        assertEquals("https://hb.test/oauth/revoke", call.url)
        assertEquals("R0", call.json["token"])
        assertEquals("refresh_token", call.json["token_type_hint"])
        // Offline sign-out still clears.
        signedIn()
        client(FakeHttp { throw IOException("offline") }).signOut()
        assertNull(store.read())
        // Signed out already: no request.
        val idle = FakeHttp { 200 to "{}" }
        client(idle).signOut()
        assertTrue(idle.calls.isEmpty())
    }

    @Test
    fun uploadSendsBytesAndChecksCid() {
        signedIn()
        val bytes = "print(\"hi\")".toByteArray()
        val cid = Cid.computeCid(bytes)
        val http = FakeHttp { 200 to """{"cid":"$cid","size_bytes":${bytes.size},"cost_cents":1,"expires_at":"2026-12-14T00:00:00Z"}""" }
        val r = client(http).upload(bytes, SaveBytes.Text.CONTENT_TYPE, 3)
        assertEquals(HashBinUpload(cid, bytes.size.toLong(), 1, "2026-12-14T00:00:00Z"), r)
        val call = http.calls.single()
        assertEquals("POST", call.method)
        assertEquals("https://hb.test/api/content?max_cost_cents=3", call.url)
        assertEquals("Bearer A0", call.headers["Authorization"])
        assertEquals("text/plain; charset=utf-8", call.headers["Content-Type"])
        assertTrue(call.body!!.contentEquals(bytes))
    }

    @Test
    fun uploadErrorsMap() {
        val bytes = ByteArray(100) { it.toByte() }
        val other = Cid.computeCid(ByteArray(100))
        val cases = listOf(
            (402 to """{"error":"insufficient_balance"}""") to "insufficient-balance",
            (400 to """{"error":"insufficient_balance"}""") to "insufficient-balance",
            (409 to """{"error":"max_cost_exceeded","cost_cents":9}""") to "cost-exceeded",
            (413 to """{"error":"too-large"}""") to "too-large",
            (413 to "") to "too-large",
            (500 to "oops") to "http-error",
            (200 to """{"cid":"$other"}""") to "mismatch",
            (200 to "{}") to "failed",
        )
        for ((answer, code) in cases) {
            signedIn()
            expectCode(code) { client(FakeHttp { answer }).upload(bytes, "application/json", 5) }
        }
        signedIn()
        expectCode("network") { client(FakeHttp { throw IOException("offline") }).upload(bytes, "application/json", 5) }
    }

    @Test
    fun upload401ClearsTokensAndAsksForSignIn() {
        signedIn()
        expectSignIn { client(FakeHttp { 401 to """{"error":"unauthorized"}""" }).upload(byteArrayOf(1), "application/json", 5) }
        assertNull(store.read())
    }

    @Test
    fun configAndEstimate() {
        val c = client(FakeHttp { 200 to """{"max_upload_bytes":94371840,"price_cents_per_mb_month":1}""" })
        val config = c.fetchConfig()
        assertEquals(94371840L, HashBinClient.maxUploadBytes(config))
        assertEquals(1L, HashBinClient.estimateCents(10, config))
        assertEquals(3L, HashBinClient.estimateCents(2_500_000, config))
        assertNull(client(FakeHttp { 404 to "" }).fetchConfig())
        assertNull(client(FakeHttp { throw IOException("offline") }).fetchConfig())
        // Without a price there is no estimate (the UI shows "up to maxCostCents").
        assertNull(HashBinClient.estimateCents(10, null))
        assertNull(HashBinClient.estimateCents(10, mapOf("max_upload_bytes" to 1.0)))
    }

    private fun expectCode(code: String, block: () -> Unit) {
        try {
            block()
            fail("expected $code")
        } catch (e: BinfireException) {
            assertEquals(code, e.code)
        }
    }

    private fun expectSignIn(block: () -> Unit) {
        try {
            block()
            fail("expected sign-in")
        } catch (_: SignInRequiredException) {
        }
    }
}
