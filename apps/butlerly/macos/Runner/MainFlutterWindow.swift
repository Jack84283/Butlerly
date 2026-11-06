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

    super.awakeFromNib()
  }
}
