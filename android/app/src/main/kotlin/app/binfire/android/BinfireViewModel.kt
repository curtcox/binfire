package app.binfire.android

import android.annotation.SuppressLint
import android.app.Activity
import android.app.Application
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.MutableContextWrapper
import android.net.Uri
import android.os.Message
import android.view.ViewGroup
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.referentialEqualityPolicy
import androidx.compose.runtime.setValue
import android.widget.Toast
import androidx.browser.customtabs.CustomTabsIntent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import app.binfire.android.hashbin.DebugOverrides
import app.binfire.android.hashbin.SecureTokenStore
import app.binfire.android.hashbin.WebDownloads
import app.binfire.core.BinfireConfig
import app.binfire.core.BinfireError
import app.binfire.core.BinfireException
import app.binfire.core.CidFetch
import app.binfire.core.CidLoader
import app.binfire.core.Envelope
import app.binfire.core.Qr
import app.binfire.core.HashBin
import app.binfire.core.HashBinAuthRequest
import app.binfire.core.HashBinClient
import app.binfire.core.Library
import app.binfire.core.Links
import app.binfire.core.ParsedUrl
import app.binfire.core.Registry
import app.binfire.core.RegistryApp
import app.binfire.core.Route
import app.binfire.core.SaveBytes
import app.binfire.core.SignInRequiredException
import app.binfire.core.StateKind
import app.binfire.core.UrlConnectionHttp
import app.binfire.core.UrlState
import app.binfire.android.qr.QrImage
import app.binfire.transfer.Bundle
import app.binfire.transfer.BundleKind
import app.binfire.transfer.MultiFrameQr
import app.binfire.transfer.ScanResult
import app.binfire.transfer.ScanSession
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Holds the app state that must survive configuration changes: the library, the
 * current screen and sheet, and one WebView per opened app. WebViews are created
 * on a [MutableContextWrapper] whose base is swapped to the current Activity, so
 * they are never recreated by recomposition or rotation and never leak an Activity.
 */
class BinfireViewModel(application: Application) : AndroidViewModel(application) {
    /** The bundled config. HashBin endpoints may be overridden in debug builds ([DebugOverrides]). */
    private val bundledConfig: BinfireConfig = BinfireConfig.parse(asset("binfire.config.json"))
    var config: BinfireConfig = effectiveConfig()
        private set
    val registry: Registry = Registry.parse(asset("apps.json"))
    var links = Links(registry, config)
        private set

    private val http = UrlConnectionHttp()
    private val tokenStore = SecureTokenStore(application)

    /** Native Save client, or null when no client ID is configured (then Save to HashBin is hidden). */
    var hashbin by mutableStateOf(makeClient())
        private set

    /** Whether HashBin tokens are stored (shows Sign out). */
    var hashbinSignedIn by mutableStateOf(false)
        private set

    /** A sign-in waiting for its `<ownScheme>://oauth` redirect. Never leaves this process. */
    private class PendingAuth(val request: HashBinAuthRequest, val onSignedIn: () -> Unit) {
        var pausedSinceLaunch = false
    }
    private var pendingAuth: PendingAuth? = null
    private var loadJob: Job? = null

    /** Set by the Activity: launches a file chooser intent (for `<input type=file>` in a WebView). */
    var fileChooserLauncher: ((Intent) -> Boolean)? = null
    private var fileCallback: ValueCallback<Array<Uri>>? = null

    private val store = LibraryStore(File(application.filesDir, "library.json"))
    var library by mutableStateOf(store.load())
        private set

    var screen by mutableStateOf<Screen>(Screen.Library)
    /** Referential equality: the async flows below check `sheet === theirSheet` to see if they were dismissed. */
    var sheet by mutableStateOf<Sheet?>(null, referentialEqualityPolicy())

    /** The HashBin Publish popup (`window.open`), shown as a dialog. */
    var popup by mutableStateOf<WebView?>(null)
        private set

    val tabs = mutableStateMapOf<String, BrowserTab>()

    private val contextWrapper = MutableContextWrapper(application)
    private val downloads = WebDownloads(application, config.limits.maxStateBytes) { activity() }

    init {
        refreshSignedIn()
    }

