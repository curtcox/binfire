import SwiftUI
import UIKit
import AVFoundation
import VisionKit
import Vision
import CoreML
import PhotosUI
import ImageIO
import BinfireCore

/// One scan sheet's state: a single `ScanSession` for every decoded text,
/// live or from images (`spec/qr.md` "Scanning").
@MainActor
final class ScanController: ObservableObject {
    enum Camera: Equatable {
        case checking, live, unavailable, denied
    }

    @Published var camera: Camera = .checking
    @Published var status = ""
    private var session: ScanSession
    private weak var model: AppModel?
    /// A route or bundle was acted on: the sheet is closing.
    private var finished = false
    private var lastText: String?

    init(model: AppModel) {
        self.model = model
        self.session = ScanSession(links: model.links)
    }

    /// Largest image file read for scan-from-image (spec/qr.md: 25 MiB).
    static let maxImageBytes = 25 << 20
    /// Images are downsampled to at most this many pixels on the long side.
    static let maxImagePixels = 4096

    func checkCamera() async {
        guard DataScannerViewController.isSupported else {
            setCamera(.unavailable)
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            if !(await AVCaptureDevice.requestAccess(for: .video)) {
                setCamera(.denied)
                return
            }
        default:
            setCamera(.denied)
            return
        }
        setCamera(DataScannerViewController.isAvailable ? .live : .unavailable)
    }

    private func setCamera(_ c: Camera) {
        camera = c
        switch c {
        case .checking: status = ""
        case .live: status = "Point the camera at a QR code."
        case .unavailable: status = "Camera unavailable"
        case .denied: status = "Camera permission denied"
        }
    }

    /// A text from the live scanner, which reports the same code many times a second.
    func acceptLive(_ text: String) {
        guard text != lastText else { return }
        lastText = text
        accept(text)
    }

    func accept(_ text: String) {
        guard !finished, let model else { return }
        switch session.accept(text) {
        case let .progress(received, count):
            status = "Receiving \(received) of \(count)"
        case let .frameError(error):
            status = ScanController.message(for: error)
        case let .route(route):
            finished = true
            model.handle(route)
        case let .bundle(payload):
            finished = true
            model.receiveBundle(payload)
        }
    }

    /// Scan from image: the first QR code Vision reports.
    func scanImage(_ item: PhotosPickerItem) async {
        status = "Reading image…"
        let picked: PickedImageFile
        do {
            guard let file = try await item.loadTransferable(type: PickedImageFile.self) else {
                status = "Couldn't read this image."
                return
            }
            picked = file
        } catch {
            status = "Couldn't read this image."
            return
        }
        guard let url = picked.url else {
            status = "This image is too large."
            return
        }
        let text = await Task.detached(priority: .userInitiated) { () -> String? in
            defer { try? FileManager.default.removeItem(at: url) }
            return ScanController.decodeQR(url)
        }.value
        guard let text else {
            status = "No QR code found in this image."
            return
        }
        lastText = nil
        accept(text)
    }

    /// Decodes at most `maxImagePixels` on the long side, then runs Vision.
    nonisolated static func decodeQR(_ url: URL) -> String? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxImagePixels,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        do {
            return try detectQR(image, device: nil, revision: nil)
        } catch {
            // Without a Neural Engine (the simulator) Vision can't create its
            // default inference context. Retry on the CPU, newest revision
            // first; the newer ML revisions find nothing there, older ones do.
            let devices = (try? VNDetectBarcodesRequest().supportedComputeStageDevices)?[.main] ?? []
            guard let cpu = devices.first(where: { if case .cpu = $0 { return true } else { return false } }) else {
                return nil
            }
            for revision in VNDetectBarcodesRequest.supportedRevisions.sorted(by: >) {
                if let text = try? detectQR(image, device: cpu, revision: revision) { return text }
            }
            return nil
        }
    }

    nonisolated private static func detectQR(_ image: CGImage, device: MLComputeDevice?, revision: Int?) throws -> String? {
        let request = VNDetectBarcodesRequest()
        if let revision { request.revision = revision }
        request.symbologies = [.qr]
        if let device { request.setComputeDevice(device, for: .main) }
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return request.results?.lazy.compactMap(\.payloadStringValue).first
    }

    static func message(for error: BinfireError) -> String {
        let text: String
        switch error {
        case .badMagic: text = "This isn't a binfire frame."
        case .badVersion: text = "This frame is from a newer version of binfire."
        case .badFrame: text = "This frame is damaged."
        case .tooLarge: text = "This transfer is too large."
        case .inconsistent: text = "Frames from different transfers got mixed. Keep scanning to start again."
        case .mismatch: text = "The received data failed verification. Keep scanning to start again."
        default: text = "This frame can't be read."
        }
        return "\(text) (\(error.code))"
    }
}

/// A picked image as a temporary file copy, or `url == nil` when the file is
/// over `ScanController.maxImageBytes` (refused before it is read).
struct PickedImageFile: Transferable {
    let url: URL?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            let size = (try? received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= ScanController.maxImageBytes else { return PickedImageFile(url: nil) }
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("scan-\(UUID().uuidString)")
                .appendingPathExtension(received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedImageFile(url: copy)
        }
    }
}

/// Library → Scan: live camera, or scan from an image.
struct ScanSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller: ScanController
    @State private var pickedItem: PhotosPickerItem?

    init(model: AppModel) {
        _controller = StateObject(wrappedValue: ScanController(model: model))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                cameraArea
                Text(controller.status)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("scan.status")
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label("Scan from image", systemImage: "photo")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("scan.image")
                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("scan.cancel")
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.sheet")
        .task { await controller.checkCamera() }
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            Task { await controller.scanImage(item) }
        }
    }

    @ViewBuilder private var cameraArea: some View {
        switch controller.camera {
        case .live:
            LiveScanner { controller.acceptLive($0) }
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityElement()
                .accessibilityLabel("Camera")
                .accessibilityIdentifier("scan.camera")
        case .checking:
            ProgressView().frame(height: 120)
        case .unavailable, .denied:
            Image(systemName: controller.camera == .denied ? "video.slash" : "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(height: 120)
        }
    }
}

/// VisionKit's live QR scanner.
struct LiveScanner: UIViewControllerRepresentable {
    let onText: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .balanced,
                                           recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: true,
                                           isPinchToZoomEnabled: true,
                                           isGuidanceEnabled: false,
                                           isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        context.coordinator.onText = onText
        if !vc.isScanning {
            DispatchQueue.main.async { try? vc.startScanning() }
        }
    }

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onText: onText) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onText: (String) -> Void

        init(onText: @escaping (String) -> Void) {
            self.onText = onText
        }

        private func report(_ items: [RecognizedItem]) {
            for item in items {
                if case let .barcode(code) = item, let text = code.payloadStringValue { onText(text) }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(addedItems)
        }

        // A cycling multi-frame QR often updates the same tracked item.
        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            report(updatedItems)
        }
    }
}
