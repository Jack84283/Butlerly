import Flutter
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
      let lines = observations.compactMap { $0.topCandidates(1).first?.string }
      DispatchQueue.main.async { result(["text": lines.joined(separator: "\n"), "lines": lines]) }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    DispatchQueue.global(qos: .userInitiated).async {
      do { try VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:]).perform([request]) }
      catch { DispatchQueue.main.async { result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil)) } }
    }
  }
}
