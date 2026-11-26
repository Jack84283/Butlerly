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
    let storageChannel = FlutterMethodChannel(
      name: "butlerly/storage_capacity",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    storageChannel.setMethodCallHandler { call, result in
      if call.method == "availableBytes" || call.method == "filesystemId" {
        guard let args = call.arguments as? [String: Any],
              let storagePath = args["path"] as? String else {
          result(FlutterError(code: "invalid_path", message: "Storage path required.", details: nil))
          return
        }
        do {
          let info = try FileManager.default.attributesOfFileSystem(forPath: storagePath)
          if call.method == "availableBytes" {
            result((info[.systemFreeSize] as? NSNumber)?.int64Value)
          } else {
            result((info[.systemNumber] as? NSNumber)?.stringValue)
          }
        } catch {
          result(FlutterError(code: "storage_unavailable", message: "Cannot read filesystem metadata.", details: nil))
        }
        return
      }
      if call.method == "publishNoReplace" {
        guard let args = call.arguments as? [String: Any],
              let source = args["source"] as? String,
              let destination = args["destination"] as? String else {
          result(FlutterError(code: "invalid_path", message: "Source and destination required.", details: nil))
          return
        }
        do {
          // FileManager creates a hard link atomically and refuses an existing
          // destination; a rename would overwrite a competing receipt.
          try FileManager.default.linkItem(atPath: source, toPath: destination)
          result(nil)
        } catch {
          result(FlutterError(code: "publish_failed", message: "Atomic no-replace publication failed.", details: nil))
        }
        return
      }
      result(FlutterMethodNotImplemented)
    }
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ButlerlyLocalOcr") else { return }
    let channel = FlutterMethodChannel(name: "butlerly/local_ocr", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      if call.method == "availability" {
        result(true)
        return
      }
      guard call.method == "recognizeText" else { result(FlutterMethodNotImplemented); return }
      guard let arguments = call.arguments as? [String: Any], let path = arguments["path"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "A local image path is required.", details: nil)); return
      }
      Self.recognizeText(
        at: path,
        receiptGeometry: arguments["receiptGeometry"] as? Bool == true,
        result: result
      )
    }
  }

  static func recognizeText(
    at path: String,
    receiptGeometry: Bool = false,
    result: @escaping FlutterResult
  ) {
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
        var observations = structuredObservations(request.results ?? [], pageIndex: 0)
        if receiptGeometry {
          annotateRaisedCents(in: &observations, image: cgImage, orientation: orientation)
        }
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

  /// Vision's accurate mode can merge superscript cents into the dollar token.
  /// Compare the same token in fast mode, which provides glyph-level bounds.
  private static func annotateRaisedCents(
    in rows: inout [[String: Any]],
    image: CGImage,
    orientation: CGImagePropertyOrientation
  ) {
    let strings = rows.compactMap { $0["text"] as? String }
    let isTransaction = strings.contains {
      $0.range(
        of: #"transaction details|posted on|on your statement as"#,
        options: [.regularExpression, .caseInsensitive]
      ) != nil
    }
    let pattern = #"^(?:Amount\s*:?\s*)?\$[0-9]{3,6}$"#
    guard isTransaction, strings.contains(where: {
      $0.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }) else { return }

    let request = configuredRequest()
    request.recognitionLevel = .fast
    let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
    guard (try? handler.perform([request])) != nil else { return }

    for result in request.results ?? [] {
      guard let candidate = result.topCandidates(1).first,
            candidate.string.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil,
            hasRaisedCents(candidate) else { continue }
      let box = result.boundingBox
      let positions = rows.indices.filter { index in
        guard rows[index]["text"] as? String == candidate.string,
              let left = rows[index]["left"] as? Double,
              let top = rows[index]["top"] as? Double,
              let width = rows[index]["width"] as? Double,
              let height = rows[index]["height"] as? Double else { return false }
        let original = CGRect(x: left, y: 1 - top - height, width: width, height: height)
        let overlap = original.intersection(box)
        return overlap.width * overlap.height > original.width * original.height * 0.6
      }
      if positions.count == 1 {
        rows[positions[0]]["hasRaisedCents"] = true
      }
    }
  }

  private static func hasRaisedCents(_ candidate: VNRecognizedText) -> Bool {
    let value = candidate.string
    var digits: [CGRect] = []
    guard let currencySign = value.firstIndex(of: "$") else { return false }
    for index in value.indices where index > currencySign {
      let end = value.index(after: index)
      guard let glyph = try? candidate.boundingBox(for: index..<end),
            glyph.boundingBox.height > 0 else { return false }
      digits.append(glyph.boundingBox)
    }
    let dollars = digits.dropLast(2)
    let cents = digits.suffix(2)
    guard let shortestDollar = dollars.map(\.height).min(),
          let highestDollarBaseline = dollars.map(\.minY).max(),
          let firstCent = cents.first,
          let lastCent = cents.last,
          firstCent.maxX <= lastCent.minX,
          abs(firstCent.minY - lastCent.minY) <= shortestDollar * 0.15 else {
      return false
    }
    return cents.allSatisfy {
      $0.height <= shortestDollar * 0.8 &&
      $0.minY >= highestDollarBaseline + shortestDollar * 0.15
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
