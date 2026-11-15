package app.binfire.android.ui

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.ViewGroup
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.binfire.android.BinfireViewModel
import app.binfire.android.Sheet

@Composable
fun Sheets(vm: BinfireViewModel) {
    when (val s = vm.sheet) {
        null -> Unit
        is Sheet.Text -> TextSheet(s.text) { vm.sheet = null }
        is Sheet.Error -> SheetFrame("error.sheet", onDismiss = { vm.sheet = null }) {
            Text(s.title, style = MaterialTheme.typography.titleLarge)
            Text(s.message, Modifier.testTag("error.message"))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Button(onClick = { vm.sheet = null }, modifier = Modifier.testTag("error.ok")) { Text("OK") }
            }
        }
        is Sheet.Save -> {
            var name by remember(s) { mutableStateOf("") }
            SheetFrame("save.sheet", onDismiss = { vm.sheet = null }) {
                Text("Save state", style = MaterialTheme.typography.titleLarge)
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    modifier = Modifier.fillMaxWidth().testTag("save.name"),
                    placeholder = { Text(s.suggestedName) },
                    singleLine = true,
                )
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End)) {
                    TextButton(onClick = { vm.sheet = null }, modifier = Modifier.testTag("save.cancel")) { Text("Cancel") }
                    Button(onClick = { vm.confirmSave(s, name) }, modifier = Modifier.testTag("save.confirm")) { Text("Save") }
                }
            }
        }
        is Sheet.Loading -> SheetFrame("loading.sheet", onDismiss = { vm.cancelLoading() }) {
            Text("Opening document", style = MaterialTheme.typography.titleLarge)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CircularProgressIndicator(Modifier.size(24.dp))
                Text("Fetching and verifying…", style = MaterialTheme.typography.bodyMedium)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = { vm.cancelLoading() }) { Text("Cancel") }
            }
        }
        is Sheet.Chooser -> ChooserSheet(vm, s)
        is Sheet.LongLink -> SheetFrame("long.notice", onDismiss = { vm.sheet = null }) {
            Text("Long link copied", style = MaterialTheme.typography.titleLarge)
            Text(
                "This link is ${s.bytes} bytes. Messengers and mail apps often cut links this long." +
                    if (s.canSave) " Save to HashBin for a short link." else " The app's own Publish button can make a short link.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                TextButton(onClick = { vm.sheet = null }) { Text("Close") }
                if (s.canSave) {
                    Button(onClick = { vm.startHashBinSave(s.slug, s.url, copyLink = true) }, modifier = Modifier.testTag("long.save")) {
                        Text("Save to HashBin")
                    }
                }
            }
        }
        is Sheet.HashBinConfirm -> SheetFrame("hashbin.confirm", onDismiss = { vm.sheet = null }) {
            val size = s.bytes.size.toLong()
            val tooLarge = s.maxUploadBytes != null && size > s.maxUploadBytes
            Text("Save to HashBin", style = MaterialTheme.typography.titleLarge)
            Text("Size: ${formatBytes(size)}", Modifier.testTag("hashbin.size"), style = MaterialTheme.typography.bodyLarge)
            Text(
                when {
                    tooLarge -> "This is larger than HashBin accepts (${formatBytes(s.maxUploadBytes!!)})."
                    s.estimateCents == null -> "Estimating cost…"
                    else -> "Estimated cost: ${formatCents(s.estimateCents)}. HashBin won't charge more than that."
                },
                style = MaterialTheme.typography.bodyMedium,
            )
            Text("HashBin is pay to publish. You may be asked to sign in.", style = MaterialTheme.typography.bodySmall)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                TextButton(onClick = { vm.sheet = null }, modifier = Modifier.testTag("hashbin.cancel")) { Text("Cancel") }
                Button(onClick = { vm.confirmHashBin(s) }, enabled = !tooLarge, modifier = Modifier.testTag("hashbin.ok")) { Text("Save") }
            }
        }
        is Sheet.HashBinWorking -> SheetFrame("hashbin.working", onDismiss = {}) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                CircularProgressIndicator(Modifier.size(24.dp))
                Text(s.message, style = MaterialTheme.typography.bodyLarge)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = { vm.sheet = null }) { Text("Cancel") }
            }
        }
        is Sheet.HashBinResult -> SheetFrame("hashbin.result", onDismiss = { vm.sheet = null }) {
            Text("Saved to HashBin", style = MaterialTheme.typography.titleLarge)
            SelectionContainer {
                Text(s.link, Modifier.testTag("hashbin.link"), style = MaterialTheme.typography.bodyMedium)
            }
            if (s.copied) Text("The short link is copied.", style = MaterialTheme.typography.bodySmall)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                TextButton(onClick = { vm.sheet = null }) { Text("Done") }
                Button(onClick = {
                    vm.copy(s.link, "binfire link")
                    vm.toast("Link copied")
                }, modifier = Modifier.testTag("hashbin.copy")) { Text("Copy link") }
            }
        }
        is Sheet.PublishNote -> SheetFrame("hashbin.publishNote", onDismiss = { vm.sheet = null }) {
            Text("Use ${s.appName}'s Publish", style = MaterialTheme.typography.titleLarge)
            Text(
                "${s.reason} Use the Publish (Save to HashBin) button inside ${s.appName} to get a short link.",
                style = MaterialTheme.typography.bodyMedium,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Button(onClick = { vm.sheet = null }) { Text("OK") }
            }
        }
    }
}

