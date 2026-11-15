package app.binfire.android.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import app.binfire.android.BinfireViewModel
import app.binfire.android.Sheet
import app.binfire.android.qr.QrImage
import app.binfire.core.QrPlan
import app.binfire.core.Utf8
import app.binfire.transfer.Frames
import kotlinx.coroutines.delay

/** Send → QR code (`spec/qr.md`): one QR when the link fits, else HashBin and multi-frame offers. */
@Composable
internal fun QrSheet(vm: BinfireViewModel, s: Sheet.Qr) {
    val bitmap = remember(s.text) { if (s.plan == QrPlan.TOO_LONG) null else QrImage.bitmap(s.text) }
    SheetFrame("qr.sheet", onDismiss = { vm.sheet = null }) {
        Text("QR code", style = MaterialTheme.typography.titleLarge)
        if (bitmap != null) QrBitmap(bitmap, "QR code of the link", Modifier.testTag("qr.image"))
        when (s.plan) {
            QrPlan.OK -> Unit
            QrPlan.DENSE -> Text("Dense, may be hard to scan.", Modifier.testTag("qr.note"), style = MaterialTheme.typography.bodyMedium)
            QrPlan.TOO_LONG -> Text(
                "This link is too long for one QR code (${Utf8.length(s.text)} bytes).",
                Modifier.testTag("qr.note"),
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        if (s.plan != QrPlan.OK) {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                OutlinedButton(onClick = { vm.saveQrToHashBin(s) }, modifier = Modifier.fillMaxWidth().testTag("qr.hashbin")) {
                    Text("Save to HashBin (short link)")
                }
                OutlinedButton(onClick = { vm.showQrFrames(s) }, modifier = Modifier.fillMaxWidth().testTag("qr.multi")) {
                    Text("Multi-frame QR")
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            TextButton(onClick = { vm.sheet = null }) { Text("Close") }
            if (bitmap != null) Button(onClick = { vm.exportQr(s.text) }, modifier = Modifier.testTag("qr.export")) { Text("Share") }
        }
    }
}

/** Multi-frame QR: frame `i` as `BF1:` + base64url, cycling at 5 frames per second until closed. */
@Composable
internal fun QrFramesSheet(vm: BinfireViewModel, s: Sheet.QrFrames) {
    val count = s.frames.size
    var index by remember(s) { mutableIntStateOf(0) }
    LaunchedEffect(s) {
        if (count < 2) return@LaunchedEffect
        while (true) {
            delay(200)
            index = (index + 1) % count
        }
    }
    val bitmap = remember(s, index) { QrImage.bitmap(Frames.toQrText(s.frames[index])) }
    SheetFrame("qr.multiSheet", onDismiss = { vm.sheet = null }) {
        Text("Multi-frame QR", style = MaterialTheme.typography.titleLarge)
        Text("Scan with binfire until every frame is received.", style = MaterialTheme.typography.bodySmall)
        if (bitmap != null) QrBitmap(bitmap, "Multi-frame QR code", Modifier.testTag("qr.frames"))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("${index + 1}/$count", Modifier.weight(1f).testTag("qr.frameIndex"), style = MaterialTheme.typography.bodyLarge)
            TextButton(onClick = { vm.sheet = null }) { Text("Close") }
        }
    }
}

/** Black modules on white with the quiet zone (in the bitmap), scaled without smoothing. */
@Composable
private fun QrBitmap(bitmap: Bitmap, description: String, modifier: Modifier) {
    val image = remember(bitmap) { bitmap.asImageBitmap() }
    Image(
        bitmap = image,
        contentDescription = description,
        modifier = modifier.fillMaxWidth().aspectRatio(1f),
        contentScale = ContentScale.Fit,
        filterQuality = FilterQuality.None,
    )
}
