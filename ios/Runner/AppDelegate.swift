import Flutter
import UIKit

/// FlutterViewController que permite ocultar el home indicator (barra de gestos)
/// y la barra de estado durante la reproducción a pantalla completa.
class MiruFlutterViewController: FlutterViewController {
  var fullscreen = false {
    didSet {
      setNeedsUpdateOfHomeIndicatorAutoHidden()
      setNeedsStatusBarAppearanceUpdate()
    }
  }

  override var prefersHomeIndicatorAutoHidden: Bool { fullscreen }
  override var prefersStatusBarHidden: Bool { fullscreen }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? MiruFlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.anime1v.app/foreground_service",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak controller] (call, result) in
        switch call.method {
        case "keepScreenOn":
          UIApplication.shared.isIdleTimerDisabled = true
          result(nil)
        case "releaseScreenOn":
          UIApplication.shared.isIdleTimerDisabled = false
          result(nil)
        case "setFullscreen":
          let on = (call.arguments as? Bool) ?? ((call.arguments as? [String: Any])?["value"] as? Bool ?? false)
          controller?.fullscreen = on
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