    private fun effectiveConfig() = bundledConfig.copy(hashbin = DebugOverrides.apply(bundledConfig.hashbin))

    private fun makeClient(): HashBinClient? {
        val h = config.hashbin
        if (h.clientId.isEmpty()) return null
        return HashBinClient(h.api, h.clientId, config.oauthRedirect, http, tokenStore)
    }

    /** Re-reads the debug overrides after a new launch intent. */
    fun refreshHashBin() {
        val next = effectiveConfig()
        if (next == config) return
        config = next
        links = Links(registry, next)
        hashbin = makeClient()
        refreshSignedIn()
    }

    private fun refreshSignedIn() {
        val client = hashbin
        if (client == null) {
            hashbinSignedIn = false
            return
        }
        viewModelScope.launch {
            hashbinSignedIn = withContext(Dispatchers.IO) { client.isSignedIn }
        }
    }

    private fun activity(): Activity? = contextWrapper.baseContext as? Activity

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

    /** Routes tapped links, typed input and library rows with `route` and acts on the result. */
    fun open(text: String) = act(links.route(text))

    /** Routes shared or pasted text with `routeShared`, which finds a link inside words. */
    fun openShared(text: String) = act(links.routeShared(text))

    /** A `.binfire` file was opened from another app. */
    fun openFile() {
        sheet = Sheet.Error("Opening .binfire files is coming in M5.")
    }

    private fun act(route: Route) {
        when (val r = route) {
            is Route.OpenApp -> openApp(r.app, r.url)
            is Route.ShowText -> sheet = Sheet.Text(r.text)
            is Route.Error -> sheet = Sheet.Error(errorMessage(r.error))
            is Route.LoadCid -> loadCid(r.cid, r.app, r.run)
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

    /** True for URLs on the HashBin API origin (`config.hashbin.api`, which a debug override may point at the mock). */
    private fun isHashBin(url: String): Boolean {
        val u = ParsedUrl.parse(url) ?: return false
        val api = ParsedUrl.parse(config.hashbin.api) ?: return false
        return u.scheme == api.scheme && u.host == api.host && u.port == api.port && u.userinfo == null
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

            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean =
                showFileChooser(callback, params)
        }
        // HashBin's file fallback (> 512 KiB) downloads a blob: the file goes to the share sheet.
        downloads.attach(webView, app)
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
                if (url == "about:blank" || isHashBin(url)) return false
                // Anything else closes the popup. A return to a registered app (HashBin's redirect
                // fallback, `#hashbin_publish=…`, state `publish`) loads in that app's browser without
                // asking; other URLs go to the show-text sheet.
                view.post { closePopup() }
                val m = registry.match(url)
                if (m != null) openApp(m.app.slug, url) else sheet = Sheet.Text(url)
                return true
            }
        }
        child.webChromeClient = object : WebChromeClient() {
            override fun onCloseWindow(window: WebView) = closePopup()

            override fun onShowFileChooser(view: WebView, callback: ValueCallback<Array<Uri>>, params: FileChooserParams): Boolean =
                showFileChooser(callback, params)
        }
        downloads.attach(child, null)
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

    // ---- CID loading (load-cid route) ----

    /**
     * `load-cid`: fetch and verify [cid], then open its app, or show the chooser.
     * [run] `false` (received content) opens the app with `run=0`.
     */
    fun loadCid(cid: String, hint: String?, run: Boolean? = null) {
        loadJob?.cancel()
        cidCache.get(cid)?.let {
            openLoaded(cid, it, hint, run)
            return
        }
        val loading = Sheet.Loading(cid)
        sheet = loading
        val fetch = CidFetch.http(config.hashbin.content, http)
        val limit = config.limits.maxStateBytes
        loadJob = viewModelScope.launch {
            val result = try {
                Result.success(withContext(Dispatchers.IO) { CidLoader.loadCid(cid, limit, fetch) })
            } catch (e: BinfireException) {
                Result.failure(e)
            }
            if (sheet !== loading) return@launch // dismissed meanwhile
            result.fold(
                onSuccess = { bytes ->
                    cidCache.put(cid, bytes)
                    openLoaded(cid, bytes, hint, run)
                },
                onFailure = { e -> sheet = Sheet.Error(cidErrorMessage((e as BinfireException).error), "Can't open this document") },
            )
        }
    }

