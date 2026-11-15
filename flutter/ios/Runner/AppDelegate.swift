import CoreImage
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

/// `binfire/qr_image` `decode({path})`: the QR texts in an image file, using
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
      DispatchQueue.global(qos: .userInitiated).async {
        let texts = decode(path: path)
        DispatchQueue.main.async { result(texts) }
      }
    }
  }

  static func decode(path: String) -> [String] {
    guard let image = CIImage(contentsOf: URL(fileURLWithPath: path)),
          let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                    options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    else { return [] }
    return detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
  }
}
