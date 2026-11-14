package app.binfire.android

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.lifecycle.ViewModelProvider
import app.binfire.android.ui.BinfireApp

class MainActivity : ComponentActivity() {
    private lateinit var vm: BinfireViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        vm = ViewModelProvider(this)[BinfireViewModel::class.java]
        vm.attach(this)
        if (savedInstanceState == null) handle(intent)
        setContent { BinfireApp(vm) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    override fun onStop() {
        super.onStop()
        vm.flush()
    }

    override fun onDestroy() {
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
                if (data.scheme == "content" || data.scheme == "file") vm.openFile()
                else intent.dataString?.let { vm.open(it) }
            }
            Intent.ACTION_SEND -> {
                val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                if (!text.isNullOrBlank()) vm.openShared(text)
            }
        }
    }
}