    fun cancelLoading() {
        loadJob?.cancel()
        sheet = null
    }

    private fun openLoaded(cid: String, bytes: ByteArray, hint: String?, run: Boolean?) {
        val hinted = hint?.let { registry.app(it) }
        val apps = if (hinted != null) listOf(hinted) else Envelope.documentType(bytes)?.let { registry.appsForDocumentType(it) }.orEmpty()
        if (apps.size == 1) {
            openApp(apps[0].slug, cidUrl(apps[0], cid, run))
        } else {
            sheet = Sheet.Chooser(cid, apps.ifEmpty { registry.apps }, links.makeCidLink(cid), contentUrl(cid), run)
        }
    }

    /** `canonicalOrigin + "#" + cid`, with `run=0` for received content (`spec/links.md`, `routeReceived`). */
    private fun cidUrl(app: RegistryApp, cid: String, run: Boolean?): String {
        val url = app.canonicalOrigin + "#" + cid
        return if (run == false) UrlState.withRunZero(url) else url
    }

    private fun contentUrl(cid: String) = config.hashbin.content.trimEnd('/') + "/" + cid

    fun chooseApp(chooser: Sheet.Chooser, app: RegistryApp) = openApp(app.slug, cidUrl(app, chooser.cid, chooser.run))

    /** Open raw: the content URL in the system browser. */
    fun openRaw(chooser: Sheet.Chooser) {
        sheet = null
        openExternal(chooser.rawUrl)
    }

