import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import BinfireCore

/// What the QR sheet shows: `link` (a `makeLink` or `/c#` link). `stateURL`
/// is the raw app URL behind it, for Save to HashBin and Multi-frame QR, or
/// nil for a link that already is short.
struct QRRequest: Equatable {
    let app: String
    let stateURL: String?
    let link: String
}

/// QR images with Core Image (`spec/qr.md` "Rendering"): byte mode, the
/// smallest version at level L, then the strongest level that still fits
/// that version; black on white with a 4-module quiet zone.
enum QRRenderer {
    private static let context = CIContext()

    private static func generate(_ data: Data, _ level: String) -> CIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = data
        f.correctionLevel = level
        guard let img = f.outputImage, !img.extent.isInfinite, !img.extent.isEmpty else { return nil }
        return img
    }

    /// The module matrix, one pixel per module, with Core Image's 1-module border.
    static func matrix(_ text: String) -> CGImage? {
        let data = Data(text.utf8)
        guard let low = generate(data, "L") else { return nil }
        var best = low
        // The same output size means the same version.
        for level in ["H", "Q", "M"] {
            if let img = generate(data, level), img.extent.width == low.extent.width {
                best = img
                break
            }
        }
        return context.createCGImage(best, from: best.extent)
    }

    /// `scale` pixels per module, including a 4-module quiet zone.
    static func image(_ text: String, scale: Int) -> UIImage? {
        guard let cg = matrix(text) else { return nil }
        let modules = cg.width - 2
        let side = CGFloat((modules + 8) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            ctx.cgContext.interpolationQuality = .none
            // Core Image's own border is one (white) module of the four.
            let s = CGFloat(scale)
            UIImage(cgImage: cg).draw(in: CGRect(x: 3 * s, y: 3 * s, width: CGFloat(cg.width) * s, height: CGFloat(cg.height) * s))
        }
    }

    /// Writes a PNG (8 pixels per module) to a temporary file for sharing.
    static func exportPNG(_ text: String) -> URL? {
        guard let data = image(text, scale: 8)?.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("binfire-qr.png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// A QR code image, crisp at any size and always black on white.
struct QRCodeImage: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 320, maxHeight: 320)
    }
}

/// Send → QR code (`spec/qr.md`): one QR when the link fits, else Save to
/// HashBin and Multi-frame QR.
struct QRSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let request: QRRequest
    @State private var image: UIImage?
    @State private var exportURL: URL?
    @State private var frames: [String]?

    private var plan: QRPlan { QR.qrPlan(request.link) }

    var body: some View {
        NavigationStack {
            Group {
                if let frames {
                    MultiFrameView(frames: frames)
                } else {
                    single
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(20)
            .navigationTitle(frames == nil ? "QR code" : "Multi-frame QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("qr.sheet")
        .task(id: request.link) {
            guard plan != .tooLong else { return }
            image = QRRenderer.image(request.link, scale: 8)
            exportURL = QRRenderer.exportPNG(request.link)
        }
    }

    private var single: some View {
        VStack(spacing: 16) {
            if plan != .tooLong, let image {
                QRCodeImage(image: image)
                    .accessibilityLabel("QR code")
                    .accessibilityIdentifier("qr.image")
            }
            if plan != .ok {
                Text(plan == .dense ? "Dense, may be hard to scan."
                     : "This link is too long for one QR code.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("qr.note")
            }
            if plan != .tooLong, let exportURL {
                ShareLink(item: exportURL, preview: SharePreview("binfire QR code", image: Image(uiImage: image ?? UIImage()))) {
                    Label("Share image", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("qr.export")
            }
            if plan != .ok, let stateURL = request.stateURL {
                // Like long.save: Native Save, or the app's own Publish without a client ID.
                Button {
                    model.startHashBinSave(app: request.app, url: stateURL, copyLink: false, showQR: true)
                } label: { Label("Save to HashBin (short link)", systemImage: "icloud.and.arrow.up") }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("qr.hashbin")
                Button {
                    frames = QR.multiFrameTexts(url: stateURL)
                } label: { Label("Multi-frame QR", systemImage: "square.stack.3d.forward.dottedline") }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("qr.multi")
            }
            Text(request.link.count > 300 ? String(request.link.prefix(300)) + "…" : request.link)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
        }
    }
}

/// Cycles the `BF1:` frames at 5 frames per second until the sheet closes.
struct MultiFrameView: View {
    let frames: [String]
    @State private var index = 0
    @State private var image: UIImage?
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let image {
                    QRCodeImage(image: image)
                } else {
                    Color.white.frame(width: 320, height: 320)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Multi-frame QR code")
            .accessibilityIdentifier("qr.frames")
            Text("\(index + 1)/\(frames.count)")
                .font(.headline.monospacedDigit())
                .accessibilityIdentifier("qr.frameIndex")
            Text("Keep the receiving camera on the code until it has every frame.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .onAppear { show(0) }
        .onReceive(timer) { _ in show((index + 1) % frames.count) }
    }

    private func show(_ i: Int) {
        guard !frames.isEmpty else { return }
        index = i
        image = QRRenderer.image(frames[i], scale: 4)
    }
}
