package app.binfire.android

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.content.MutableContextWrapper
import android.os.Message
import android.view.ViewGroup
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import app.binfire.core.BinfireConfig
import app.binfire.core.BinfireError
import app.binfire.core.Library
import app.binfire.core.Links
import app.binfire.core.ParsedUrl
import app.binfire.core.Registry
import app.binfire.core.RegistryApp
import app.binfire.core.Route
import app.binfire.core.StateKind
import app.binfire.core.UrlState
import java.io.File

/** Which top-level screen is showing. */
sealed interface Screen {
    data object Library : Screen
    data class Browser(val slug: String) : Screen
}

/** The sheet (dialog) on top of the current screen, if any. */
sealed interface Sheet {
    /** Unregistered input: show it, offer Open in browser (http/https) and Copy. Never navigate. */
    data class Text(val text: String) : Sheet
    data class Error(val message: String) : Sheet
    data class Save(val slug: String, val url: String, val suggestedName: String) : Sheet
}

/** One registered app's live WebView. Kept for the life of the process so app storage and drafts persist. */
class BrowserTab(val app: RegistryApp, val webView: WebView) {
    /** The current main-frame app URL (updated on every history change, including `replaceState`). */
    var url by mutableStateOf("")
}

/**
 * Holds the app state that must survive configuration changes: the library, the
 * current screen and sheet, and one WebView per opened app. WebViews are created
 * on a [MutableContextWrapper] whose base is swapped to the current Activity, so
 * they are never recreated by recomposition or rotation and never leak an Activity.
 */
class BinfireViewModel(application: Application) : AndroidViewModel(application) {
    val config: BinfireConfig = BinfireConfig.parse(asset("binfire.config.json"))
    val registry: Registry = Registry.parse(asset("apps.json"))
    val links = Links(registry, config)

    private val store = LibraryStore(File(application.filesDir, "library.json"))
    var library by mutableStateOf(store.load())
        private set

    var screen by mutableStateOf<Screen>(Screen.Library)
    var sheet by mutableStateOf<Sheet?>(null)

    /** The HashBin Publish popup (`window.open`), shown as a dialog. */
    var popup by mutableStateOf<WebView?>(null)
        private set

    val tabs = mutableStateMapOf<String, BrowserTab>()

    private val contextWrapper = MutableContextWrapper(application)
    private val hashbinHost = ParsedUrl.parse(config.hashbin.api)?.host

    private fun asset(name: String) = getApplication<Application>().assets.open("binfire/$name").bufferedReader().use { it.readText() }

    /** Points WebViews at [activity] (call from `onCreate`). */
    fun attach(activity: Activity) {
        contextWrapper.baseContext = activity
    }

    /** Points WebViews back at the application (call from `onDestroy`). */
    fun detach(activity: Activity) {
        if (contextWrapper.baseContext === activity) contextWrapper.baseContext = getApplication()
        store.flushNow()
    }

    fun flush() = store.flushNow()

    /** Routes any input text (paste, scan, tapped row, intent) and acts on the result. */
    fun open(text: String) {
        when (val r = links.route(text)) {
            is Route.OpenApp -> openApp(r.app, r.url)
            is Route.ShowText -> sheet = Sheet.Text(r.text)
            is Route.Error -> sheet = Sheet.Error(errorMessage(r.error))
            is Route.LoadCid -> sheet = Sheet.Error("Opening HashBin documents by CID is coming in M3.")
            is Route.OpenSite -> sheet = Sheet.Error("Packaged sites are coming in M6.")
        }
    }

    /** Shows [slug]'s browser, creating its WebView on first use. Keeps the current page when [url] is null. */
    fun openApp(slug: String, url: String?) {
        val app = registry.app(slug) ?: return
        val existing = tabs[slug]
        val tab = existing ?: createTab(app).also { tabs[slug] = it }
        val target = url ?: if (existing == null) app.canonicalOrigin else null
        if (target != null && target != tab.url) load(tab, target)
        screen = Screen.Browser(slug)
        sheet = null
    }

    /** Switches to an app's browser, or opens its start page. */
    fun openAppTile(app: RegistryApp) = openApp(app.slug, null)

    fun showLibrary() {
        screen = Screen.Library
    }

    fun reload(tab: BrowserTab) = tab.webView.reload()

    /** Run: reload the same URL without its `run` parameter. */
    fun run(tab: BrowserTab) = load(tab, UrlState.withoutRun(tab.url))

    fun requestSave(tab: BrowserTab) {
        sheet = Sheet.Save(tab.app.slug, tab.url, title(tab.app, tab.url))
    }

