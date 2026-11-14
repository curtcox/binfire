import Foundation

/// How a single QR code can show a link (`spec/qr.md` "qrPlan").
public enum QRPlan: String, Sendable, CaseIterable {
    /// Fits version 20-L: show the QR.
    case ok
    /// Fits up to version 40-L: show it with a "dense" note and offer alternatives.
    case dense
    /// No single QR: offer Save to HashBin and Multi-frame QR.
    case tooLong = "too-long"
}

/// QR code planning.
public enum QR {
    /// Largest UTF-8 byte count that fits version 20-L in byte mode.
    public static let okMax = 858
    /// Largest UTF-8 byte count that fits version 40-L in byte mode.
    public static let denseMax = 2953

    /// The plan for a link of `bytes` UTF-8 bytes.
    public static func qrPlan(bytes: Int) -> QRPlan {
        bytes <= okMax ? .ok : bytes <= denseMax ? .dense : .tooLong
    }

    /// The plan for a link text.
    public static func qrPlan(_ text: String) -> QRPlan { qrPlan(bytes: text.utf8.count) }
}
