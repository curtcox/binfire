package app.binfire.core

/** HashBin document envelopes (`spec/state.md`, "Envelopes"). */
object Envelope {
    /** Key returned for a document that is a JSON string. */
    const val SOURCE = "source"

    /**
     * The envelope key of a document: `"<format>:<type>"`, `"<format>"`,
     * [SOURCE] for a JSON string, or `null`.
     */
    fun documentType(bytes: ByteArray): String? {
        val text = Utf8.decodeStrict(bytes) ?: return null
        val value = try {
            Json.parse(text)
        } catch (_: JsonException) {
            return null
        }
        if (value is String) return SOURCE
        val obj = value.asJsonObject() ?: return null
        val format = obj["format"] as? String ?: return null
        val type = obj["type"] as? String
        return if (type != null) "$format:$type" else format
    }

    /** Every registry app that lists [key], in file order. */
    fun appsForDocumentType(registry: Registry, key: String): List<RegistryApp> = registry.appsForDocumentType(key)
}
