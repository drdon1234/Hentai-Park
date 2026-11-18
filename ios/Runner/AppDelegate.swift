import Flutter
import UIKit
import UserNotifications
import AVFoundation
import MediaPlayer
import BackgroundTasks
import Network
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  static var authenticating = false
  private var platform: ParkPlatform?
  private var worker: FlutterEngine?
  private var workerPlatform: ParkPlatform?
  private var workerChannel: FlutterMethodChannel?
  private var refreshTask: BGAppRefreshTask?
  private var claims: [FlutterResult] = []
  private var refreshDeadline: DispatchWorkItem?
  private let refreshIdentifier = "com.hentaipark.subscriptions"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: .main) {
      [weak self] task in
      guard let self = self, let task = task as? BGAppRefreshTask else { return }
      self.refresh(task)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ParkPlatform")!
    platform = ParkPlatform(messenger: registrar.messenger(), delegate: self)
  }

  func scheduleSubscriptions(_ hours: Int) throws {
    UserDefaults.standard.set(hours, forKey: "parkSubscriptionHours")
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshIdentifier)
    guard hours > 0 else { return }
    let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: Double(hours) * 3600)
    try BGTaskScheduler.shared.submit(request)
  }

  func claimSourceEngine(_ result: @escaping FlutterResult) {
    guard worker != nil else { result(nil); return }
    // 前台初始化数据库和配置之前，必须等后台完成取消及持久化。
    claims.append(result)
    cancelWorker()
  }

  private func refresh(_ task: BGAppRefreshTask) {
    let hours = UserDefaults.standard.integer(forKey: "parkSubscriptionHours")
    try? scheduleSubscriptions(hours)
    guard hours > 0, refreshTask == nil else {
      task.setTaskCompleted(success: false)
      return
    }
    // 已存在主引擎时复用它；禁止两个引擎同时改写源配置、会话和订阅。
    if let platform = platform {
      refreshTask = task
      task.expirationHandler = { [weak self, weak task] in
        DispatchQueue.main.async {
          guard let self = self, self.refreshTask === task else { return }
          self.platform?.cancelRefresh()
          self.refreshTask?.setTaskCompleted(success: false)
          self.refreshTask = nil
        }
      }
      platform.refreshSubscriptions { [weak self, weak task] value in
        guard let self = self, self.refreshTask === task else { return }
        self.refreshTask?.setTaskCompleted(success: value as? Bool ?? false)
        self.refreshTask = nil
      }
      return
    }
    guard worker == nil,
          UIApplication.shared.applicationState == .background else {
      task.setTaskCompleted(success: false)
      return
    }
    refreshTask = task
    let engine = FlutterEngine(name: "park-subscriptions", project: nil, allowHeadlessExecution: true)
    worker = engine
    guard engine.run(withEntrypoint: "subscriptionBackgroundMain") else {
      finishRefresh(success: false)
      return
    }
    GeneratedPluginRegistrant.register(with: engine)
    workerPlatform = ParkPlatform(messenger: engine.binaryMessenger, delegate: self)
    // 同一主线程内完成注册，Dart 首次平台消息随后处理。
    let channel = FlutterMethodChannel(name: "hentai_park/subscription_background",
                                       binaryMessenger: engine.binaryMessenger)
    workerChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "finished" else { result(FlutterMethodNotImplemented); return }
      result(nil)
      DispatchQueue.main.async { self?.finishRefresh() }
    }
    task.expirationHandler = { [weak self] in
      DispatchQueue.main.async {
        self?.cancelWorker()
      }
    }
  }

  private func cancelWorker() {
    workerChannel?.invokeMethod("cancel", arguments: nil)
    guard refreshDeadline == nil else { return }
    let deadline = DispatchWorkItem { [weak self] in self?.finishRefresh(success: false) }
    refreshDeadline = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: deadline)
  }

  private func finishRefresh(success: Bool = true) {
    refreshDeadline?.cancel()
    refreshDeadline = nil
    refreshTask?.setTaskCompleted(success: success)
    refreshTask = nil
    workerChannel?.setMethodCallHandler(nil)
    workerChannel = nil
    workerPlatform = nil
    worker?.destroyContext()
    worker = nil
    let waiting = claims
    claims.removeAll()
    waiting.forEach { $0(nil) }
  }
}

