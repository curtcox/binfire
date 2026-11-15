/// Single-QR planning (spec/qr.md).
library;

import 'package:qr/qr.dart';

import 'text.dart';

export 'package:qr/qr.dart' show QrErrorCorrectLevel;

/// Largest UTF-8 size that fits QR version 20-L.
const qrOkMaxBytes = 858;

/// Largest UTF-8 size that fits QR version 40-L.
const qrDenseMaxBytes = 2953;

/// How a link can be shown as a single QR code.
enum QrPlan {
  /// Show the QR.
  ok('ok'),

  /// Show it with a "dense" note, and offer Save to HashBin / Multi-frame QR.
  dense('dense'),

  /// No single QR. Offer Save to HashBin / Multi-frame QR.
  tooLong('too-long');

  const QrPlan(this.code);

  /// The spec string.
  final String code;
}

/// The plan for a link of [bytes] UTF-8 bytes.
QrPlan qrPlanForBytes(int bytes) => bytes <= qrOkMaxBytes
    ? QrPlan.ok
    : bytes <= qrDenseMaxBytes
        ? QrPlan.dense
        : QrPlan.tooLong;

/// The plan for showing [text] as a single QR.
QrPlan qrPlan(String text) => qrPlanForBytes(utf8Length(text));

/// A QR code's module matrix, without the quiet zone.
class QrMatrix {
  QrMatrix._(this._image);

  final QrImage _image;

  /// Modules per side.
  int get size => _image.moduleCount;

  /// QR version, 1–40.
  int get version => _image.typeNumber;

  /// Error correction level: one of [QrErrorCorrectLevel]'s values.
  int get eccLevel => _image.errorCorrectLevel;

  /// Whether the module at [row], [col] is dark.
  bool isDark(int row, int col) => _image.isDark(row, col);
}

/// Encodes [text] as a byte-mode QR code by FK's rule (qr.md): the smallest
/// version that fits at level L, then the strongest level that still fits
/// that version. Returns `null` when [text] does not fit version 40-L.
QrMatrix? encodeQr(String text) {
  if (qrPlan(text) == QrPlan.tooLong) return null;
  final version = QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.L).typeNumber;
  for (final level in const [QrErrorCorrectLevel.H, QrErrorCorrectLevel.Q, QrErrorCorrectLevel.M, QrErrorCorrectLevel.L]) {
    try {
      return QrMatrix._(QrImage(QrCode(version, level)..addData(text)));
    } on InputTooLongException {
      continue;
    }
  }
  return null;
}
