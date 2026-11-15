package app.binfire.android.ui

import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.binfire.android.BinfireViewModel

private val TABS = listOf("apps" to "Apps", "saved" to "Saved", "recent" to "Recent")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(vm: BinfireViewModel) {
    var input by rememberSaveable { mutableStateOf("") }
    var tabIndex by rememberSaveable { mutableIntStateOf(0) }
    val context = LocalContext.current
    fun go() {
        if (input.isNotBlank()) vm.open(input)
    }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                modifier = Modifier.weight(1f).testTag("open.input"),
                placeholder = { Text("Paste a link or CID") },
                singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go),
                keyboardActions = KeyboardActions(onGo = { go() }),
            )
            Spacer(Modifier.width(8.dp))
            Button(onClick = { go() }, modifier = Modifier.testTag("open.go")) { Text("Open") }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            OutlinedButton(onClick = { vm.openScan() }, modifier = Modifier.testTag("open.scan")) { Text("Scan") }
            OutlinedButton(
                onClick = {
                    val clip = (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).primaryClip
                    val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
                    if (!text.isNullOrBlank()) {
                        input = text
                        vm.openShared(text)
                    }
                },
                modifier = Modifier.testTag("open.paste"),
            ) { Text("Paste") }
        }
        PrimaryTabRow(selectedTabIndex = tabIndex, modifier = Modifier.padding(top = 8.dp)) {
            TABS.forEachIndexed { i, (id, label) ->
                Tab(selected = tabIndex == i, onClick = { tabIndex = i }, modifier = Modifier.testTag("tab.$id"), text = { Text(label) })
            }
        }
        when (TABS[tabIndex].first) {
            "apps" -> AppsTab(vm)
            "saved" -> SavedTab(vm)
            else -> RecentTab(vm)
        }
    }
}

@Composable
private fun AppsTab(vm: BinfireViewModel) {
    LazyVerticalGrid(
        columns = GridCells.Adaptive(minSize = 140.dp),
        contentPadding = PaddingValues(12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(vm.registry.apps, key = { it.slug }) { app ->
            Card(onClick = { vm.openAppTile(app) }, modifier = Modifier.testTag("app.${app.slug}")) {
                Column(Modifier.padding(12.dp)) {
                    Text(app.name, style = MaterialTheme.typography.titleMedium)
                    val open = vm.tabs.containsKey(app.slug)
                    Text(if (open) "Open" else app.canonicalOrigin.removePrefix("https://"), style = MaterialTheme.typography.bodySmall,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun SavedTab(vm: BinfireViewModel) {
    val saved = vm.library.saved
    if (saved.isEmpty()) {
        Empty("Saved states appear here. Use Save in a browser.")
        return
    }
    LazyColumn {
        itemsIndexed(saved, key = { _, s -> s.id }) { i, s ->
            Row2(
                title = s.name,
                subtitle = "${vm.appName(s.app)} · ${s.savedAt}",
                preview = s.url,
                tag = "saved.row.$i",
                onClick = { vm.open(s.url) },
                onLongClick = { vm.deleteSaved(s.id) },
                longClickLabel = "Delete",
            )
        }
    }
}

@Composable
private fun RecentTab(vm: BinfireViewModel) {
    val recent = vm.library.recent
    if (recent.isEmpty()) {
        Empty("Recently visited states appear here.")
        return
    }
    LazyColumn {
        itemsIndexed(recent, key = { _, r -> r.url }) { i, r ->
            val app = vm.registry.app(r.app)
            Row2(
                title = (app?.let { vm.title(it, r.url) } ?: r.app),
                subtitle = r.visitedAt,
                preview = r.url,
                tag = "recent.row.$i",
                onClick = { vm.open(r.url) },
            )
        }
    }
}

/**
 * A library row. Its children's semantics are replaced by one label (title and
 * subtitle), so the row's ID carries its text for UI tests and screen readers.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Row2(
    title: String,
    subtitle: String,
    preview: String,
    tag: String,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)? = null,
    longClickLabel: String? = null,
) {
    val modifier = Modifier
        .combinedClickable(onClick = onClick, onLongClick = onLongClick, onLongClickLabel = longClickLabel)
        .clearAndSetSemantics {
            testTag = tag
            contentDescription = "$title, $subtitle"
            onClick { onClick(); true }
            if (onLongClick != null) onLongClick(longClickLabel) { onLongClick(); true }
        }
    Column(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(subtitle, style = MaterialTheme.typography.bodySmall)
        // URLs can be megabytes: show a short preview only.
        Text(preview.take(200), style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
    HorizontalDivider()
}

@Composable
private fun Empty(text: String) {
    Text(text, Modifier.padding(24.dp), style = MaterialTheme.typography.bodyMedium)
}
