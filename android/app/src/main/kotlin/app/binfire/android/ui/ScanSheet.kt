package app.binfire.android.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.ImageAnalysis
import androidx.camera.mlkit.vision.MlKitAnalyzer
import androidx.camera.view.CameraController
import androidx.camera.view.LifecycleCameraController
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.binfire.android.BinfireViewModel
import app.binfire.android.Sheet
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.io.IOException

/** The camera permission prompt text (`spec/qr.md`). Android shows it before asking. */
const val CAMERA_USAGE = "binfire uses the camera to scan QR codes."

/**
 * Scan sheet (`spec/qr.md`): live ML Kit scanning through CameraX, and "From image"
 * through the system photo picker (no camera permission). Every decoded text goes
 * to the sheet's one ScanSession, through [BinfireViewModel.onScanned].
 */
@Composable
internal fun ScanSheet(vm: BinfireViewModel, s: Sheet.Scan) {
    val context = LocalContext.current
    val hasCamera = remember { context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY) }
    var granted by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    var denied by remember { mutableStateOf(false) }
    var cameraFailed by remember(s) { mutableStateOf(false) }
    val scanner = remember(s) {
        BarcodeScanning.getClient(BarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build())
    }
    DisposableEffect(scanner) { onDispose { scanner.close() } }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
        granted = ok
        denied = !ok
    }
    LaunchedEffect(s) { if (hasCamera && !granted) permission.launch(Manifest.permission.CAMERA) }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scanImage(context, scanner, uri, onText = { vm.onScanned(s, it) }, onStatus = { s.status = it })
    }

    val cameraMessage = when {
        !hasCamera || cameraFailed -> "Camera unavailable"
        denied -> "Camera permission denied"
        !granted -> CAMERA_USAGE
        else -> null
    }
    SheetFrame("scan.sheet", onDismiss = { vm.sheet = null }) {
        Text("Scan a QR code", style = MaterialTheme.typography.titleLarge)
        if (cameraMessage == null) {
            CameraPreview(
                scanner,
                onText = { vm.onScanned(s, it) },
                onError = { cameraFailed = true },
                modifier = Modifier.fillMaxWidth().aspectRatio(1f).testTag("scan.camera"),
            )
        }
        Text(
            s.status ?: cameraMessage ?: "Point the camera at a QR code.",
            Modifier.testTag("scan.status"),
            style = MaterialTheme.typography.bodyMedium,
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            TextButton(onClick = { vm.sheet = null }, modifier = Modifier.testTag("scan.cancel")) { Text("Cancel") }
            Button(
                onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                modifier = Modifier.testTag("scan.image"),
            ) { Text("From image") }
        }
    }
}

/** Decodes the first QR code in a picked image. */
private fun scanImage(context: Context, scanner: BarcodeScanner, uri: Uri, onText: (String) -> Unit, onStatus: (String) -> Unit) {
    val image = try {
        InputImage.fromFilePath(context, uri)
    } catch (_: IOException) {
        onStatus("Couldn't read this image.")
        return
    } catch (_: OutOfMemoryError) {
        onStatus("This image is too large.")
        return
    }
    scanner.process(image)
        .addOnSuccessListener { codes ->
            val text = codes.firstOrNull()?.rawValue
            if (text != null) onText(text) else onStatus("No QR code found in this image.")
        }
        .addOnFailureListener { onStatus("Couldn't read this image.") }
}

/** Live preview with ML Kit analysis. Live scanners report the same code many times a second. */
@Composable
private fun CameraPreview(scanner: BarcodeScanner, onText: (String) -> Unit, onError: () -> Unit, modifier: Modifier) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val currentOnText by rememberUpdatedState(onText)
    val currentOnError by rememberUpdatedState(onError)
    val controller = remember { LifecycleCameraController(context) }
    DisposableEffect(owner, scanner) {
        val executor = ContextCompat.getMainExecutor(context)
        try {
            controller.setEnabledUseCases(CameraController.IMAGE_ANALYSIS)
            controller.setImageAnalysisAnalyzer(
                executor,
                MlKitAnalyzer(listOf(scanner), ImageAnalysis.COORDINATE_SYSTEM_ORIGINAL, executor) { result ->
                    result.getValue(scanner)?.firstOrNull()?.rawValue?.let { currentOnText(it) }
                },
            )
            controller.bindToLifecycle(owner)
            controller.initializationFuture.addListener({
                try {
                    controller.initializationFuture.get()
                } catch (_: Exception) {
                    currentOnError()
                }
            }, executor)
        } catch (_: RuntimeException) {
            currentOnError()
        }
        onDispose {
            controller.clearImageAnalysisAnalyzer()
            controller.unbind()
        }
    }
    AndroidView(
        factory = {
            PreviewView(it).apply {
                // A TextureView: SurfaceView previews don't draw reliably inside dialog windows.
                implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                scaleType = PreviewView.ScaleType.FILL_CENTER
                // The scaled TextureView otherwise draws past the square, over the sheet's text.
                clipToOutline = true
                clipChildren = true
                this.controller = controller
            }
        },
        modifier = modifier.clipToBounds(),
    )
}