/// 只实现公开 iOS API；不模拟系统触摸、不关闭 TLS 校验。
private final class ParkPlatform: NSObject {
  private let channel: FlutterMethodChannel
  private let downloads: FlutterMethodChannel
  private weak var delegate: AppDelegate?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var activeDownloads = 0
  private var originalBrightness: CGFloat?
  private var sessionBrightness: CGFloat?
  private var subscriptionReady = false
  private var pendingRefreshes: [FlutterResult] = []
  private let volumeView: MPVolumeView = {
    let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    view.alpha = 0.01
    view.clipsToBounds = true
    view.isUserInteractionEnabled = false
    return view
  }()
  private var volumeObserver: NSKeyValueObservation?
  private var voiceID: String?
  private var remoteTargets: [(MPRemoteCommand, Any)] = []

  init(messenger: FlutterBinaryMessenger, delegate: AppDelegate) {
    self.delegate = delegate
    channel = FlutterMethodChannel(name: "hentai_park/platform", binaryMessenger: messenger)
    downloads = FlutterMethodChannel(name: "hentai_park/downloads", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in self?.handle(call, result) }
    downloads.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "update":
        let arguments = call.arguments as? [String: Any]
        self.updateDownloads(arguments?["count"] as? Int ?? 0)
        result(nil)
      case "progress": result(nil) // iOS 没有 Android 的常驻进度通知。
      default: result(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground),
                                           name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(enteredForeground),
                                           name: UIApplication.willEnterForegroundNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(willResignActive),
                                           name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive),
                                           name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
    remoteTargets.forEach { $0.0.removeTarget($0.1) }
    volumeView.removeFromSuperview()
    if let brightness = originalBrightness { UIScreen.main.brightness = brightness }
    if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
  }

  func refreshSubscriptions(_ result: @escaping FlutterResult) {
    if subscriptionReady {
      channel.invokeMethod("subscriptionRefresh", arguments: nil, result: result)
    } else {
      pendingRefreshes.append(result)
    }
  }

  func cancelRefresh() {
    let waiting = pendingRefreshes
    pendingRefreshes.removeAll()
    waiting.forEach { $0(false) }
    channel.invokeMethod("cancelSubscriptionRefresh", arguments: nil)
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "claimSourceEngine": delegate?.claimSourceEngine(result)
    case "subscriptionEngineReady":
      subscriptionReady = true
      let waiting = pendingRefreshes
      pendingRefreshes.removeAll()
      for pending in waiting {
        channel.invokeMethod("subscriptionRefresh", arguments: nil, result: pending)
      }
      result(nil)
    case "scheduleSubscriptions":
      do {
        try delegate?.scheduleSubscriptions(call.arguments as? Int ?? 0)
        result(nil)
      } catch { result(FlutterError(code: "BACKGROUND", message: "Background scheduling unavailable", details: nil)) }
    case "setSecure":
      // iOS 不支持通用防截屏；应用锁仅遮盖切后台时的任务快照。
      UserDefaults.standard.set(call.arguments as? Bool ?? false, forKey: "parkPrivateSnapshot")
      result(nil)
    case "setAuthenticating":
      AppDelegate.authenticating = call.arguments as? Bool ?? false
      result(nil)
    case "excludeFromBackup":
      let paths: [String]
      if let list = call.arguments as? [String] {
        paths = list
      } else if let single = call.arguments as? String {
        paths = [single]
      } else {
        paths = []
      }
      var allSucceeded = true
      for path in paths {
        var url = URL(fileURLWithPath: path, isDirectory: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
          try url.setResourceValues(values)
        } catch {
          allSucceeded = false
        }
      }
      result(allSucceeded)
    case "setWebViewProxy":
      if #available(iOS 17.0, *) {
        let args = call.arguments as? [String: Any]
        let host = (args?["host"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if host.isEmpty {
          WKWebsiteDataStore.default().proxyConfigurations = []
          result(true)
          return
        }
        guard let portNum = args?["port"] as? Int,
              portNum > 0, portNum <= 65535,
              let nwPort = NWEndpoint.Port(rawValue: UInt16(portNum)) else {
          result(false)
          return
        }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        var config = ProxyConfiguration(httpConnectProxy: endpoint)
        if let username = args?["username"] as? String, !username.isEmpty {
          config.applyCredential(username: username, password: args?["password"] as? String ?? "")
        }
        WKWebsiteDataStore.default().proxyConfigurations = [config]
        result(true)
      } else {
        result(false)
      }
    case "videoLevels":
      installVolumeControl()
      result(["brightness": Double(UIScreen.main.brightness),
              "volume": Double(AVAudioSession.sharedInstance().outputVolume)])
    case "setVideoBrightness":
      if originalBrightness == nil { originalBrightness = UIScreen.main.brightness }
      let target = CGFloat(min(1, max(0, (call.arguments as? NSNumber)?.doubleValue ?? 0.5)))
      sessionBrightness = target
      UIScreen.main.brightness = target
      result(nil)
    case "resetVideoBrightness":
      sessionBrightness = nil
      if let value = originalBrightness { UIScreen.main.brightness = value }
      originalBrightness = nil
      result(nil)
    case "setVideoVolume":
      installVolumeControl()
      let value = min(1, max(0, (call.arguments as? NSNumber)?.floatValue ?? 1))
      if let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first {
        slider.setValue(value, animated: false)
        slider.sendActions(for: .valueChanged)
      }
      result(nil)
    case "startVoicePlayback":
      let args = call.arguments as? [String: Any] ?? [:]
      guard let id = args["id"] as? String else { result(false); return }
      do {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .default)
        try audio.setActive(true)
        voiceID = id
        installRemoteControls()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
          MPMediaItemPropertyTitle: args["text"] as? String ?? "HentaiPark",
          MPNowPlayingInfoPropertyPlaybackRate: 0.0,
        ]
        result(true)
      } catch { result(false) }
    case "updateVoicePlayback":
      let args = call.arguments as? [String: Any] ?? [:]
      guard args["id"] as? String == voiceID else { result(nil); return }
      let available = args["available"] as? Bool ?? false
      let playing = available && (args["playing"] as? Bool ?? false)
      remoteTargets.forEach { $0.0.isEnabled = available }
      MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
      result(nil)
    case "stopVoicePlayback":
      if call.arguments as? String == voiceID {
        voiceID = nil
        remoteTargets.forEach { $0.0.removeTarget($0.1) }
        remoteTargets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func installVolumeControl() {
    if volumeView.superview == nil {
      let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
      scene?.windows.first(where: { $0.isKeyWindow })?.addSubview(volumeView)
    }
    if volumeObserver == nil {
      volumeObserver = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) {
        [weak self] session, _ in
        DispatchQueue.main.async { self?.channel.invokeMethod("mediaVolume", arguments: Double(session.outputVolume)) }
      }
    }
  }

  private func installRemoteControls() {
    guard remoteTargets.isEmpty else { return }
    let center = MPRemoteCommandCenter.shared()
    for (command, action) in [(center.playCommand, "play"), (center.pauseCommand, "pause"), (center.stopCommand, "stop")] {
      let target = command.addTarget { [weak self] _ in
        guard let self = self, let id = self.voiceID else { return .noSuchContent }
        DispatchQueue.main.async { self.channel.invokeMethod("voiceControl", arguments: ["id": id, "action": action]) }
        return .success
      }
      remoteTargets.append((command, target))
    }
  }

  private func updateDownloads(_ count: Int) {
    activeDownloads = count
    if count == 0 { endBackgroundTime() }
    else if UIApplication.shared.applicationState == .background { beginBackgroundTime() }
  }

  @objc private func enteredBackground() {
    if activeDownloads > 0 { beginBackgroundTime() }
  }

  @objc private func enteredForeground() { endBackgroundTime() }

  @objc private func willResignActive() {
    if sessionBrightness != nil, let original = originalBrightness {
      UIScreen.main.brightness = original
    }
  }

  @objc private func didBecomeActive() {
    if let target = sessionBrightness {
      originalBrightness = UIScreen.main.brightness
      UIScreen.main.brightness = target
    }
  }

  private func beginBackgroundTime() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Park transfers") { [weak self] in
      self?.downloads.invokeMethod("interrupted", arguments: nil)
      self?.endBackgroundTime()
    }
    if backgroundTask == .invalid { downloads.invokeMethod("interrupted", arguments: nil) }
  }

  private func endBackgroundTime() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}
