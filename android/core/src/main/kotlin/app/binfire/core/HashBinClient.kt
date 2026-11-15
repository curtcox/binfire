package app.binfire.core

import java.io.IOException
import java.security.SecureRandom

/** OAuth tokens for HashBin. Serialized only into a [TokenStore]; never logged ([toString] hides them). */
class HashBinTokens(val accessToken: String, val refreshToken: String, val expiresAtMillis: Long) {
    fun toJson(): String = Json.stringify(
        linkedMapOf("access_token" to accessToken, "refresh_token" to refreshToken, "expires_at_ms" to expiresAtMillis.toDouble()),
    )

    override fun toString(): String = "HashBinTokens(expiresAt=$expiresAtMillis)"

    companion object {
        fun fromJson(text: String): HashBinTokens? {
            val o = Json.parseObject(text) ?: return null
            val a = o["access_token"] as? String ?: return null
            val r = o["refresh_token"] as? String ?: return null
            val e = o["expires_at_ms"].asJsonInteger() ?: return null
            return HashBinTokens(a, r, e)
        }
    }
}

/**
 * Where the client keeps its tokens, as one opaque string under the key
 * `hashbin.tokens`. The Android implementation encrypts it with a Keystore key.
 */
interface TokenStore {
    fun read(): String?

    /** Stores [value], or removes the entry when it is `null`. */
    fun write(value: String?)
}

/** A [TokenStore] in memory (tests, and as a fallback when no secure store exists). */
class MemoryTokenStore(private var value: String? = null) : TokenStore {
    override fun read(): String? = value
    override fun write(value: String?) {
        this.value = value
    }
}

/** No usable tokens: the user has to sign in (again). Not a spec error code. */
class SignInRequiredException : Exception("sign-in required")

/** One pending authorization: open [url] in Custom Tabs, then pass the redirect to [HashBinClient.finishSignIn]. */
class HashBinAuthRequest(val url: String, val state: String, val verifier: String)

/** The `POST /api/content` result. */
data class HashBinUpload(val cid: String, val sizeBytes: Long, val costCents: Long?, val expiresAt: String?)

/**
 * HashBin Native Save client (`spec/hashbin.md`): OAuth 2.0 with PKCE, token
 * refresh (single flight, rotating refresh tokens), revoke, and upload with a
 * cost cap. All I/O goes through [http]; every call blocks, so call it off the
 * main thread.
 */
