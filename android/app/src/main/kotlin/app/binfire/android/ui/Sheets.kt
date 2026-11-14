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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
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
            Text("Can't open this", style = MaterialTheme.typography.titleLarge)
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
    }
}

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
