import Flutter
import ImageIO
import UIKit
import Vision

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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ButlerlyLocalOcr") else { return }
    let channel = FlutterMethodChannel(name: "butlerly/local_ocr", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognizeText" else { result(FlutterMethodNotImplemented); return }
      guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "A local image path is required.", details: nil)); return
      }
      Self.recognizeText(at: path, result: result)
    }
  }

  private static func recognizeText(at path: String, result: @escaping FlutterResult) {
    let request = VNRecognizeTextRequest { request, error in
      if let error { DispatchQueue.main.async { result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil)) }; return }
      let observations = request.results as? [VNRecognizedTextObservation] ?? []
      let structured = observations.compactMap { observation -> [String: Any]? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let box = observation.boundingBox
        return [
          "text": candidate.string,
          "confidence": Double(candidate.confidence),
          "left": Double(box.origin.x),
          "top": Double(1.0 - box.origin.y - box.size.height),
          "width": Double(box.size.width),
          "height": Double(box.size.height),
        ]
      }
      let lines = structured.compactMap { $0["text"] as? String }
      DispatchQueue.main.async {
        result(["text": lines.joined(separator: "\n"), "lines": lines, "observations": structured])
      }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US", "zh-Hans", "es-ES"]
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        guard let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage else {
          throw NSError(domain: "ButlerlyLocalOcr", code: 1, userInfo: [NSLocalizedDescriptionKey: "The receipt image could not be opened."])
        }
        let orientation = Self.cgOrientation(image.imageOrientation)
        try VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:]).perform([request])
      }
      catch { DispatchQueue.main.async { result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil)) } }
    }
  }

  private static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
    switch orientation {
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    default: return .up
    }
  }
}
