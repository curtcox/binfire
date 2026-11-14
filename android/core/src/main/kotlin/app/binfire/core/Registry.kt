package app.binfire.core

/** One registered app (`spec/registry.md`). */
data class RegistryApp(
    val slug: String,
    val name: String,
    /** Origin used to build new links. */
    val canonicalOrigin: String,
    val recoveryOrigin: String,
    /** More bases that match the app. Never used to build links. */
    val otherOrigins: List<String>,
    /** Envelope keys, `"<format>:<type>"` or `"<format>"`. */
    val documentTypes: List<String>,
    val offlineManifest: String?,
    val icon: String?,
    /** Open capability flags, for example `fragmentKit` and `publish`. */
    val capabilities: Map<String, Any?>,
) {
    /** [canonicalOrigin], [recoveryOrigin], then [otherOrigins]. */
    val bases: List<String> get() = listOf(canonicalOrigin, recoveryOrigin) + otherOrigins

    /** True when the app's [capabilities] has [key] set to `true`. */
    fun hasCapability(key: String): Boolean = capabilities[key] == true
}

/** The result of [Registry.match]: the app and which of its bases matched. */
data class RegistryMatch(val app: RegistryApp, val base: String, val isCanonical: Boolean)

/** The app registry (`shared/registry/apps.json`). */
class Registry(val apps: List<RegistryApp>) {
    private class Base(val app: RegistryApp, val text: String, val url: ParsedUrl, val canonical: Boolean)

    private val bases: List<Base> = apps.flatMap { app ->
        app.bases.mapIndexed { i, b ->
            val url = ParsedUrl.parse(b) ?: throw IllegalArgumentException("registry: bad origin '$b' for ${app.slug}")
            Base(app, b, url, i == 0)
        }
    }

    init {
        val seen = HashSet<String>()
        for (a in apps) require(seen.add(a.slug)) { "registry: duplicate slug '${a.slug}'" }
    }

    /** The app with [slug], or `null`. */
    fun app(slug: String): RegistryApp? = apps.firstOrNull { it.slug == slug }

    /** The first app (in file order) that [url] belongs to, or `null` (`appForURL`). */
    fun appForUrl(url: String): RegistryApp? = match(url)?.app

    /** Like [appForUrl], also saying which base matched. */
    fun match(url: String): RegistryMatch? = ParsedUrl.parse(url)?.let { match(it) }

    internal fun match(u: ParsedUrl): RegistryMatch? {
        if (u.userinfo != null) return null
        for (b in bases) {
            val base = b.url
            if (u.scheme != base.scheme) continue
            if (u.scheme != "https" && u.scheme != "http") continue
            if (u.host != base.host || u.port != base.port) continue
            val ok = if (base.path.endsWith("/")) u.path == base.path || u.path == base.path + "index.html" else u.path == base.path
            if (ok) return RegistryMatch(b.app, b.text, b.canonical)
        }
        return null
    }

    /** Every app that lists the envelope [key], in file order (`appsForDocumentType`). */
    fun appsForDocumentType(key: String): List<RegistryApp> = apps.filter { key in it.documentTypes }

    companion object {
        private val SLUG = Regex("^[a-z0-9][a-z0-9-]*$")

        /** Parses `apps.json`. Throws [IllegalArgumentException] if it is malformed. */
        fun parse(json: String): Registry {
            val root = try {
                Json.parse(json).asJsonObject()
            } catch (e: JsonException) {
                throw IllegalArgumentException("registry is not JSON: ${e.message}")
            } ?: throw IllegalArgumentException("registry is not an object")
            require(root["format"] == "binfire-registry") { "registry: wrong format" }
            require(root["version"].asJsonInteger() == 1L) { "registry: unsupported version" }
            val list = root["apps"].asJsonArray() ?: throw IllegalArgumentException("registry: apps must be an array")
            return Registry(list.map { parseApp(it.asJsonObject() ?: throw IllegalArgumentException("registry: app must be an object")) })
        }

        private fun parseApp(o: Map<String, Any?>): RegistryApp {
            fun str(k: String) = o[k] as? String ?: throw IllegalArgumentException("registry: '$k' must be a string")
            fun strList(k: String) = (o[k].asJsonArray() ?: throw IllegalArgumentException("registry: '$k' must be an array"))
                .map { it as? String ?: throw IllegalArgumentException("registry: '$k' must hold strings") }
            val slug = str("slug")
            require(SLUG.matches(slug)) { "registry: bad slug '$slug'" }
            return RegistryApp(
                slug = slug,
                name = str("name"),
                canonicalOrigin = str("canonicalOrigin"),
                recoveryOrigin = str("recoveryOrigin"),
                otherOrigins = if (o.containsKey("otherOrigins")) strList("otherOrigins") else emptyList(),
                documentTypes = if (o.containsKey("documentTypes")) strList("documentTypes") else emptyList(),
                offlineManifest = o["offlineManifest"] as? String,
                icon = o["icon"] as? String,
                capabilities = o["capabilities"].asJsonObject() ?: emptyMap(),
            )
        }
    }
}
