import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let storageChannel = FlutterMethodChannel(
      name: "butlerly/storage_capacity",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    storageChannel.setMethodCallHandler { call, result in
      guard call.method == "availableBytes" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let storagePath = args["path"] as? String else {
        result(FlutterError(code: "invalid_path", message: "Storage path required.", details: nil))
        return
      }
      do {
        let info = try FileManager.default.attributesOfFileSystem(forPath: storagePath)
        result((info[.systemFreeSize] as? NSNumber)?.int64Value)
      } catch {
        result(FlutterError(code: "storage_unavailable", message: "Cannot read free capacity.", details: nil))
      }
    }

    super.awakeFromNib()
  }
}
