/// Scanning QR codes: the scan sheet (live camera and scan from image) and
/// opening what a scan received (spec/qr.md).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/core.dart';
import '../transfer/transfer.dart';
import 'binfire_controller.dart';
import 'hashbin_flow.dart';
import 'ids.dart';
import 'route_actions.dart';
import 'sheets.dart';

/// Status shown when the device has no usable camera.
const cameraUnavailableMessage = 'Camera unavailable';

/// Status shown when camera permission is denied.
const cameraDeniedMessage = 'Camera permission denied';

/// Status shown when a picked image holds no QR code.
const noQrInImageMessage = 'No QR code found in this image.';

/// Error shown for a received `site` bundle until M6.
const packagedSitesLaterMessage = 'Packaged sites arrive in a later version.';

/// Builds the live camera preview. It reports every decoded text through
/// `onText`, and calls `onUnavailable` with a status message when the camera
/// can't run.
typedef ScanCameraBuilder = Widget Function(
  BuildContext context,
  void Function(String text) onText,
  void Function(String message) onUnavailable,
);

/// Lets the user pick an image and decodes the QR codes in it. Returns `null`
/// when the user cancelled, else the decoded texts in reported order.
typedef ScanImagePicker = Future<List<String>?> Function();

/// A user-facing message for a frame error code.
String frameErrorMessage(String code) => switch (code) {
      ErrorCodes.tooLarge => 'This transfer is too large.',
      ErrorCodes.inconsistent => 'Frames from different transfers were mixed. Keep scanning to start over.',
      ErrorCodes.mismatch => 'The received data failed verification. Keep scanning to start over.',
      ErrorCodes.badMagic || ErrorCodes.badVersion => 'This QR code is from an unsupported version.',
      _ => "This frame couldn't be read. Keep scanning.",
    };

/// A user-facing message for a received bundle that failed to decode.
String bundleErrorMessage(String code) => switch (code) {
      ErrorCodes.tooLarge => 'The received content is too large.',
      ErrorCodes.mismatch => "The received content failed verification: it doesn't match its ID.",
      _ => "The received content couldn't be opened ($code).",
    };

/// The library's **Scan**: shows the scan sheet and acts on its result.
Future<void> startScan(BuildContext context, BinfireController c,
    {ScanCameraBuilder? camera, ScanImagePicker? pickImage}) async {
  final result = await showModalBottomSheet<ScanResult>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => ScanSheet(controller: c, camera: camera, pickImage: pickImage),
  );
  if (result == null || !context.mounted) return;
  switch (result) {
    case ScanRoute(:final route):
      await performRoute(context, c, route);
    case ScanBundle(:final payload):
      await openReceivedBundle(context, c, payload);
    case ScanProgress() || ScanFrameError():
      break;
  }
}

/// Opens a received bundle [payload] (qr.md, Received bundles).
Future<void> openReceivedBundle(BuildContext context, BinfireController c, Uint8List payload) async {
  final Bundle bundle;
  try {
    bundle = decodeBundle(payload, limits: c.config.limits);
  } on BinfireException catch (e) {
    return showErrorSheet(context, bundleErrorMessage(e.code));
  }
  switch (bundle.kind) {
    case BundleKind.url:
      await performRoute(context, c, c.links.routeReceived(bundle.url!));
    case BundleKind.cid:
      final entry = bundle.entries.single;
      c.cacheCid(entry.cid, entry.bytes);
      await openCid(context, c, entry.cid, hint: bundle.app, run: false);
    case BundleKind.site:
      await showErrorSheet(context, packagedSitesLaterMessage);
  }
}

/// The scan sheet. Every decoded text goes to one [ScanSession]; the sheet
/// closes with the first `route` or `bundle` result.
class ScanSheet extends StatefulWidget {
  /// Creates the sheet. [camera] and [pickImage] default to mobile_scanner
  /// and the system photo picker.
  const ScanSheet({super.key, required this.controller, this.camera, this.pickImage});

  /// App state.
  final BinfireController controller;

  /// The live camera, or `null` for mobile_scanner.
  final ScanCameraBuilder? camera;

