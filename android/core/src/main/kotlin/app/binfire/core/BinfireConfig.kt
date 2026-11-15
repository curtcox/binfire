package app.binfire.core

/**
 * The runtime configuration (`config/binfire.config.json`, bundled as
 * `assets/binfire/binfire.config.json`). Everything that a fork may change is
 * injected through this class rather than hard-coded.
 */
data class BinfireConfig(
    val appName: String,
    /** Host of `https://` binfire links, for example `binfire.app`. */
    val linkDomain: String,
    /** Custom URL scheme for received links, for example `binfire`. */
    val scheme: String,
    val hashbin: HashBin,
    val ble: Ble,
    val limits: Limits,
    /**
     * This port's private reverse-DNS scheme (its app ID, e.g. `app.binfire.android`).
     * Several ports can claim [scheme] on one device, so binfire reaches itself through this one.
     */
    val ownScheme: String = "",
    /** OAuth redirect URI: `<ownScheme>://oauth`, as `tools/configure.mjs` writes it. */
    val oauthRedirect: String = "${ownScheme.ifEmpty { scheme }}://oauth",
) {
    /** HashBin endpoints. [content] is the CID content base, for example `https://256t.us`. */
    data class HashBin(val api: String, val content: String, val clientId: String = "", val maxCostCents: Long = DEFAULT_MAX_COST_CENTS) {
        companion object {
            /** Default Native Save cost cap, sent as `max_cost_cents` (`spec/hashbin.md`, "Cost"). */
            const val DEFAULT_MAX_COST_CENTS = 25L
        }
    }

    /** BLE GATT UUIDs (`spec/ble-gatt.md`). */
    data class Ble(val serviceUuid: String, val controlCharacteristicUuid: String, val dataCharacteristicUuid: String)

    /** Bounds on untrusted input, in bytes (or files). */
    data class Limits(
        val maxStateBytes: Long,
        val maxSiteFileBytes: Long,
        val maxSiteTotalBytes: Long,
        val maxSiteFiles: Long,
        val maxTransferBytes: Long,
    )

    companion object {
        /**
         * Parses the config JSON. Unknown fields (such as `$comment`) are ignored.
         * Throws [IllegalArgumentException] when a required field is missing.
         */
        fun parse(json: String): BinfireConfig {
            val root = try {
                Json.parse(json).asJsonObject()
            } catch (e: JsonException) {
                throw IllegalArgumentException("config is not JSON: ${e.message}")
            } ?: throw IllegalArgumentException("config is not a JSON object")
            val hashbin = root.obj("hashbin")
            val ble = root.obj("ble")
            val limits = root.obj("limits")
            val scheme = root.str("scheme")
            // The runtime config has ownScheme; the repo config has it as ids.android.
            val ownScheme = root["ownScheme"] as? String ?: root["ids"].asJsonObject()?.get("android") as? String ?: ""
            return BinfireConfig(
                appName = root.str("appName"),
                linkDomain = root.str("linkDomain"),
                scheme = scheme,
                hashbin = HashBin(
                    hashbin.str("api"),
                    hashbin.str("content"),
                    hashbin["clientId"] as? String ?: "",
                    hashbin["maxCostCents"]?.let { v -> v.asJsonInteger()?.takeIf { it >= 0 } ?: throw IllegalArgumentException("config: 'maxCostCents' must be a non-negative integer") }
                        ?: HashBin.DEFAULT_MAX_COST_CENTS,
                ),
                ble = Ble(ble.str("serviceUuid"), ble.str("controlCharacteristicUuid"), ble.str("dataCharacteristicUuid")),
                limits = Limits(
                    maxStateBytes = limits.long("maxStateBytes"),
                    maxSiteFileBytes = limits.long("maxSiteFileBytes"),
                    maxSiteTotalBytes = limits.long("maxSiteTotalBytes"),
                    maxSiteFiles = limits.long("maxSiteFiles"),
                    maxTransferBytes = limits.long("maxTransferBytes"),
                ),
                ownScheme = ownScheme,
                oauthRedirect = root["oauthRedirect"] as? String ?: "${ownScheme.ifEmpty { scheme }}://oauth",
            )
        }

        private fun Map<String, Any?>.obj(k: String) =
            this[k].asJsonObject() ?: throw IllegalArgumentException("config: '$k' must be an object")

        private fun Map<String, Any?>.str(k: String) =
            this[k] as? String ?: throw IllegalArgumentException("config: '$k' must be a string")

        private fun Map<String, Any?>.long(k: String) =
            this[k].asJsonInteger()?.takeIf { it >= 0 } ?: throw IllegalArgumentException("config: '$k' must be a non-negative integer")
    }
}
