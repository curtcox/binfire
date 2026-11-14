package app.binfire.core

import java.io.File

/** Reads shared conformance fixtures straight from the repository (never copied). */
object Fixtures {
    private fun prop(name: String): File =
        File(System.getProperty(name) ?: error("system property $name not set (run through Gradle)"))

    fun load(name: String): Map<String, Any?> =
        Json.parse(File(prop("binfire.fixtures"), name).readText()).asJsonObject()!!

    val registry: Registry by lazy { Registry.parse(prop("binfire.registry").readText()) }

    val config: BinfireConfig by lazy { BinfireConfig.parse(prop("binfire.config").readText()) }

    val assetsDir: File get() = prop("binfire.assets")
}

@Suppress("UNCHECKED_CAST")
fun Map<String, Any?>.objects(key: String): List<Map<String, Any?>> = this[key] as List<Map<String, Any?>>

fun Map<String, Any?>.str(key: String): String = this[key] as String

fun Map<String, Any?>.long(key: String): Long = this[key].asJsonInteger()!!

/** The bytes of a fixture value given as `"text"` (UTF-8) or `"b64"` (base64url). */
fun Map<String, Any?>.bytes(): ByteArray = when {
    containsKey("text") -> Utf8.encode(str("text"))
    containsKey("b64") -> Base64Url.decode(str("b64")) ?: error("bad b64 in fixture")
    else -> error("fixture value has neither text nor b64")
}

/** A label for assertion messages. */
fun Map<String, Any?>.label(): String =
    (this["name"] ?: this["why"] ?: this["url"] ?: this["input"] ?: this["text"] ?: this["cid"] ?: this.toString()).toString().take(120)
