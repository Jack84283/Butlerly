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

  static func recognizeText(at path: String, result: @escaping FlutterResult) {
    let url = URL(fileURLWithPath: path)
    let extensionName = url.pathExtension.lowercased()
    let safeFormat = ["jpg", "jpeg", "png", "heic", "heif", "pdf"].contains(extensionName)
      ? extensionName : "other"
    debugLog("started sourceFormat=\(safeFormat)")
    DispatchQueue.global(qos: .userInitiated).async {
      if url.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: url) {
        do {
          var all: [[String: Any]] = []
          var visionObservationCount = 0
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
            let pageRequest = configuredRequest()
            try VNImageRequestHandler(cgImage: cgImage).perform([pageRequest])
            visionObservationCount += pageRequest.results?.count ?? 0
            let pageRows = structuredObservations(pageRequest.results ?? [], pageIndex: pageIndex)
            all.append(contentsOf: pageRows)
          }
          finish(
            result,
            payload: payload(
              observations: all,
              sourceKind: "pdf",
              sourceOpened: true,
              pageCount: document.pageCount,
              visionObservationCount: visionObservationCount
            )
          )
        } catch {
          fail(result, code: "ocr_failed", stage: "visionRecognition")
        }
        return
      }

      guard let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage else {
        fail(result, code: "image_open_failed", stage: "imageOpen")
        return
      }
      let orientation = cgOrientation(image.imageOrientation)
      debugLog(
        "imageOpened pixels=\(cgImage.width)x\(cgImage.height) orientation=\(orientationName(image.imageOrientation))"
      )
      let request = configuredRequest()
      do {
        try VNImageRequestHandler(
          cgImage: cgImage,
          orientation: orientation,
          options: [:]
        ).perform([request])
        let observations = structuredObservations(request.results ?? [], pageIndex: 0)
        finish(
          result,
          payload: payload(
            observations: observations,
            sourceKind: "image",
            sourceOpened: true,
            pageCount: 1,
            visionObservationCount: request.results?.count ?? 0,
            pixelWidth: cgImage.width,
            pixelHeight: cgImage.height,
            orientation: orientationName(image.imageOrientation)
          )
        )
      } catch {
        fail(result, code: "ocr_failed", stage: "visionRecognition")
      }
    }
  }

  private static func configuredRequest() -> VNRecognizeTextRequest {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US", "zh-Hans", "es-ES"]
    return request
  }

  private static func structuredObservations(
    _ observations: [VNRecognizedTextObservation],
    pageIndex: Int
  ) -> [[String: Any]] {
    observations.enumerated().compactMap { index, observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      let box = observation.boundingBox
      return [
        "text": candidate.string,
        "confidence": Double(candidate.confidence),
        "left": Double(box.origin.x),
        "top": Double(1.0 - box.origin.y - box.size.height),
        "width": Double(box.size.width),
        "height": Double(box.size.height),
        "pageIndex": pageIndex,
        "order": index,
      ]
    }
  }

  private static func payload(
    observations: [[String: Any]],
    sourceKind: String,
    sourceOpened: Bool,
    pageCount: Int,
    visionObservationCount: Int? = nil,
    pixelWidth: Int? = nil,
    pixelHeight: Int? = nil,
    orientation: String? = nil
  ) -> [String: Any] {
    let lines = observations.compactMap { $0["text"] as? String }
    let confidences = observations.compactMap { $0["confidence"] as? Double }
    let confidenceMinimum = confidences.min()
    let confidenceMaximum = confidences.max()
    let confidenceAverage = confidences.isEmpty
      ? nil
      : confidences.reduce(0, +) / Double(confidences.count)
    let observationsWithBounds = observations.filter {
      (($0["width"] as? Double) ?? 0) > 0 && (($0["height"] as? Double) ?? 0) > 0
    }.count
    var diagnostics: [String: Any] = [
      "sourceKind": sourceKind,
      "sourceOpened": sourceOpened,
      "pageCount": pageCount,
      "observationCount": observations.count,
      "visionObservationCount": visionObservationCount ?? observations.count,
      "recognizedLineCount": lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
      "observationsWithBounds": observationsWithBounds,
    ]
    if let confidenceMinimum { diagnostics["confidenceMinimum"] = confidenceMinimum }
    if let confidenceAverage { diagnostics["confidenceAverage"] = confidenceAverage }
    if let confidenceMaximum { diagnostics["confidenceMaximum"] = confidenceMaximum }
    if let pixelWidth { diagnostics["pixelWidth"] = pixelWidth }
    if let pixelHeight { diagnostics["pixelHeight"] = pixelHeight }
    if let orientation { diagnostics["orientation"] = orientation }
    debugLog(
      "completed observations=\(observations.count) lines=\(lines.count) bounded=\(observationsWithBounds) confidenceMin=\(formatted(confidenceMinimum)) confidenceAvg=\(formatted(confidenceAverage)) confidenceMax=\(formatted(confidenceMaximum))"
    )
    return [
      "text": lines.joined(separator: "\n"),
      "lines": lines,
      "observations": observations,
      "diagnostics": diagnostics,
    ]
  }

  private static func finish(_ result: @escaping FlutterResult, payload: [String: Any]) {
    DispatchQueue.main.async { result(payload) }
  }

  private static func fail(_ result: @escaping FlutterResult, code: String, stage: String) {
    debugLog("failed stage=\(stage) code=\(code)")
    DispatchQueue.main.async {
      result(
        FlutterError(
          code: code,
          message: "Local text recognition failed.",
          details: ["stage": stage]
        )
      )
    }
  }

  private static func formatted(_ value: Double?) -> String {
    guard let value else { return "none" }
    return String(format: "%.3f", value)
  }

  private static func orientationName(_ orientation: UIImage.Orientation) -> String {
    switch orientation {
    case .down: return "down"
    case .left: return "left"
    case .right: return "right"
    case .upMirrored: return "upMirrored"
    case .downMirrored: return "downMirrored"
    case .leftMirrored: return "leftMirrored"
    case .rightMirrored: return "rightMirrored"
    default: return "up"
    }
  }

  private static func debugLog(_ message: String) {
    #if DEBUG
    print("ButlerlyLocalOcr \(message)")
    #endif
  }

  static func cgOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
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
