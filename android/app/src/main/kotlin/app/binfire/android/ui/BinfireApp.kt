package app.binfire.android.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import app.binfire.android.BinfireViewModel
import app.binfire.android.Screen

/** Exposes `Modifier.testTag` values as resource IDs for Maestro (`spec/ui.md`). Apply in every window root. */
@OptIn(ExperimentalComposeUiApi::class)
fun Modifier.uiTestRoot(): Modifier = semantics { testTagsAsResourceId = true }

@Composable
fun BinfireApp(vm: BinfireViewModel) {
    MaterialTheme {
        Surface(Modifier.fillMaxSize().uiTestRoot()) {
            Box(Modifier.fillMaxSize().safeDrawingPadding()) {
                when (val s = vm.screen) {
                    Screen.Library -> LibraryScreen(vm)
                    is Screen.Browser -> {
                        val tab = vm.tabs[s.slug]
                        if (tab == null) {
                            vm.showLibrary()
                        } else {
                            BackHandler {
                                if (tab.webView.canGoBack()) tab.webView.goBack() else vm.showLibrary()
                            }
                            BrowserScreen(vm, tab)
                        }
                    }
                }
            }
            Sheets(vm)
            PopupDialog(vm)
        }
    }
}
