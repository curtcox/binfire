/// Showing QR codes: Send → QR code, the multi-frame sheet, and sharing a
/// QR as a PNG (spec/qr.md).
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/core.dart';
import '../transfer/transfer.dart';
import 'binfire_controller.dart';
import 'hashbin_flow.dart';
import 'ids.dart';

/// Quiet zone around every QR, in modules.
const qrQuietZone = 4;

/// Frames per second of the multi-frame QR.
const multiFrameFps = 5;

/// Paints [matrix]: black modules on white with a 4-module quiet zone, in
/// light and dark mode alike.
class QrMatrixPainter extends CustomPainter {
  /// Creates a painter for [matrix].
  QrMatrixPainter(this.matrix);

  /// The code to paint.
  final QrMatrix matrix;

  @override
  void paint(Canvas canvas, Size size) => paintQr(canvas, size.shortestSide, matrix);

  @override
  bool shouldRepaint(QrMatrixPainter old) => !identical(old.matrix, matrix);
}

/// Paints [matrix] with its quiet zone into a square of [side] pixels.
void paintQr(Canvas canvas, double side, QrMatrix matrix) {
  final n = matrix.size;
  final cell = side / (n + 2 * qrQuietZone);
  canvas.drawRect(Rect.fromLTWH(0, 0, side, side), Paint()..color = const Color(0xFFFFFFFF));
  final dark = Paint()
    ..color = const Color(0xFF000000)
    ..isAntiAlias = false;
  final path = Path();
  for (var r = 0; r < n; r++) {
    for (var c = 0; c < n; c++) {
      if (matrix.isDark(r, c)) {
        // Slight overlap avoids hairline gaps between modules.
        path.addRect(Rect.fromLTWH((c + qrQuietZone) * cell, (r + qrQuietZone) * cell, cell + 0.5, cell + 0.5));
      }
    }
  }
  canvas.drawPath(path, dark);
}

/// A square QR image of [matrix], as large as the constraints allow.
class QrMatrixView extends StatelessWidget {
  /// Creates the view.
  const QrMatrixView({super.key, required this.matrix, this.maxSide = 360});

  /// The code to show.
  final QrMatrix matrix;

  /// Largest side in logical pixels.
  final double maxSide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final side = math.min(box.maxWidth, maxSide);
      return Center(
        child: Semantics(
          image: true,
          label: 'QR code',
          child: SizedBox.square(dimension: side, child: CustomPaint(painter: QrMatrixPainter(matrix))),
        ),
      );
    });
  }
}

/// PNG bytes of [matrix] with its quiet zone, at least 8 pixels per module
/// (qr.md, `qr.export`).
Future<Uint8List> qrPng(QrMatrix matrix) async {
  final modules = matrix.size + 2 * qrQuietZone;
  final scale = math.max(8, (1024 / modules).ceil());
  final side = (modules * scale).toDouble();
  final recorder = ui.PictureRecorder();
  paintQr(Canvas(recorder), side, matrix);
  final image = await recorder.endRecording().toImage(side.toInt(), side.toInt());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Writes [matrix] as a PNG to a temporary file and opens the share sheet.
Future<void> shareQrPng(BuildContext context, QrMatrix matrix) async {
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize ? null : box.localToGlobal(Offset.zero) & box.size;
  final bytes = await qrPng(matrix);
  final dir = await Directory((await getTemporaryDirectory()).path).createTemp('qr');
  final file = File('${dir.path}/binfire-qr.png');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'image/png')],
    sharePositionOrigin: origin,
  ));
}

/// Wraps text so that one accessible node carries both [id] and the text,
/// which Maestro matches on the tagged node itself.
Widget _textWithId(String id, String text, {TextStyle? style, TextAlign? align}) =>
    MergeSemantics(child: Semantics(identifier: id, child: Text(text, style: style, textAlign: align)));

/// **Send → QR code** for [slug]'s current state (qr.md).
Future<void> showQrSheet(BuildContext context, BinfireController c, String slug) async {
  final o = c.openFor(slug);
  final link = o == null ? null : c.links.makeLink(o.currentUrl);
  if (o == null || link == null) return;
  final appUrl = o.currentUrl;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => QrSheet(controller: c, slug: slug, link: link, appUrl: appUrl),
  );
}