    fun openExternal(url: String) {
        val ctx = activity() ?: getApplication<Application>()
        try {
            ctx.startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE)
                    .apply { if (ctx !is Activity) addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) },
            )
        } catch (_: ActivityNotFoundException) {
            toast("No browser available")
        }
    }

    // ---- Send menu ----

    /** Send → Copy link. Links over 2000 bytes are still copied, and get the long-link notice. */
    fun copyLink(tab: BrowserTab) {
        val link = linkFor(tab)
        if (link == null) {
            toast("No link for this page")
            return
        }
        copy(link, "binfire link")
        if (HashBin.isLongLink(link)) {
            sheet = Sheet.LongLink(tab.app.slug, tab.url, app.binfire.core.Utf8.length(link), hashbin != null)
        } else {
            toast("Link copied")
        }
    }

    fun copy(text: String, label: String) {
        val cm = getApplication<Application>().getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        cm.setPrimaryClip(ClipData.newPlainText(label, text))
    }

    fun toast(text: String) = Toast.makeText(getApplication(), text, Toast.LENGTH_SHORT).show()

    // ---- Native Save to HashBin ----

    /** Send → Save to HashBin (or the long-link notice's Save): decides what to upload (`saveBytes`). */
    fun startHashBinSave(slug: String, url: String, copyLink: Boolean = false, toQr: Boolean = false) {
        val app = registry.app(slug) ?: return
        val client = hashbin
        if (client == null) {
            // No client ID (long-link notice only): the app's own Publish makes a short link.
            sheet = Sheet.PublishNote(app.name, "Saving to HashBin isn't set up in this build.")
            return
        }
        when (val s = HashBin.saveBytes(url, config.limits.maxStateBytes)) {
            is SaveBytes.Cid -> finishSave(slug, url, links.makeCidLink(s.cid, slug), copyLink, toQr)
            is SaveBytes.Text -> confirm(client, slug, url, s.bytes, SaveBytes.Text.CONTENT_TYPE, copyLink, toQr)
            is SaveBytes.Json -> confirm(client, slug, url, s.bytes, SaveBytes.Json.CONTENT_TYPE, copyLink, toQr)
            is SaveBytes.None -> sheet = Sheet.PublishNote(
                app.name,
                if (s.error != null) "This page's state couldn't be read (${s.error!!.code})." else "binfire can't read this kind of state without the app.",
            )
        }
    }

    private fun confirm(client: HashBinClient, slug: String, url: String, bytes: ByteArray, type: String, copyLink: Boolean, toQr: Boolean) {
        val c = Sheet.HashBinConfirm(slug, bytes, type, copyLink, config.hashbin.maxCostCents, toQr = toQr, url = url)
        sheet = c
        viewModelScope.launch {
            val cfg = withContext(Dispatchers.IO) { client.fetchConfig() }
            if (sheet === c) sheet = c.loaded(HashBinClient.estimateCents(bytes.size.toLong(), cfg), HashBinClient.maxUploadBytes(cfg))
        }
    }

    /** Save on the confirm sheet: upload, signing in first when needed. */
    fun confirmHashBin(c: Sheet.HashBinConfirm) {
        val client = hashbin ?: return
        // Always the configured cap, so HashBin refuses anything dearer (cost-exceeded).
        upload(client, c, c.maxCostCents, allowSignIn = true)
    }

    private fun upload(client: HashBinClient, c: Sheet.HashBinConfirm, maxCost: Long, allowSignIn: Boolean) {
        val working = Sheet.HashBinWorking("Saving to HashBin…")
        sheet = working
        viewModelScope.launch {
            try {
                val r = withContext(Dispatchers.IO) { client.upload(c.bytes, c.contentType, maxCost) }
                hashbinSignedIn = true
                if (sheet === working) finishSave(c.slug, c.url, links.makeCidLink(r.cid, c.slug), c.copyLink, c.toQr)
            } catch (_: SignInRequiredException) {
                hashbinSignedIn = false
                if (allowSignIn && sheet === working) signIn(client) { upload(client, c, maxCost, allowSignIn = false) }
                else if (sheet === working) sheet = Sheet.Error(saveErrorMessage(BinfireError.FAILED), "HashBin")
            } catch (e: BinfireException) {
                if (sheet === working) sheet = Sheet.Error(saveErrorMessage(e.error), "Not saved")
            }
        }
    }

    private fun finishSave(slug: String, url: String, link: String, copyLink: Boolean, toQr: Boolean) {
        if (copyLink) copy(link, "binfire link")
        // From the QR sheet: show the QR of the short /c# link.
        sheet = if (toQr) Sheet.Qr(slug, url, link, Qr.plan(link)) else Sheet.HashBinResult(link, copyLink)
    }

    /** Opens the authorize page in a Custom Tab. The redirect comes back through [onOAuthRedirect]. */
    private fun signIn(client: HashBinClient, then: () -> Unit) {
        val activity = activity()
        if (activity == null) {
            sheet = Sheet.Error(saveErrorMessage(BinfireError.FAILED), "HashBin")
            return
        }
        val request = client.startSignIn()
        pendingAuth = PendingAuth(request, then)
        sheet = Sheet.HashBinWorking("Signing in to HashBin…")
        try {
            CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(activity, Uri.parse(request.url))
        } catch (_: ActivityNotFoundException) {
            pendingAuth = null
            sheet = Sheet.Error("Signing in needs a web browser.", "HashBin")
        }
    }

    /** True when [uri] is this port's OAuth redirect (`<ownScheme>://oauth`). Checked before `route()`. */
    fun isOAuthRedirect(uri: Uri): Boolean =
        config.ownScheme.isNotEmpty() && uri.scheme.equals(config.ownScheme, ignoreCase = true) && uri.host.equals("oauth", ignoreCase = true)

    /** The redirect from the sign-in page. The state check happens in [HashBinClient.finishSignIn]. */
    fun onOAuthRedirect(url: String) {
        val pending = pendingAuth ?: return // not ours, or already handled
        val client = hashbin ?: return
        pendingAuth = null
        val working = Sheet.HashBinWorking("Signing in to HashBin…")
        sheet = working
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { client.finishSignIn(pending.request, url) }
                hashbinSignedIn = true
                if (sheet === working) pending.onSignedIn()
            } catch (e: BinfireException) {
                if (sheet !== working) return@launch
                sheet = if (e.error == BinfireError.CANCELLED) null else Sheet.Error(saveErrorMessage(e.error), "HashBin")
            }
        }
    }

    /** Activity lifecycle hooks: returning from the Custom Tab without a redirect cancels the sign-in. */
    fun onActivityPaused() {
        pendingAuth?.pausedSinceLaunch = true
    }

    fun onActivityResumed() {
        val pending = pendingAuth ?: return
        if (!pending.pausedSinceLaunch) return
        pendingAuth = null
        if (sheet is Sheet.HashBinWorking) sheet = null
    }

    /** Sign out: clears the stored tokens and revokes the refresh token. */
    fun signOutHashBin() {
        val client = hashbin ?: return
        hashbinSignedIn = false
        viewModelScope.launch {
            withContext(Dispatchers.IO) { client.signOut() }
            toast("Signed out of HashBin")
        }
    }

    // ---- QR codes (spec/qr.md) ----

    /** Send → QR code: the `makeLink` link of the tab's state, never the raw app URL. */
    fun showQr(tab: BrowserTab) {
        val link = linkFor(tab)
        if (link == null) {
            toast("No link for this page")
            return
        }
        sheet = Sheet.Qr(tab.app.slug, tab.url, link, Qr.plan(link))
    }

    /** The QR sheet's Save to HashBin: like `long.save`, then the QR of the short link. */
    fun saveQrToHashBin(s: Sheet.Qr) = startHashBinSave(s.slug, s.url, toQr = true)

    /** Multi-frame QR: a `url` bundle of the raw app URL, in 512-byte frames with a random id. */
    fun showQrFrames(s: Sheet.Qr) {
        sheet = Sheet.QrFrames(MultiFrameQr.frames(MultiFrameQr.payload(s.url)))
    }

    /** Share the QR of [text] as a PNG through the system share sheet. */
    fun exportQr(text: String) {
        val ctx = getApplication<Application>()
        val file = QrImage.writePng(text, File(ctx.cacheDir, "qr")) ?: return
        val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".files", file)
        val send = Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        send.clipData = ClipData.newRawUri("binfire QR", uri)
        val chooser = Intent.createChooser(send, "Share QR code")
        val a = activity()
        try {
            if (a != null) a.startActivity(chooser) else ctx.startActivity(chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: ActivityNotFoundException) {
            toast("No app can share this image.")
        }
    }

    /** Library → Scan. */
    fun openScan() {
        sheet = Sheet.Scan(ScanSession(links, config.limits))
    }

    /** A text decoded from the camera or an image. Ignored once the sheet has closed (live scanners repeat). */
    fun onScanned(scan: Sheet.Scan, text: String) {
        if (sheet !== scan) return
        when (val r = scan.session.accept(text)) {
            is ScanResult.Progress -> scan.status = "Receiving ${r.received} of ${r.count}"
            is ScanResult.FrameError -> scan.status = frameErrorMessage(r.error)
            is ScanResult.RouteResult -> {
                sheet = null
                act(r.route)
            }
            is ScanResult.Bundle -> {
                sheet = null
                openReceivedBundle(r.payload)
            }
        }
    }

    /** A received bundle payload (`spec/qr.md`, "Received bundles"). */
    private fun openReceivedBundle(payload: ByteArray) {
        val b = try {
            Bundle.decode(payload, config.limits)
        } catch (e: BinfireException) {
            sheet = Sheet.Error(bundleErrorMessage(e.error), "Can't open what was received")
            return
        }
        when (b.kind) {
            BundleKind.URL -> act(links.routeReceived(b.url!!))
            BundleKind.CID -> {
                // The entry is already verified: cache it, then open it like a received load-cid route.
                val cid = b.cid!!
                cidCache.put(cid, b.entries[0].bytes)
                loadCid(cid, b.app, run = false)
            }
            BundleKind.SITE -> sheet = Sheet.Error("Packaged sites arrive in a later version.", "Can't open what was received")
        }
    }

    /** Verified document bytes by CID, for offline reopen (`spec/cid.md`). In memory only until M6. */
    private val cidCache = CidCache(32L * 1024 * 1024)

    // ---- WebView file chooser (HashBin's file fallback: the user picks the saved file) ----

    private fun showFileChooser(callback: ValueCallback<Array<Uri>>, params: WebChromeClient.FileChooserParams): Boolean {
        fileCallback?.onReceiveValue(null)
        val launcher = fileChooserLauncher ?: return false
        fileCallback = callback
        val ok = try {
            launcher(params.createIntent())
        } catch (_: ActivityNotFoundException) {
            false
        }
        if (!ok) fileCallback = null
        return ok
    }

    fun onFileChosen(uris: Array<Uri>?) {
        fileCallback?.onReceiveValue(uris)
        fileCallback = null
    }
}
