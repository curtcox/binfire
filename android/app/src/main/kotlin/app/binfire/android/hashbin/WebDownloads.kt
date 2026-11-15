package app.binfire.android.hashbin

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Base64
import android.webkit.URLUtil
import android.webkit.WebView
import android.widget.Toast
import androidx.core.content.FileProvider
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import app.binfire.core.Json
import app.binfire.core.ParsedUrl
import app.binfire.core.RegistryApp
import java.io.File

/**
 * WebView downloads (`spec/hashbin.md`, "File fallback"): FK's HashBin SDK saves
 * documents over 512 KiB with `<a download>` on a `blob:` URL, then sends the
 * user to HashBin to pick that file. Native code cannot read `blob:` URLs, so
 * the page reads the blob itself and posts it back through a web message
 * listener that only the app's own origins can reach. The file goes to the
 * share sheet (Files, Drive, …). Plain http(s) downloads open in the browser.
 */
class WebDownloads(
    private val context: Context,
    private val maxBytes: Long,
    private val activity: () -> Activity?,
) {
    /** Adds the download listener to [webView]. [app] (null for popups) limits who may post blob contents. */
    fun attach(webView: WebView, app: RegistryApp?) {
        val origins = app?.bases?.mapNotNull { origin(it) }?.toSet().orEmpty()
        val canReadBlobs = origins.isNotEmpty() && WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)
        if (canReadBlobs) {
            WebViewCompat.addWebMessageListener(webView, BRIDGE, origins) { _, message, _, isMainFrame, _ ->
                if (isMainFrame) message.data?.let { receive(it) }
            }
        }
        webView.setDownloadListener { url, _, contentDisposition, mimeType, _ ->
            when {
                url.startsWith("blob:") && canReadBlobs -> {
                    val name = URLUtil.guessFileName(url, contentDisposition, mimeType).takeIf { !it.startsWith("downloadfile") }
                        ?: "hashbin-document"
                    webView.evaluateJavascript(readBlobScript(url, name), null)
                }
                url.startsWith("https://") || url.startsWith("http://") -> openInBrowser(url)
                else -> toast("This download can't be saved here.")
            }
        }
    }

    private fun origin(base: String): String? {
        val u = ParsedUrl.parse(base) ?: return null
        if (u.scheme != "https" && u.scheme != "http") return null
        return "${u.scheme}://${u.host}" + (u.port?.let { ":$it" } ?: "")
    }

    private fun readBlobScript(url: String, name: String): String {
        val args = Json.stringify(listOf(url, name, maxBytes.toDouble()))
        return """(function(a){var u=a[0],n=a[1],max=a[2];
fetch(u).then(function(r){return r.blob();}).then(function(b){
if(b.size>max){$BRIDGE.postMessage(JSON.stringify({error:'too-large'}));return;}
var f=new FileReader();f.onload=function(){$BRIDGE.postMessage(JSON.stringify({name:n,type:b.type,data:f.result}));};
f.onerror=function(){$BRIDGE.postMessage(JSON.stringify({error:'read'}));};f.readAsDataURL(b);
}).catch(function(e){$BRIDGE.postMessage(JSON.stringify({error:String(e)}));});})($args);"""
    }

    private fun receive(text: String) {
        val o = Json.parseObject(text) ?: return
        if (o["error"] != null) {
            toast(if (o["error"] == "too-large") "This file is too large to save." else "The download failed.")
            return
        }
        val dataUrl = o["data"] as? String ?: return
        val comma = dataUrl.indexOf(',')
        if (!dataUrl.startsWith("data:") || comma < 0 || !dataUrl.substring(0, comma).endsWith(";base64")) return
        val bytes = try {
            Base64.decode(dataUrl.substring(comma + 1), Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            return
        }
        if (bytes.size > maxBytes) return
        val name = sanitize(o["name"] as? String ?: "hashbin-document")
        val type = (o["type"] as? String)?.takeIf { it.isNotBlank() } ?: "application/octet-stream"
        val dir = File(context.cacheDir, "downloads").apply { mkdirs() }
        val file = File(dir, name)
        file.writeBytes(bytes)
        share(FileProvider.getUriForFile(context, context.packageName + ".files", file), type)
    }

    private fun sanitize(name: String): String =
        name.replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001f]"), "_").trim().trimStart('.').take(120).ifEmpty { "hashbin-document" }

    private fun share(uri: Uri, type: String) {
        val send = Intent(Intent.ACTION_SEND).setType(type).putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val chooser = Intent.createChooser(send, "Save the file for HashBin")
        val a = activity()
        try {
            if (a != null) a.startActivity(chooser) else context.startActivity(chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
            toast("No app can save this file.")
        }
    }

    private fun openInBrowser(url: String) {
        val a = activity() ?: return
        try {
            a.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE))
        } catch (_: ActivityNotFoundException) {
            toast("No browser available")
        }
    }

    private fun toast(text: String) = Toast.makeText(context, text, Toast.LENGTH_SHORT).show()

    private companion object {
        const val BRIDGE = "binfireDownload"
    }
}
