import Flutter
import ImageIO
import PDFKit
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
      let structured = observations.enumerated().compactMap { index, observation -> [String: Any]? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let box = observation.boundingBox
        return [
          "text": candidate.string,
          "confidence": Double(candidate.confidence),
          "left": Double(box.origin.x),
          "top": Double(1.0 - box.origin.y - box.size.height),
          "width": Double(box.size.width),
          "height": Double(box.size.height),
          "pageIndex": 0,
          "order": index,
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
        if let document = PDFDocument(url: URL(fileURLWithPath: path)) {
          var all: [[String: Any]] = []
          for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(3.0, max(1.0, 2200.0 / max(bounds.width, bounds.height)))
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { context in
              UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
              context.cgContext.translateBy(x: 0, y: size.height)
              context.cgContext.scaleBy(x: scale, y: -scale)
              page.draw(with: .mediaBox, to: context.cgContext)
            }
            guard let cgImage = image.cgImage else { continue }
            let pageRequest = VNRecognizeTextRequest()
            pageRequest.recognitionLevel = .accurate
            pageRequest.usesLanguageCorrection = true
            pageRequest.recognitionLanguages = ["en-US", "zh-Hans", "es-ES"]
            try VNImageRequestHandler(cgImage: cgImage).perform([pageRequest])
            let pageRows = (pageRequest.results ?? []).enumerated().compactMap { index, observation -> [String: Any]? in
              guard let candidate = observation.topCandidates(1).first else { return nil }
              let box = observation.boundingBox
              return ["text": candidate.string, "confidence": Double(candidate.confidence),
                "left": Double(box.origin.x), "top": Double(1.0 - box.origin.y - box.size.height),
                "width": Double(box.size.width), "height": Double(box.size.height),
                "pageIndex": pageIndex, "order": index]
            }
            all.append(contentsOf: pageRows)
          }
          let lines = all.compactMap { $0["text"] as? String }
          DispatchQueue.main.async { result(["text": lines.joined(separator: "\n"), "lines": lines, "observations": all]) }
          return
        }
        guard let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage else {
          throw NSError(domain: "ButlerlyLocalOcr", code: 1, userInfo: [NSLocalizedDescriptionKey: "The statement image or PDF could not be opened."])
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