    fun confirmSave(save: Sheet.Save, name: String) {
        updateLibrary(library.save(name.trim().ifEmpty { save.suggestedName }, save.url, save.slug))
        sheet = null
    }

    fun deleteSaved(id: String) = updateLibrary(library.deleteSaved(id))

    /** The share link for the tab's current state, or null. */
    fun linkFor(tab: BrowserTab): String? = links.makeLink(tab.url)

    /** `"<App name> · <state kind>"` for titles and list rows. */
    fun title(app: RegistryApp, url: String): String {
        val state = UrlState.classify(url)?.state ?: StateKind.NONE
        return "${app.name} · ${state.code}"
    }

    fun appName(slug: String): String = registry.app(slug)?.name ?: slug

    fun closePopup() {
        popup?.let { destroy(it) }
        popup = null
    }

    private fun updateLibrary(next: Library) {
        library = next
        store.save(next)
    }

    private fun load(tab: BrowserTab, url: String) {
        val before = tab.url
        tab.url = url
        tab.webView.loadUrl(url)
        // A change of fragment only is a same-document navigation; reload so the app reads the new state.
        if (before.isNotEmpty() && before.substringBefore('#') == url.substringBefore('#') && before != url) {
            tab.webView.post { tab.webView.reload() }
        }
    }

    /** Main-frame navigation policy for an app's WebView. Returns true to cancel. */
    private fun shouldBlock(tab: BrowserTab, url: String): Boolean {
        if (url == "about:blank" || isHashBin(url)) return false
        val m = registry.match(url)
        if (m != null) {
            if (m.app.slug == tab.app.slug) return false
            openApp(m.app.slug, url)
            return true
        }
        sheet = Sheet.Text(url)
        return true
    }

    private fun isHashBin(url: String): Boolean {
        val u = ParsedUrl.parse(url) ?: return false
        return u.scheme == "https" && u.host == hashbinHost && u.port == null && u.userinfo == null
    }

    private fun onVisited(tab: BrowserTab, url: String) {
        if (registry.match(url)?.app?.slug != tab.app.slug) return
        tab.url = url
        updateLibrary(library.addRecent(url, tab.app.slug))
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configure(webView: WebView) {
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            setSupportMultipleWindows(true)
            javaScriptCanOpenWindowsAutomatically = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
    }

    private fun createTab(app: RegistryApp): BrowserTab {
        val webView = WebView(contextWrapper)
        configure(webView)
        val tab = BrowserTab(app, webView)
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                request.isForMainFrame && shouldBlock(tab, request.url.toString())

            override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) = onVisited(tab, url)
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(view: WebView, isDialog: Boolean, isUserGesture: Boolean, resultMsg: Message): Boolean =
                createPopup(tab, resultMsg)
        }
        return tab
    }

    /** Creates the popup WebView for `window.open` (FK's HashBin Publish), so `window.opener` keeps working. */
    @SuppressLint("SetJavaScriptEnabled")
    private fun createPopup(opener: BrowserTab, resultMsg: Message): Boolean {
        closePopup()
        val child = WebView(contextWrapper)
        configure(child)
        child.settings.setSupportMultipleWindows(false)
        child.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (!request.isForMainFrame) return false
                val url = request.url.toString()
                if (url == "about:blank" || isHashBin(url) || registry.match(url)?.app?.slug == opener.app.slug) return false
                sheet = Sheet.Text(url)
                return true
            }
        }
        child.webChromeClient = object : WebChromeClient() {
            override fun onCloseWindow(window: WebView) = closePopup()
        }
        val transport = resultMsg.obj as? WebView.WebViewTransport ?: return false
        transport.webView = child
        resultMsg.sendToTarget()
        popup = child
        return true
    }

    private fun destroy(webView: WebView) {
        (webView.parent as? ViewGroup)?.removeView(webView)
        webView.destroy()
    }

    override fun onCleared() {
        store.flushNow()
        closePopup()
        tabs.values.forEach { destroy(it.webView) }
        tabs.clear()
    }

    private fun errorMessage(error: BinfireError): String = when (error) {
        BinfireError.UNKNOWN_APP -> "This link is for an app binfire doesn't know."
        BinfireError.BAD_LINK -> "This binfire link is malformed."
        BinfireError.UNKNOWN_LINK -> "This binfire link isn't one binfire understands."
        BinfireError.INVALID_CID -> "This link doesn't contain a valid document ID."
        BinfireError.TOO_LARGE -> "This text is too large to open."
        else -> "This link can't be opened (${error.code})."
    }
}
