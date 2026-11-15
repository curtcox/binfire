package app.binfire.android.hashbin

import android.content.Intent
import app.binfire.android.BuildConfig
import app.binfire.core.BinfireConfig

/**
 * Debug-only HashBin overrides (`spec/hashbin.md`, "Development: mock HashBin"):
 * launch intent extras `hashbinApi`, `hashbinContent` and `hashbinClientId`
 * (Maestro's `launchApp` `arguments` arrive as extras). They are kept in memory
 * for the life of the process. Release builds ignore them.
 */
object DebugOverrides {
    @Volatile private var api: String? = null
    @Volatile private var content: String? = null
    @Volatile private var clientId: String? = null

    /** Reads the extras from [intent]. Returns true when anything changed. */
    fun capture(intent: Intent?): Boolean {
        if (!BuildConfig.DEBUG || intent == null) return false
        val before = Triple(api, content, clientId)
        intent.getStringExtra("hashbinApi")?.takeIf { it.isNotBlank() }?.let { api = it.trim() }
        intent.getStringExtra("hashbinContent")?.takeIf { it.isNotBlank() }?.let { content = it.trim() }
        intent.getStringExtra("hashbinClientId")?.let { clientId = it.trim() }
        return before != Triple(api, content, clientId)
    }

    /** [h] with any overrides applied (always [h] itself in release builds). */
    fun apply(h: BinfireConfig.HashBin): BinfireConfig.HashBin {
        if (!BuildConfig.DEBUG) return h
        return h.copy(api = api ?: h.api, content = content ?: h.content, clientId = clientId ?: h.clientId)
    }
}
