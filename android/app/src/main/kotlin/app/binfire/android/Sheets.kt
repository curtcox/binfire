package app.binfire.android

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import android.webkit.WebView
import app.binfire.core.QrPlan
import app.binfire.core.RegistryApp
import app.binfire.transfer.ScanSession

/** Which top-level screen is showing. */
sealed interface Screen {
    data object Library : Screen
    data class Browser(val slug: String) : Screen
}

/** The sheet (dialog) on top of the current screen, if any. */
sealed interface Sheet {
    /** Unregistered input: show it, offer Open in browser (http/https) and Copy. Never navigate. */
    data class Text(val text: String) : Sheet
    data class Error(val message: String, val title: String = "Can't open this") : Sheet
    data class Save(val slug: String, val url: String, val suggestedName: String) : Sheet

    /** Fetching and verifying a CID (`loading.sheet`). */
    data class Loading(val cid: String) : Sheet

    /**
     * No single app for a loaded CID: pick one, copy the link, or open the raw content (`chooser.sheet`).
     * [run] `false` (received content) opens the chosen app with `run=0`.
     */
    data class Chooser(val cid: String, val apps: List<RegistryApp>, val link: String, val rawUrl: String, val run: Boolean? = null) : Sheet

    /** Send → QR code (`qr.sheet`): [text] is the link shown; [slug] and [url] are the state it came from. */
    data class Qr(val slug: String, val url: String, val text: String, val plan: QrPlan) : Sheet

    /** Multi-frame QR (`qr.frames`): the chunk frames, shown in turn at 5 fps. */
    class QrFrames(val frames: List<ByteArray>) : Sheet

    /** Scan (`scan.sheet`). One [session] lives as long as the sheet; [status] is `scan.status`. */
    class Scan(val session: ScanSession) : Sheet {
        var status by mutableStateOf<String?>(null)
    }

    /** Send → Copy link made a link over 2000 bytes (`long.notice`). [canSave] when Native Save is configured. */
    data class LongLink(val slug: String, val url: String, val bytes: Long, val canSave: Boolean) : Sheet

    /**
     * Size and cost before uploading (`hashbin.confirm`). [estimateCents] only when `/api/config`
     * has a price; otherwise the sheet shows "up to [maxCostCents]". [copyLink] copies the result;
     * [toQr] shows the result as a QR (the QR sheet's Save to HashBin).
     */
    class HashBinConfirm(
        val slug: String,
        val bytes: ByteArray,
        val contentType: String,
        val copyLink: Boolean,
        val maxCostCents: Long,
        val configLoaded: Boolean = false,
        val estimateCents: Long? = null,
        val maxUploadBytes: Long? = null,
        val toQr: Boolean = false,
        val url: String = "",
    ) : Sheet {
        fun loaded(estimateCents: Long?, maxUploadBytes: Long?) =
            HashBinConfirm(slug, bytes, contentType, copyLink, maxCostCents, true, estimateCents, maxUploadBytes, toQr, url)
    }

    /** Signing in or uploading. */
    data class HashBinWorking(val message: String) : Sheet

    /** The `/c#` link (`hashbin.result`). */
    data class HashBinResult(val link: String, val copied: Boolean) : Sheet

    /** binfire can't extract this state: use the app's own Publish (`hashbin.publishNote`). */
    data class PublishNote(val appName: String, val reason: String) : Sheet
}

/** One registered app's live WebView. Kept for the life of the process so app storage and drafts persist. */
class BrowserTab(val app: RegistryApp, val webView: WebView) {
    /** The current main-frame app URL (updated on every history change, including `replaceState`). */
    var url by mutableStateOf("")
}