  /// Scan from image, or `null` for the system picker plus a QR decoder.
  final ScanImagePicker? pickImage;

  @override
  State<ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<ScanSheet> {
  late final ScanSession _session = ScanSession(widget.controller.links);
  MobileScannerController? _scanner;
  String _status = 'Point the camera at a binfire QR code.';
  bool _cameraOk = true;
  bool _done = false;
  bool _picking = false;

  MobileScannerController get _ownScanner =>
      _scanner ??= MobileScannerController(formats: const [BarcodeFormat.qrCode]);

  @override
  void dispose() {
    _scanner?.dispose();
    super.dispose();
  }

  void _onText(String text) {
    if (_done || !mounted) return;
    final r = _session.accept(text);
    switch (r) {
      case ScanProgress(:final received, :final count):
        setState(() => _status = 'Receiving $received of $count');
      case ScanFrameError(:final error):
        setState(() => _status = frameErrorMessage(error));
      case ScanRoute() || ScanBundle():
        // Live scanners repeat a code many times a second: act once.
        _done = true;
        Navigator.of(context).pop(r);
    }
  }

  void _onCameraUnavailable(String message) {
    if (!mounted || !_cameraOk) return;
    setState(() {
      _cameraOk = false;
      _status = message;
    });
  }

  Future<void> _fromImage() async {
    if (_picking) return;
    _picking = true;
    try {
      final texts = await (widget.pickImage ?? _pickAndDecode)();
      if (texts == null || !mounted) return;
      if (texts.isEmpty) {
        setState(() => _status = noQrInImageMessage);
        return;
      }
      _onText(texts.first);
    } catch (_) {
      if (mounted) setState(() => _status = "Couldn't read this image.");
    } finally {
      _picking = false;
    }
  }

  Future<List<String>?> _pickAndDecode() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (file == null) return null;
    return decodeQrImage(file.path, _ownScanner);
  }

  Widget _defaultCamera(BuildContext context, void Function(String) onText, void Function(String) onUnavailable) {
    return MobileScanner(
      controller: _ownScanner,
      onDetect: (capture) {
        for (final b in capture.barcodes) {
          final text = b.rawValue;
          if (text != null) onText(text);
        }
      },
      errorBuilder: (context, error) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onUnavailable(
            error.errorCode == MobileScannerErrorCode.permissionDenied ? cameraDeniedMessage : cameraUnavailableMessage));
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final camera = widget.camera ?? _defaultCamera;
    final screen = MediaQuery.sizeOf(context);
    final cameraHeight = (screen.width - 32).clamp(0.0, screen.height * 0.45);
    return withId(
      Ids.scanSheet,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Scan a QR code', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              if (_cameraOk)
                withId(
                  Ids.scanCamera,
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(height: cameraHeight, child: camera(context, _onText, _onCameraUnavailable)),
                  ),
                ),
              const SizedBox(height: 12),
              MergeSemantics(
                child: Semantics(
                  identifier: Ids.scanStatus,
                  liveRegion: true,
                  child: Text(_status, textAlign: TextAlign.center),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    withId(Ids.scanCancel, TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                    withId(
                      Ids.scanImage,
                      FilledButton.icon(
                        onPressed: _fromImage,
                        icon: const Icon(Icons.photo_outlined),
                        label: const Text('From image'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _imageChannel = MethodChannel('binfire/qr_image');

/// Decodes the QR codes in the image at [path], in reported order.
///
/// Uses mobile_scanner (Vision or ML Kit). Where it can't analyze files
/// (the iOS Simulator), iOS falls back to Core Image's QR detector.
Future<List<String>> decodeQrImage(String path, MobileScannerController scanner) async {
  try {
    final capture = await scanner.analyzeImage(path, formats: const [BarcodeFormat.qrCode]);
    return [for (final b in capture?.barcodes ?? const <Barcode>[]) if (b.rawValue != null) b.rawValue!];
  } catch (_) {
    if (!Platform.isIOS) rethrow;
    final texts = await _imageChannel.invokeListMethod<String>('decode', {'path': path});
    return texts ?? const [];
  }
}