/// The QR sheet: one QR of [link] when it fits, the dense note, and the
/// HashBin / multi-frame offers.
class QrSheet extends StatefulWidget {
  /// Creates the sheet.
  const QrSheet({super.key, required this.controller, required this.slug, required this.link, required this.appUrl});

  /// App state.
  final BinfireController controller;

  /// The app whose state is shown.
  final String slug;

  /// The `makeLink` link of the state.
  final String link;

  /// The raw app URL (for the multi-frame bundle).
  final String appUrl;

  @override
  State<QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends State<QrSheet> {
  late String _text = widget.link;
  late QrPlan _plan = qrPlan(_text);
  late QrMatrix? _matrix = encodeQr(_text);
  bool _busy = false;

  BinfireController get _c => widget.controller;

  void _show(String text) => setState(() {
        _text = text;
        _plan = qrPlan(text);
        _matrix = encodeQr(text);
      });

  Future<void> _saveToHashbin() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!_c.canSaveToHashbin) {
        await showPublishNote(context);
        return;
      }
      final link = await saveToHashbin(context, _c, widget.slug, showResult: false);
      if (link != null && mounted) _show(link);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matrix = _matrix;
    final offers = _plan != QrPlan.ok;
    return withId(
      Ids.qrSheet,
      SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('QR code', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              if (matrix != null) withId(Ids.qrImage, QrMatrixView(matrix: matrix)),
              if (_plan == QrPlan.dense)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _textWithId(Ids.qrNote, 'Dense, may be hard to scan.', align: TextAlign.center),
                ),
              if (_plan == QrPlan.tooLong)
                _textWithId(
                  Ids.qrNote,
                  'This state is too long for one QR code. Save it to HashBin for a short link, '
                  'or show it as a multi-frame QR.',
                ),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (offers)
                      withId(
                        Ids.qrHashbin,
                        OutlinedButton(onPressed: _busy ? null : _saveToHashbin, child: const Text('Save to HashBin')),
                      ),
                    if (offers)
                      withId(
                        Ids.qrMulti,
                        OutlinedButton(
                          onPressed: () => showMultiFrameSheet(context, multiFrameTexts(widget.appUrl)),
                          child: const Text('Multi-frame QR'),
                        ),
                      ),
                    if (matrix != null)
                      withId(
                        Ids.qrExport,
                        Builder(
                          builder: (button) => FilledButton(
                            onPressed: () => shareQrPng(button, matrix),
                            child: const Text('Share image'),
                          ),
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

/// Shows [texts] as a cycling multi-frame QR at [multiFrameFps] until the
/// sheet closes.
Future<void> showMultiFrameSheet(BuildContext context, List<String> texts) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => MultiFrameSheet(texts: texts),
  );
}

/// The multi-frame sheet: `qr.frames` cycles the frames, `qr.frameIndex`
/// shows `i/n`.
class MultiFrameSheet extends StatefulWidget {
  /// Creates the sheet.
  const MultiFrameSheet({super.key, required this.texts});

  /// The `BF1:` frame texts.
  final List<String> texts;

  @override
  State<MultiFrameSheet> createState() => _MultiFrameSheetState();
}

class _MultiFrameSheetState extends State<MultiFrameSheet> {
  int _index = 0;
  late QrMatrix _matrix = encodeQr(widget.texts[0])!;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.texts.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 1000 ~/ multiFrameFps), (_) {
        final next = (_index + 1) % widget.texts.length;
        setState(() {
          _index = next;
          _matrix = encodeQr(widget.texts[next])!;
        });
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return withId(
      Ids.qrFrames,
      SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Multi-frame QR', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text('Scan with binfire until every frame has been received.'),
              const SizedBox(height: 12),
              QrMatrixView(matrix: _matrix),
              const SizedBox(height: 12),
              _textWithId(Ids.qrFrameIndex, '${_index + 1}/${widget.texts.length}', align: TextAlign.center),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
