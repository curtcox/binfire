package app.binfire.android.ui

import android.view.ViewGroup
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import app.binfire.android.BinfireViewModel
import app.binfire.android.BrowserTab
import app.binfire.core.UrlState

@Composable
fun BrowserScreen(vm: BinfireViewModel, tab: BrowserTab) {
    val runOff = remember(tab.url) { UrlState.classify(tab.url)?.run == false }
    var menu by remember { mutableStateOf(false) }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { vm.showLibrary() }, modifier = Modifier.testTag("web.library")) { Text("Library") }
            Text(
                vm.title(tab.app, tab.url),
                modifier = Modifier.weight(1f).testTag("web.title"),
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            TextButton(onClick = { vm.reload(tab) }, modifier = Modifier.testTag("web.reload")) { Text("Reload") }
            TextButton(onClick = { vm.requestSave(tab) }, modifier = Modifier.testTag("web.save")) { Text("Save") }
            Box {
                TextButton(onClick = { menu = true }, modifier = Modifier.testTag("web.send")) { Text("Send") }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, modifier = Modifier.uiTestRoot()) {
                    DropdownMenuItem(
                        text = { Text("Copy link") },
                        onClick = {
                            menu = false
                            vm.copyLink(tab)
                        },
                        modifier = Modifier.testTag("send.copy"),
                    )
                    DropdownMenuItem(
                        text = { Text("QR code") },
                        onClick = {
                            menu = false
                            vm.showQr(tab)
                        },
                        modifier = Modifier.testTag("send.qr"),
                    )
                    if (vm.hashbin != null) {
                        DropdownMenuItem(
                            text = { Text("Save to HashBin") },
                            onClick = {
                                menu = false
                                vm.startHashBinSave(tab.app.slug, tab.url)
                            },
                            modifier = Modifier.testTag("send.hashbin"),
                        )
                        if (vm.hashbinSignedIn) {
                            DropdownMenuItem(
                                text = { Text("Sign out of HashBin") },
                                onClick = {
                                    menu = false
                                    vm.signOutHashBin()
                                },
                                modifier = Modifier.testTag("hashbin.signOut"),
                            )
                        }
                    }
                }
            }
        }
        if (runOff) {
            Row(
                Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.secondaryContainer).padding(horizontal = 12.dp, vertical = 4.dp)
                    .testTag("run.banner"),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Code won't run until you choose Run.", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                Button(onClick = { vm.run(tab) }, modifier = Modifier.testTag("run.go")) { Text("Run") }
            }
        }
        Box(Modifier.fillMaxWidth().weight(1f).testTag("web.view")) {
            AndroidView(
                // The WebView lives in the view model; re-host it rather than recreate it.
                factory = { tab.webView.also { (it.parent as? ViewGroup)?.removeView(it) } },
                modifier = Modifier.fillMaxSize(),
                onRelease = { (it.parent as? ViewGroup)?.removeView(it) },
            )
        }
    }
}
