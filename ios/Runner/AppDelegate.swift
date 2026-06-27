import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, AVAudioPlayerDelegate {
  private var dataExportShareChannel: FlutterMethodChannel?
  private var voiceRecorderChannel: FlutterMethodChannel?
  private var audioPlayerChannel: FlutterMethodChannel?
  private var audioRecorder: AVAudioRecorder?
  private var audioPlayer: AVAudioPlayer?
  private var audioPlayerURL: URL?
  private var recordingURL: URL?
  private var recordingStartedAt: Date?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerDataExportShareChannel(messenger: messenger)
    registerVoiceRecorderChannel(messenger: messenger)
    registerAudioPlayerChannel(messenger: messenger)
  }

  private func registerDataExportShareChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "simichat/data_export_share",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.shareExportFile(call: call, result: result)
    }
    dataExportShareChannel = channel
  }

  private func registerVoiceRecorderChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "simichat/voice_recorder",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startRecording":
        self?.startVoiceRecording(result: result)
      case "stopRecording":
        self?.stopVoiceRecording(result: result)
      case "cancelRecording":
        self?.cancelVoiceRecording(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    voiceRecorderChannel = channel
  }

  private func registerAudioPlayerChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "simichat/audio_player",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "playFile":
        self?.playAudioFile(call: call, result: result)
      case "stop":
        self?.stopAudioPlayback()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    audioPlayerChannel = channel
  }

  private func shareExportFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          !path.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "缺少导出文件路径", details: nil))
      return
    }

    let fileURL = URL(fileURLWithPath: path).standardizedFileURL
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(FlutterError(code: "FILE_NOT_FOUND", message: "导出文件不存在", details: nil))
      return
    }
    guard isSimiChatExportArchive(fileURL.lastPathComponent) else {
      result(FlutterError(code: "INVALID_EXPORT_FILE", message: "只能分享 SimiChat 导出压缩包", details: nil))
      return
    }
    let homePath = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
    guard fileURL.path.hasPrefix(homePath + "/") else {
      result(FlutterError(code: "OUTSIDE_APP_DATA", message: "导出文件必须位于应用私有目录", details: nil))
      return
    }

    guard let presenter = topMostViewController() else {
      result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "当前没有可用窗口用于系统分享", details: nil))
      return
    }

    let subject = arguments["subject"] as? String ?? "SimiChat 数据导出包"
    let activityController = UIActivityViewController(
      activityItems: [fileURL],
      applicationActivities: nil
    )
    activityController.setValue(subject, forKey: "subject")
    if let popover = activityController.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(
        x: presenter.view.bounds.midX,
        y: presenter.view.bounds.midY,
        width: 0,
        height: 0
      )
      popover.permittedArrowDirections = []
    }

    DispatchQueue.main.async {
      presenter.present(activityController, animated: true)
      result(true)
    }
  }

  private func isSimiChatExportArchive(_ fileName: String) -> Bool {
    return fileName.hasPrefix("simichat-export-") && fileName.hasSuffix(".tar.gz")
  }

  private func topMostViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }?
      .rootViewController
    var top = root
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func startVoiceRecording(result: @escaping FlutterResult) {
    guard audioRecorder == nil else {
      result(FlutterError(code: "ALREADY_RECORDING", message: "正在录音中", details: nil))
      return
    }

    AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
      DispatchQueue.main.async {
        guard granted else {
          result(FlutterError(code: "PERMISSION_DENIED", message: "麦克风权限被拒绝", details: nil))
          return
        }
        self?.beginVoiceRecording(result: result)
      }
    }
  }

  private func beginVoiceRecording(result: @escaping FlutterResult) {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
      try session.setActive(true)

      let directory = try FileManager.default.url(
        for: .cachesDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
      ).appendingPathComponent("simichat_recordings", isDirectory: true)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

      let fileURL = directory.appendingPathComponent("simichat-recording-\(Int(Date().timeIntervalSince1970 * 1000)).m4a")
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
      ]
      let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
      recorder.prepareToRecord()
      guard recorder.record() else {
        result(FlutterError(code: "START_RECORDING_FAILED", message: "启动录音失败", details: nil))
        return
      }
      audioRecorder = recorder
      recordingURL = fileURL
      recordingStartedAt = Date()
      result(true)
    } catch {
      result(FlutterError(code: "START_RECORDING_FAILED", message: "启动录音失败", details: nil))
    }
  }

  private func stopVoiceRecording(result: @escaping FlutterResult) {
    guard let recorder = audioRecorder, let fileURL = recordingURL else {
      result(FlutterError(code: "NOT_RECORDING", message: "当前没有正在进行的录音", details: nil))
      return
    }
    let durationMs = Int(Date().timeIntervalSince(recordingStartedAt ?? Date()) * 1000)
    recorder.stop()
    audioRecorder = nil
    recordingURL = nil
    recordingStartedAt = nil

    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      result(FlutterError(code: "RECORDING_TOO_SHORT", message: "录音时间太短", details: nil))
      return
    }
    let attributes = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)) ?? [:]
    let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    guard fileSize > 0 else {
      try? FileManager.default.removeItem(at: fileURL)
      result(FlutterError(code: "RECORDING_TOO_SHORT", message: "录音时间太短", details: nil))
      return
    }
    result([
      "path": fileURL.path,
      "fileName": fileURL.lastPathComponent,
      "mimeType": "audio/mp4",
      "fileSize": fileSize,
      "durationMs": max(durationMs, 0)
    ])
  }

  private func cancelVoiceRecording(result: @escaping FlutterResult) {
    let fileURL = recordingURL
    audioRecorder?.stop()
    audioRecorder = nil
    recordingURL = nil
    recordingStartedAt = nil
    if let fileURL {
      try? FileManager.default.removeItem(at: fileURL)
    }
    result(true)
  }

  private func playAudioFile(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String,
          !path.isEmpty else {
      result(FlutterError(code: "INVALID_ARGUMENT", message: "缺少语音文件路径", details: nil))
      return
    }

    let fileURL = URL(fileURLWithPath: path)
      .resolvingSymlinksInPath()
      .standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
          !isDirectory.boolValue else {
      result(FlutterError(code: "FILE_NOT_FOUND", message: "语音文件不存在", details: nil))
      return
    }
    let homePath = URL(fileURLWithPath: NSHomeDirectory())
      .resolvingSymlinksInPath()
      .standardizedFileURL
      .path
    guard fileURL.path == homePath || fileURL.path.hasPrefix(homePath + "/") else {
      result(FlutterError(code: "OUTSIDE_APP_DATA", message: "只能播放应用私有目录内的语音文件", details: nil))
      return
    }

    do {
      stopAudioPlayback()
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
      let player = try AVAudioPlayer(contentsOf: fileURL)
      guard player.prepareToPlay(), player.play() else {
        result(FlutterError(code: "PLAY_FAILED", message: "语音播放失败，请稍后重试", details: nil))
        return
      }
      player.delegate = self
      audioPlayer = player
      audioPlayerURL = fileURL
      result(true)
    } catch {
      audioPlayer = nil
      audioPlayerURL = nil
      result(FlutterError(code: "PLAY_FAILED", message: "语音播放失败，请稍后重试", details: nil))
    }
  }

  private func stopAudioPlayback() {
    let stoppedPath = audioPlayerURL?.path
    audioPlayer?.stop()
    audioPlayer = nil
    audioPlayerURL = nil
    emitAudioPlaybackEvent(method: "playbackStopped", path: stoppedPath)
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    guard audioPlayer === player else { return }
    let finishedPath = audioPlayerURL?.path
    audioPlayer = nil
    audioPlayerURL = nil
    emitAudioPlaybackEvent(
      method: flag ? "playbackCompleted" : "playbackError",
      path: finishedPath
    )
  }

  func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
    guard audioPlayer === player else { return }
    let failedPath = audioPlayerURL?.path
    audioPlayer = nil
    audioPlayerURL = nil
    emitAudioPlaybackEvent(method: "playbackError", path: failedPath)
  }

  private func emitAudioPlaybackEvent(method: String, path: String?) {
    var arguments: [String: Any] = [:]
    if let path {
      arguments["path"] = path
    }
    audioPlayerChannel?.invokeMethod(method, arguments: arguments)
  }
}
