package app.binfire.android

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.webkit.WebChromeClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.ViewModelProvider
import app.binfire.android.hashbin.DebugOverrides
import app.binfire.android.ui.BinfireApp

class MainActivity : ComponentActivity() {
    private lateinit var vm: BinfireViewModel

    /** `<input type=file>` in a WebView (HashBin's file fallback). */
    private val fileChooser = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        vm.onFileChosen(WebChromeClient.FileChooserParams.parseResult(r.resultCode, r.data))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Debug builds only: HashBin endpoint overrides from launch extras (before the view model reads config).
        DebugOverrides.capture(intent)
        vm = ViewModelProvider(this)[BinfireViewModel::class.java]
        vm.refreshHashBin()
        vm.attach(this)
        vm.fileChooserLauncher = { i ->
            try {
                fileChooser.launch(i)
                true
            } catch (_: ActivityNotFoundException) {
                false
            }
        }
        if (savedInstanceState == null) handle(intent)
        setContent { BinfireApp(vm) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (DebugOverrides.capture(intent)) vm.refreshHashBin()
        handle(intent)
    }

    override fun onPause() {
        super.onPause()
        vm.onActivityPaused()
    }

    override fun onResume() {
        super.onResume()
        vm.onActivityResumed()
    }

    override fun onStop() {
        super.onStop()
        vm.flush()
    }

    override fun onDestroy() {
        vm.fileChooserLauncher = null
        vm.detach(this)
        super.onDestroy()
    }

    /**
     * Tapped links (App Links, custom scheme) go through `route`; shared text
     * (ACTION_SEND) through `routeShared`. Called for a cold start (not after
     * rotation or process recreation, where `savedInstanceState` is set) and for
     * every new intent, whatever is showing.
     */
    private fun handle(intent: Intent?) {
        if (intent == null || intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return
        when (intent.action) {
            Intent.ACTION_VIEW -> {
                val data = intent.data ?: return
                when {
                    data.scheme == "content" || data.scheme == "file" -> vm.openFile()
                    // HashBin sign-in redirect (<ownScheme>://oauth): never routed, never shown.
                    vm.isOAuthRedirect(data) -> intent.dataString?.let { vm.onOAuthRedirect(it) }
                    else -> intent.dataString?.let { vm.open(it) }
                }
            }
            Intent.ACTION_SEND -> {
                val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                if (!text.isNullOrBlank()) vm.openShared(text)
            }
        }
    }
}
