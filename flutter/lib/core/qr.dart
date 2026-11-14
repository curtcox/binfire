/// Single-QR planning (spec/qr.md).
library;

import 'text.dart';

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
