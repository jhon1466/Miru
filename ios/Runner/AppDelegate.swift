import Flutter
import UIKit
import AVKit
import AVFoundation

/// AVPlayerViewController que avisa cuando desaparece (botón Done, swipe o programático).
class MiruPlayerVC: AVPlayerViewController {
  var onDismiss: (() -> Void)?
  private var didNotify = false

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    // Solo notificar si realmente se está cerrando (no al entrar en PiP)
    if isBeingDismissed || presentingViewController == nil {
      guard !didNotify else { return }
      didNotify = true
      onDismiss?()
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var playerVC: MiruPlayerVC?
  private var playerEndObserver: NSObjectProtocol?
  private var pendingResult: FlutterResult?
  private var resultSent = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.anime1v.app/native_player",
        binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] (call, result) in
        guard let self = self else { return }
        if call.method == "play" {
          let args = call.arguments as? [String: Any]
          let url = args?["url"] as? String ?? ""
          let title = args?["title"] as? String
          let headers = args?["headers"] as? [String: String]
          let startAt = args?["startAt"] as? Double ?? 0
          self.presentNativePlayer(url: url, title: title, headers: headers, startAt: startAt, result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func presentNativePlayer(url: String, title: String?, headers: [String: String]?, startAt: Double, result: @escaping FlutterResult) {
    guard let videoURL = URL(string: url) else {
      result(FlutterError(code: "bad_url", message: "URL invalida", details: url))
      return
    }

    // Reproducir audio aunque el telefono este en silencio
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {}

    var options: [String: Any] = [:]
    if let headers = headers, !headers.isEmpty {
      options["AVURLAssetHTTPHeaderFieldsKey"] = headers
    }
    let asset = AVURLAsset(url: videoURL, options: options)
    let item = AVPlayerItem(asset: asset)
    let player = AVPlayer(playerItem: item)

    let vc = MiruPlayerVC()
    vc.player = player
    vc.modalPresentationStyle = .fullScreen
    vc.allowsPictureInPicturePlayback = true

    self.playerVC = vc
    self.pendingResult = result
    self.resultSent = false

    var ended = false
    // Detectar fin del video
    self.playerEndObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime,
      object: item,
      queue: .main) { [weak self] _ in
        ended = true
        self?.playerVC?.dismiss(animated: true) {
          self?.cleanup(reason: "ended")
        }
    }

    vc.onDismiss = { [weak self] in
      self?.cleanup(reason: ended ? "ended" : "closed")
    }

    guard let root = window?.rootViewController else {
      result(FlutterError(code: "no_root", message: "Sin rootViewController", details: nil))
      return
    }
    var top: UIViewController = root
    while let presented = top.presentedViewController { top = presented }

    top.present(vc, animated: true) {
      if startAt > 0 {
        player.seek(to: CMTime(seconds: startAt, preferredTimescale: 1))
      }
      player.play()
    }
  }

  private func cleanup(reason: String) {
    if let observer = playerEndObserver {
      NotificationCenter.default.removeObserver(observer)
      playerEndObserver = nil
    }
    playerVC?.player?.pause()
    playerVC = nil
    guard !resultSent else { return }
    resultSent = true
    let result = pendingResult
    pendingResult = nil
    result?(reason)
  }
}
