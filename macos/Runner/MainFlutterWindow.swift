import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var credentialChannel: AppleCredentialChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    credentialChannel = AppleCredentialChannel(
      messenger: flutterViewController.engine.binaryMessenger
    )
    title = "Fly Player"

    super.awakeFromNib()
  }
}
