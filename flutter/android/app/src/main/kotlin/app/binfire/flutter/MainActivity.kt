package app.binfire.flutter

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import org.json.JSONObject
import java.net.URLEncoder

/**
 * Hands shared text (ACTION_SEND) to Dart as a `<ownScheme>://share#t=<text>`
 * link (spec/links.md), so every way in goes through app_links and route().
 * The private scheme always reaches this app, even with other ports installed.
 */
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        intent = shareAsLink(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(shareAsLink(intent) ?: intent)
    }

    private fun shareAsLink(intent: Intent?): Intent? {
        if (intent?.action != Intent.ACTION_SEND) return intent
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: return intent
        val scheme = scheme() ?: return intent
        // URLEncoder's form encoding decodes back exactly with URLSearchParams.
        val link = "$scheme://share#t=" + URLEncoder.encode(text, "UTF-8")
        return Intent(Intent.ACTION_VIEW, Uri.parse(link))
    }

    /** The private scheme (`ownScheme`) from the bundled runtime config. */
    private fun scheme(): String? = try {
        assets.open("flutter_assets/assets/binfire/binfire.config.json").use {
            JSONObject(it.readBytes().toString(Charsets.UTF_8)).optString("ownScheme").ifEmpty { null }
        }
    } catch (e: Exception) {
        null
    }
}