@Composable
private fun ChooserSheet(vm: BinfireViewModel, s: Sheet.Chooser) {
    SheetFrame("chooser.sheet", onDismiss = { vm.sheet = null }) {
        Text("Open with", style = MaterialTheme.typography.titleLarge)
        Column(Modifier.heightIn(max = 320.dp).verticalScroll(rememberScrollState())) {
            for (app in s.apps) {
                TextButton(onClick = { vm.chooseApp(s, app) }, modifier = Modifier.fillMaxWidth().testTag("chooser.app.${app.slug}")) {
                    Text(app.name, Modifier.fillMaxWidth())
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            TextButton(onClick = {
                vm.copy(s.link, "binfire link")
                vm.toast("Link copied")
            }, modifier = Modifier.testTag("chooser.copy")) { Text("Copy link") }
            TextButton(onClick = { vm.openRaw(s) }, modifier = Modifier.testTag("chooser.raw")) { Text("Open raw") }
        }
    }
}

private fun formatBytes(n: Long): String = when {
    n < 1024 -> "$n bytes"
    n < 1024 * 1024 -> String.format(java.util.Locale.ROOT, "%.1f KiB", n / 1024.0)
    else -> String.format(java.util.Locale.ROOT, "%.1f MiB", n / (1024.0 * 1024))
}

private fun formatCents(c: Long): String = if (c < 100) "$c¢" else String.format(java.util.Locale.ROOT, "$%.2f", c / 100.0)

/** Unregistered input: shown, never navigated. "Open in browser" hands an http(s) URL to the system. */
@Composable
private fun TextSheet(text: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val isWeb = text.startsWith("https://", ignoreCase = true) || text.startsWith("http://", ignoreCase = true)
    SheetFrame("text.sheet", onDismiss = onDismiss) {
        Text("Not a binfire app", style = MaterialTheme.typography.titleLarge)
        SelectionContainer(Modifier.heightIn(max = 240.dp).verticalScroll(rememberScrollState())) {
            Text(text.take(4000), Modifier.testTag("text.value"), style = MaterialTheme.typography.bodyMedium)
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, androidx.compose.ui.Alignment.End)) {
            TextButton(onClick = {
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("text", text))
                Toast.makeText(context, "Copied", Toast.LENGTH_SHORT).show()
            }, modifier = Modifier.testTag("text.copy")) { Text("Copy") }
            if (isWeb) {
                Button(onClick = {
                    try {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(text)).addCategory(Intent.CATEGORY_BROWSABLE))
                    } catch (_: ActivityNotFoundException) {
                        Toast.makeText(context, "No browser available", Toast.LENGTH_SHORT).show()
                    }
                    onDismiss()
                }, modifier = Modifier.testTag("text.openBrowser")) { Text("Open in browser") }
            }
            TextButton(onClick = onDismiss) { Text("Close") }
        }
    }
}

@Composable
private fun SheetFrame(tag: String, onDismiss: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = MaterialTheme.shapes.large, modifier = Modifier.uiTestRoot().testTag(tag)) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
        }
    }
}

/** The `window.open` popup (FK's HashBin Publish), in its own dialog so `window.opener` keeps working. */
@Composable
fun PopupDialog(vm: BinfireViewModel) {
    val popup = vm.popup ?: return
    Dialog(onDismissRequest = { vm.closePopup() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize().padding(12.dp).uiTestRoot().testTag("popup.sheet"), shape = MaterialTheme.shapes.large) {
            Column {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    TextButton(onClick = { vm.closePopup() }) { Text("Close") }
                }
                AndroidView(
                    factory = { popup.also { (it.parent as? ViewGroup)?.removeView(it) } },
                    modifier = Modifier.fillMaxSize(),
                    onRelease = { (it.parent as? ViewGroup)?.removeView(it) },
                )
            }
        }
    }
}
