import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    windowFrame.size = NSSize(width: 1320, height: 820)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 980, height: 640)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerNativeChannel(controller: flutterViewController)

    super.awakeFromNib()
  }

  private func registerNativeChannel(controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "app_cleaner/native",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      if call.method == "getAppIcon" {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(nil)
          return
        }
        let targetSize = (args["size"] as? Int) ?? 128

        DispatchQueue.global(qos: .userInitiated).async {
          let pngData = Self.renderAppIconPng(path: path, size: targetSize)
          DispatchQueue.main.async {
            if let data = pngData {
              result(FlutterStandardTypedData(bytes: data))
            } else {
              result(nil)
            }
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func renderAppIconPng(path: String, size: Int) -> Data? {
    guard FileManager.default.fileExists(atPath: path) else {
      return nil
    }
    let icon = NSWorkspace.shared.icon(forFile: path)
    let dimension = max(16, min(size, 256))

    guard let bitmapRep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: dimension,
      pixelsHigh: dimension,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else {
      return nil
    }

    bitmapRep.size = NSSize(width: dimension, height: dimension)

    NSGraphicsContext.saveGraphicsState()
    if let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmapRep) {
      NSGraphicsContext.current = graphicsContext
      graphicsContext.imageInterpolation = .high
      icon.draw(
        in: NSRect(x: 0, y: 0, width: dimension, height: dimension),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0
      )
    }
    NSGraphicsContext.restoreGraphicsState()

    return bitmapRep.representation(using: .png, properties: [:])
  }
}
