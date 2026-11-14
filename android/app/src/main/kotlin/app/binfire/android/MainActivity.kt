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

    /** Text that reaches binfire from outside goes through `route` like everything else. */
    private fun handle(intent: Intent?) {
        val text = when (intent?.action) {
            Intent.ACTION_VIEW -> intent.dataString
            Intent.ACTION_SEND -> intent.getStringExtra(Intent.EXTRA_TEXT)
            else -> null
        }
        if (!text.isNullOrBlank()) vm.open(text)
    }
}
