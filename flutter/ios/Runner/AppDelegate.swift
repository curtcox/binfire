import CoreImage
import ImageIO
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BinfireQrImage") {
      QrImageDecoder.register(with: registrar.messenger())
    }
  }
}

/// `binfire/qr_image` `decode({path, maxBytes, maxSide})`: the QR texts in an
/// image file, using
/// Core Image's detector. Dart uses it where mobile_scanner can't analyze
/// files (its Vision path refuses to run on the iOS Simulator).
enum QrImageDecoder {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "binfire/qr_image", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "decode" else { return result(FlutterMethodNotImplemented) }
      guard let args = call.arguments as? [String: Any], let path = args["path"] as? String else {
        return result(FlutterError(code: "bad-args", message: "path required", details: nil))
      }
      let maxBytes = args["maxBytes"] as? Int ?? 25 * 1024 * 1024
      let maxSide = args["maxSide"] as? Int ?? 4096
      DispatchQueue.global(qos: .userInitiated).async {
        let texts = decode(path: path, maxBytes: maxBytes, maxSide: maxSide)
        DispatchQueue.main.async { result(texts) }
      }
    }
  }

  /// Bounded before decoding (spec/qr.md): files over [maxBytes] are
  /// refused, and the image is decoded as a thumbnail whose longest side is
  /// at most [maxSide] pixels.
  static func decode(path: String, maxBytes: Int, maxSide: Int) -> [String] {
    let url = URL(fileURLWithPath: path)
    guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int,
          size <= maxBytes,
          let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary)
    else { return [] }
    let image = CIImage(cgImage: cgImage)
    guard let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                    options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    else { return [] }
    return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
  }
}
