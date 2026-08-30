import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testAllUIImageOrientationsMapToVisionWithoutLosingMirroring() {
    let cases: [(UIImage.Orientation, CGImagePropertyOrientation)] = [
      (.up, .up), (.down, .down), (.left, .left), (.right, .right),
      (.upMirrored, .upMirrored), (.downMirrored, .downMirrored),
      (.leftMirrored, .leftMirrored), (.rightMirrored, .rightMirrored),
    ]
    for (imageOrientation, visionOrientation) in cases {
      XCTAssertEqual(AppDelegate.cgOrientation(imageOrientation), visionOrientation)
    }
  }

  func testJPEGImageReachesVisionAndReturnsStructuredObservations() throws {
    try verifyImage(type: .jpeg, extension: "jpg")
  }

  func testHEICImageReachesVisionAndReturnsStructuredObservations() throws {
    try verifyImage(type: .heic, extension: "heic")
  }

  func testImageOpenFailureIsNotAnEmptyRecognitionSuccess() {
    let completed = expectation(description: "OCR failure")
    AppDelegate.recognizeText(at: "/nonexistent/butlerly-test-image.jpg") { result in
      let error = result as? FlutterError
      XCTAssertEqual(error?.code, "image_open_failed")
      XCTAssertEqual((error?.details as? [String: String])?["stage"], "imageOpen")
      completed.fulfill()
    }
    wait(for: [completed], timeout: 10)
  }

  private func verifyImage(type: UTType, extension suffix: String) throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: CGSize(width: 1400, height: 700), format: format).image { context in
      UIColor.white.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 1400, height: 700))
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black,
      ]
      ("08/12/2026 MARKET 123.45" as NSString).draw(at: CGPoint(x: 50, y: 150), withAttributes: attributes)
      ("08/13/2026 GROCERY 42.10" as NSString).draw(at: CGPoint(x: 50, y: 300), withAttributes: attributes)
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("butlerly-ocr-\(UUID().uuidString).\(suffix)")
    defer { try? FileManager.default.removeItem(at: url) }
    guard let cgImage = image.cgImage,
      let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
    else { throw XCTSkip("This simulator cannot encode the requested local image format.") }
    CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: 1] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw XCTSkip("This simulator cannot encode the requested local image format.")
    }
    let originalBytes = try Data(contentsOf: url)
    let completed = expectation(description: "Structured Vision OCR")
    AppDelegate.recognizeText(at: url.path) { result in
      let payload = result as? [String: Any]
      XCTAssertNotNil(payload, "Native OCR should return a successful payload.")
      let observations = payload?["observations"] as? [[String: Any]] ?? []
      XCTAssertGreaterThanOrEqual(observations.count, 2)
      XCTAssertTrue((payload?["text"] as? String ?? "").contains("MARKET"))
      let diagnostics = payload?["diagnostics"] as? [String: Any]
      XCTAssertEqual(diagnostics?["sourceOpened"] as? Bool, true)
      XCTAssertEqual(diagnostics?["pixelWidth"] as? Int, 1400)
      XCTAssertEqual(diagnostics?["pixelHeight"] as? Int, 700)
      XCTAssertEqual(diagnostics?["orientation"] as? String, "up")
      XCTAssertEqual(diagnostics?["observationCount"] as? Int, observations.count)
      for observation in observations {
        XCTAssertNotNil(observation["confidence"] as? Double)
        XCTAssertGreaterThan(observation["width"] as? Double ?? 0, 0)
        XCTAssertGreaterThan(observation["height"] as? Double ?? 0, 0)
      }
      XCTAssertEqual(try? Data(contentsOf: url), originalBytes)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 30)
  }

}
