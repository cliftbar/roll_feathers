import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    self.minSize = NSSize(width: 300, height: 300)
    // Prevent black frame before Flutter's first paint.
    self.backgroundColor = NSColor.windowBackgroundColor
    super.awakeFromNib()
  }
}