class HashBinClient(
    api: String,
    val clientId: String,
    val redirectUri: String,
    private val http: Http,
    private val store: TokenStore,
    private val clock: () -> Long = System::currentTimeMillis,
    private val random: SecureRandom = SecureRandom(),
) {
    val api: String = api.trimEnd('/')
    private val lock = Any()

    /** True when tokens are stored (they may still need a refresh). */
    val isSignedIn: Boolean get() = tokens() != null

    private fun tokens(): HashBinTokens? = store.read()?.let { HashBinTokens.fromJson(it) }

    private fun save(t: HashBinTokens?) = store.write(t?.toJson())

    /** Builds the authorize URL with a fresh `state` and PKCE verifier (32 random bytes each, base64url). */
    fun startSignIn(): HashBinAuthRequest {
        val state = randomToken()
        val verifier = randomToken()
        val q = linkedMapOf(
            "client_id" to clientId,
            "redirect_uri" to redirectUri,
            "response_type" to "code",
            "scope" to SCOPE,
            "state" to state,
            "code_challenge" to HashBin.pkceChallenge(verifier),
            "code_challenge_method" to "S256",
        )
        val url = "$api/oauth/authorize?" + q.entries.joinToString("&") { "${encodeURIComponent(it.key)}=${encodeURIComponent(it.value)}" }
        return HashBinAuthRequest(url, state, verifier)
    }

    /**
     * Completes sign-in from the redirect [callbackUrl] (`<ownScheme>://oauth?code=…&state=…`).
     * Throws [BinfireException] `failed` (state mismatch, no code, token error),
     * `cancelled` (`error=access_denied`) or `network`.
     */
    fun finishSignIn(request: HashBinAuthRequest, callbackUrl: String) {
        val params = callbackParams(callbackUrl)
        if (params["state"] != request.state) fail(BinfireError.FAILED, "state mismatch")
        if (params["error"] == "access_denied") fail(BinfireError.CANCELLED)
        val code = params["code"]
        if (params["error"] != null || code.isNullOrEmpty()) fail(BinfireError.FAILED, params["error"] ?: "no code")
        val (status, body) = postJson(
            "/oauth/token",
            linkedMapOf(
                "grant_type" to "authorization_code",
                "client_id" to clientId,
                "code" to code,
                "redirect_uri" to redirectUri,
                "code_verifier" to request.verifier,
            ),
        )
        if (status != 200) fail(BinfireError.FAILED, "token: HTTP $status ${body["error"] ?: ""}".trim())
        save(parseTokens(body) ?: fail(BinfireError.FAILED, "token response"))
    }

    /**
     * A valid access token, refreshed when it expires within 60 s. Concurrent
     * callers share one refresh: refresh tokens rotate and work only once.
     * Throws [SignInRequiredException] when there are no tokens or the refresh
     * is rejected (`invalid_grant` or 401, which also clears the tokens).
     */
    fun accessToken(): String = synchronized(lock) {
        val t = tokens() ?: throw SignInRequiredException()
        if (clock() < t.expiresAtMillis - REFRESH_MARGIN_MS) return t.accessToken
        val (status, body) = postJson(
            "/oauth/token",
            linkedMapOf("grant_type" to "refresh_token", "client_id" to clientId, "refresh_token" to t.refreshToken),
        )
        if (status == 401 || body["error"] == "invalid_grant") {
            save(null)
            throw SignInRequiredException()
        }
        if (status != 200) fail(BinfireError.FAILED, "refresh: HTTP $status")
        val next = parseTokens(body) ?: fail(BinfireError.FAILED, "refresh response")
        save(next)
        next.accessToken
    }

    /** Signs out: clears the tokens, then revokes the refresh token (best effort, offline is fine). */
    fun signOut() {
        val t = synchronized(lock) { tokens().also { save(null) } } ?: return
        try {
            postJson("/oauth/revoke", linkedMapOf("token" to t.refreshToken, "token_type_hint" to "refresh_token"))
        } catch (_: BinfireException) {
        }
    }

    /** `GET {api}/api/config`, or `null` when it is unavailable. */
    fun fetchConfig(): Map<String, Any?>? = try {
        http.request("GET", "$api/api/config", mapOf("Accept" to "application/json"), null).use { r ->
            if (r.status != 200) null else r.readCapped(MAX_JSON_BYTES)?.let { Utf8.decodeStrict(it) }?.let { Json.parseObject(it) }
        }
    } catch (_: IOException) {
        null
    }

    /**
     * Uploads [bytes] as [contentType] with `max_cost_cents=[maxCostCents]`, then
     * checks the returned CID against the bytes sent. Throws
     * [SignInRequiredException] (no tokens, or a 401, which clears them) or
     * [BinfireException]: `insufficient-balance`, `cost-exceeded`, `too-large`,
     * `http-error`, `mismatch`, `failed` or `network`.
     */
    fun upload(bytes: ByteArray, contentType: String, maxCostCents: Long): HashBinUpload {
        val access = accessToken()
        val headers = mapOf("Authorization" to "Bearer $access", "Content-Type" to contentType, "Accept" to "application/json")
        val (status, body) = try {
            http.request("POST", "$api/api/content?max_cost_cents=$maxCostCents", headers, bytes).use<HttpResponse, Pair<Int, Map<String, Any?>>> { r ->
                r.status to (r.readCapped(MAX_JSON_BYTES)?.let { Utf8.decodeStrict(it) }?.let { Json.parseObject(it) } ?: emptyMap())
            }
        } catch (e: IOException) {
            fail(BinfireError.NETWORK, e.message)
        }
        val error = body["error"] as? String
        when {
            status == 401 -> {
                synchronized(lock) { save(null) }
                throw SignInRequiredException()
            }
            status == 402 || error == "insufficient_balance" -> fail(BinfireError.INSUFFICIENT_BALANCE)
            error == "max_cost_exceeded" || status == 409 && error == null -> fail(BinfireError.COST_EXCEEDED)
            status == 413 -> fail(BinfireError.TOO_LARGE)
            status !in 200..299 -> fail(BinfireError.HTTP_ERROR, "HTTP $status${error?.let { " $it" } ?: ""}")
        }
        val cid = body["cid"] as? String ?: fail(BinfireError.FAILED, "no cid in response")
        if (cid != Cid.computeCid(bytes)) fail(BinfireError.MISMATCH)
        return HashBinUpload(
            cid = cid,
            sizeBytes = body["size_bytes"].asJsonInteger() ?: bytes.size.toLong(),
            costCents = body["cost_cents"].asJsonInteger(),
            expiresAt = body["expires_at"] as? String,
        )
    }

    private fun postJson(path: String, payload: Map<String, Any?>): Pair<Int, Map<String, Any?>> = try {
        http.request(
            "POST",
            api + path,
            mapOf("Content-Type" to "application/json", "Accept" to "application/json"),
            Utf8.encode(Json.stringify(payload)),
        ).use<HttpResponse, Pair<Int, Map<String, Any?>>> { r ->
            r.status to (r.readCapped(MAX_JSON_BYTES)?.let { Utf8.decodeStrict(it) }?.let { Json.parseObject(it) } ?: emptyMap())
        }
    } catch (e: IOException) {
        fail(BinfireError.NETWORK, e.message)
    }

    private fun parseTokens(body: Map<String, Any?>): HashBinTokens? {
        val access = body["access_token"] as? String ?: return null
        val refresh = body["refresh_token"] as? String ?: return null
        val expiresIn = body["expires_in"].asJsonInteger() ?: DEFAULT_EXPIRES_IN_S
        return HashBinTokens(access, refresh, clock() + expiresIn * 1000)
    }

    private fun randomToken(): String = ByteArray(32).also { random.nextBytes(it) }.let { Base64Url.encode(it) }

    companion object {
        const val SCOPE = "content:write balance:read"
        const val REFRESH_MARGIN_MS = 60_000L
        const val DEFAULT_EXPIRES_IN_S = 900L
        private const val MAX_JSON_BYTES = 256L * 1024

        /** The query parameters of a redirect URL (after `?`, before `#`). */
        fun callbackParams(url: String): QueryParams {
            val query = url.substringBefore('#').substringAfter('?', "")
            return QueryParams.parse(query)
        }

        /**
         * Estimated upload cost in cents for [sizeBytes], only when `/api/config`
         * returns `price_cents_per_mb_month` (rounded up, minimum 1 cent). `null`
         * otherwise: binfire never invents a price (`spec/hashbin.md`, "Cost").
         */
        fun estimateCents(sizeBytes: Long, config: Map<String, Any?>?): Long? {
            val perMb = (config?.get("price_cents_per_mb_month") as? Double)?.takeIf { it >= 0 && it.isFinite() } ?: return null
            return maxOf(1L, Math.ceil(sizeBytes / 1_000_000.0 * perMb - 1e-9).toLong())
        }

        /** `max_upload_bytes` from `/api/config`, or `null`. */
        fun maxUploadBytes(config: Map<String, Any?>?): Long? = config?.get("max_upload_bytes").asJsonInteger()
    }
}
