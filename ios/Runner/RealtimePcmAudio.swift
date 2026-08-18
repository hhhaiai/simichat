import AVFoundation
import Darwin
import Flutter
import UIKit

/// Native realtime PCM bridge for the Flutter realtime voice session.
///
/// This class intentionally uses AVAudioEngine rather than AVAudioRecorder. The
/// input tap converts live microphone buffers to 16 kHz mono PCM16 and sends
/// them straight over the EventChannel. Playback schedules incoming 24 kHz
/// mono PCM16 buffers on an AVAudioPlayerNode; no audio is written to a file.
final class RealtimePcmAudio: NSObject, FlutterStreamHandler {
  static let methodChannelName = "simichat/realtime_pcm_audio"
  static let eventChannelName = "simichat/realtime_pcm_audio/events"

  private static let inputSampleRate = 16_000
  private static let outputSampleRate = 24_000
  private static let channels = 1
  private static let bitsPerSample = 16

  private struct NativeError: Error {
    let code: String
    let message: String
  }

  private var eventSink: FlutterEventSink?
  private var audioEngine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var outputFormat: AVAudioFormat?
  private var inputConverter: AVAudioConverter?
  private var inputSourceFormat: AVAudioFormat?
  private var inputTargetFormat: AVAudioFormat?
  private var captureActive = false
  private var playbackActive = false
  private var audioSessionActive = false
  private var captureGeneration: UInt64 = 0
  private var pendingCaptureStartResult: FlutterResult?
  private var lastExternalStopCode: String?
  private var notificationObservers: [NSObjectProtocol] = []

  override init() {
    super.init()
    registerNotificationObservers()
  }

  deinit {
    notificationObservers.forEach(NotificationCenter.default.removeObserver)
    stopCaptureInternal()
    stopPlaybackInternal()
  }

  // MARK: - Flutter channels

  func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in
        self?.handle(call: call, result: result)
      }
      return
    }

    switch call.method {
    case "startCapture":
      startCapture(arguments: call.arguments as? [String: Any], result: result)
    case "stopCapture":
      stopCapture(result: result)
    case "startPlayback":
      startPlayback(arguments: call.arguments as? [String: Any], result: result)
    case "writePlayback":
      writePlayback(arguments: call.arguments as? [String: Any], result: result)
    case "stopPlayback":
      stopPlayback(result: result)
    case "getDiagnostics":
      result(diagnostics())
#if DEBUG
    case "debugSimulateInterruption":
      postDebugInterruption(result: result)
    case "debugSimulateRouteUnavailable":
      postDebugRouteUnavailable(result: result)
#endif
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    if let pending = pendingCaptureStartResult {
      pendingCaptureStartResult = nil
      pending(FlutterError(
        code: "INVALID_STATE",
        message: "实时 PCM 麦克风事件订阅已取消",
        details: nil
      ))
    }
    // The EventChannel is the only owner of the capture stream. If Flutter
    // drops that stream without first calling stopCapture, remove the tap and
    // release the audio session instead of continuing to read microphone
    // buffers that nobody can consume.
    stopCaptureInternal()
    return nil
  }

  // MARK: - Capture

  private func startCapture(
    arguments: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    guard acceptsCaptureArguments(arguments) else {
      result(FlutterError(
        code: "INVALID_ARGUMENT",
        message: "实时 PCM 输入仅支持 16kHz mono PCM16",
        details: nil
      ))
      return
    }
    if captureActive {
      result(FlutterError(
        code: "ALREADY_CAPTURING",
        message: "实时麦克风已经在运行",
        details: nil
      ))
      return
    }
    if pendingCaptureStartResult != nil {
      result(FlutterError(
        code: "PERMISSION_REQUEST_ACTIVE",
        message: "麦克风权限请求正在进行中",
        details: nil
      ))
      return
    }

    let session = AVAudioSession.sharedInstance()
    switch session.recordPermission {
    case .granted:
      beginCapture(result: result)
    case .denied:
      result(FlutterError(
        code: "PERMISSION_DENIED",
        message: "麦克风权限被拒绝",
        details: nil
      ))
    case .undetermined:
      pendingCaptureStartResult = result
      session.requestRecordPermission { [weak self] granted in
        DispatchQueue.main.async {
          guard let self, let pending = self.pendingCaptureStartResult else {
            return
          }
          self.pendingCaptureStartResult = nil
          if granted {
            self.beginCapture(result: pending)
          } else {
            pending(FlutterError(
              code: "PERMISSION_DENIED",
              message: "麦克风权限被拒绝",
              details: nil
            ))
          }
        }
      }
    @unknown default:
      result(FlutterError(
        code: "PERMISSION_DENIED",
        message: "麦克风授权状态异常",
        details: nil
      ))
    }
  }

  private func beginCapture(result: @escaping FlutterResult) {
    var tapInstalled = false
    do {
      let session = AVAudioSession.sharedInstance()
      guard session.isInputAvailable else {
        throw NativeError(
          code: "CAPTURE_UNAVAILABLE",
          message: "当前设备没有可用的麦克风输入"
        )
      }
      try activateAudioSession()

      let engine = audioEngineOrCreate()
      let inputNode = engine.inputNode
      let sourceFormat = inputNode.outputFormat(forBus: 0)
      guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
        throw NativeError(
          code: "CAPTURE_UNAVAILABLE",
          message: "当前设备无法提供实时 PCM 麦克风格式"
        )
      }
      guard let targetFormat = pcmFormat(sampleRate: Double(Self.inputSampleRate)) else {
        throw NativeError(
          code: "CAPTURE_UNAVAILABLE",
          message: "无法创建 16kHz mono PCM16 格式"
        )
      }
      guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
        throw NativeError(
          code: "CAPTURE_UNAVAILABLE",
          message: "当前设备不支持实时 PCM 输入格式转换"
        )
      }
      // A live tap has no trailing frames to prime from. Downmix before the
      // channel-count reduction to the required mono wire format.
      converter.primeMethod = .none
      converter.downmix = true

      captureGeneration &+= 1
      let generation = captureGeneration
      inputConverter = converter
      inputSourceFormat = sourceFormat
      inputTargetFormat = targetFormat
      inputNode.installTap(onBus: 0, bufferSize: 1_024, format: sourceFormat) {
        [weak self, converter, targetFormat, generation] buffer, _ in
        self?.forwardCaptureBuffer(
          buffer,
          converter: converter,
          targetFormat: targetFormat,
          generation: generation
        )
      }
      tapInstalled = true
      captureActive = true
      lastExternalStopCode = nil

      do {
        try startAudioEngine(engine)
      } catch {
        throw NativeError(
          code: "CAPTURE_START_FAILED",
          message: "启动实时 PCM 麦克风失败"
        )
      }
      result(true)
    } catch let error as NativeError {
      if tapInstalled {
        audioEngine?.inputNode.removeTap(onBus: 0)
      }
      captureActive = false
      inputConverter = nil
      inputSourceFormat = nil
      inputTargetFormat = nil
      captureGeneration &+= 1
      if !playbackActive {
        shutdownEngineAndSession()
      }
      result(FlutterError(code: error.code, message: error.message, details: nil))
    } catch {
      if tapInstalled {
        audioEngine?.inputNode.removeTap(onBus: 0)
      }
      captureActive = false
      inputConverter = nil
      inputSourceFormat = nil
      inputTargetFormat = nil
      captureGeneration &+= 1
      if !playbackActive {
        shutdownEngineAndSession()
      }
      result(FlutterError(
        code: "CAPTURE_START_FAILED",
        message: "启动实时 PCM 麦克风失败",
        details: nil
      ))
    }
  }

  private func stopCapture(result: @escaping FlutterResult) {
    if let pending = pendingCaptureStartResult {
      pendingCaptureStartResult = nil
      pending(FlutterError(
        code: "INVALID_STATE",
        message: "实时 PCM 麦克风启动已取消",
        details: nil
      ))
    }
    stopCaptureInternal()
    result(true)
  }

  private func stopCaptureInternal() {
    captureGeneration &+= 1
    if captureActive {
      audioEngine?.inputNode.removeTap(onBus: 0)
    }
    captureActive = false
    inputConverter = nil
    inputSourceFormat = nil
    inputTargetFormat = nil
    shutdownIfIdle()
  }

  private func forwardCaptureBuffer(
    _ buffer: AVAudioPCMBuffer,
    converter: AVAudioConverter,
    targetFormat: AVAudioFormat,
    generation: UInt64
  ) {
    guard buffer.frameLength > 0 else { return }

    let sourceSampleRate = max(buffer.format.sampleRate, 1.0)
    let convertedCapacity = AVAudioFrameCount(
      max(
        1,
        Int(ceil(Double(buffer.frameLength) * targetFormat.sampleRate / sourceSampleRate)) + 32
      )
    )
    guard let converted = AVAudioPCMBuffer(
      pcmFormat: targetFormat,
      frameCapacity: convertedCapacity
    ) else {
      reportCaptureFailure(
        generation: generation,
        code: "CAPTURE_READ_FAILED",
        message: "实时 PCM 麦克风缓冲区创建失败"
      )
      return
    }

    var conversionError: NSError?
    var suppliedInput = false
    let conversionStatus = converter.convert(
      to: converted,
      error: &conversionError
    ) { _, status in
      guard !suppliedInput else {
        status.pointee = .noDataNow
        return nil
      }
      suppliedInput = true
      status.pointee = .haveData
      return buffer
    }
    if conversionStatus == .error || conversionError != nil {
      reportCaptureFailure(
        generation: generation,
        code: "CAPTURE_READ_FAILED",
        message: "实时 PCM 麦克风读取失败"
      )
      return
    }
    guard converted.frameLength > 0 else { return }

    guard let channelData = converted.int16ChannelData?[0] else {
      reportCaptureFailure(
        generation: generation,
        code: "CAPTURE_READ_FAILED",
        message: "实时 PCM 麦克风数据格式异常"
      )
      return
    }
    let bytesPerFrame = Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
    guard bytesPerFrame == Self.bitsPerSample / 8 else {
      reportCaptureFailure(
        generation: generation,
        code: "CAPTURE_READ_FAILED",
        message: "实时 PCM 麦克风输出不是 mono PCM16"
      )
      return
    }
    let byteCount = Int(converted.frameLength) * bytesPerFrame
    guard byteCount > 0 else { return }
    let data = Data(bytes: channelData, count: byteCount)

    DispatchQueue.main.async { [weak self] in
      guard let self,
            self.captureActive,
            self.captureGeneration == generation,
            let sink = self.eventSink else {
        return
      }
      sink(FlutterStandardTypedData(bytes: data))
    }
  }

  private func reportCaptureFailure(
    generation: UInt64,
    code: String,
    message: String
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self,
            self.captureActive,
            self.captureGeneration == generation else {
        return
      }
      self.emitEventError(code: code, message: message)
      self.stopCaptureInternal()
    }
  }

  // MARK: - Playback

  private func startPlayback(
    arguments: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    guard acceptsPlaybackArguments(arguments) else {
      result(FlutterError(
        code: "INVALID_ARGUMENT",
        message: "实时 PCM 输出仅支持 24kHz mono PCM16",
        details: nil
      ))
      return
    }
    if playbackActive {
      result(FlutterError(
        code: "ALREADY_PLAYING",
        message: "实时音频播放已经在运行",
        details: nil
      ))
      return
    }

    do {
      try activateAudioSession()
      let engine = audioEngineOrCreate()
      guard let format = pcmFormat(sampleRate: Double(Self.outputSampleRate)) else {
        throw NativeError(
          code: "PLAYBACK_UNAVAILABLE",
          message: "无法创建 24kHz mono PCM16 格式"
        )
      }

      let node: AVAudioPlayerNode
      if let existing = playerNode {
        node = existing
      } else {
        // AVAudioEngine graph changes are made while stopped. The input tap,
        // when present, remains installed across this short restart.
        let wasRunning = engine.isRunning
        if wasRunning {
          engine.stop()
        }
        let newNode = AVAudioPlayerNode()
        engine.attach(newNode)
        engine.connect(newNode, to: engine.mainMixerNode, format: format)
        playerNode = newNode
        outputFormat = format
        node = newNode
        if wasRunning {
          try startAudioEngine(engine)
        }
      }

      if !engine.isRunning {
        try startAudioEngine(engine)
      }
      node.play()
      playbackActive = true
      lastExternalStopCode = nil
      result(true)
    } catch let error as NativeError {
      if !captureActive {
        shutdownEngineAndSession()
      } else {
        restoreCaptureEngineIfNeeded()
      }
      result(FlutterError(code: error.code, message: error.message, details: nil))
    } catch {
      if !captureActive {
        shutdownEngineAndSession()
      } else {
        restoreCaptureEngineIfNeeded()
      }
      result(FlutterError(
        code: "PLAYBACK_START_FAILED",
        message: "启动实时 PCM 播放失败",
        details: nil
      ))
    }
  }

  private func writePlayback(
    arguments: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    guard playbackActive,
          let node = playerNode,
          let format = outputFormat else {
      result(FlutterError(
        code: "INVALID_STATE",
        message: "实时 PCM 播放尚未启动",
        details: nil
      ))
      return
    }
    guard let data = dataArgument(arguments), !data.isEmpty, data.count % 2 == 0 else {
      result(FlutterError(
        code: "INVALID_ARGUMENT",
        message: "实时 PCM 播放数据无效",
        details: nil
      ))
      return
    }

    let frameCount = data.count / (Self.bitsPerSample / 8)
    guard frameCount <= Int(UInt32.max),
          let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
          ),
          let channelData = buffer.int16ChannelData?[0] else {
      result(FlutterError(
        code: "PLAYBACK_WRITE_FAILED",
        message: "实时 PCM 播放缓冲区创建失败",
        details: nil
      ))
      return
    }

    data.withUnsafeBytes { rawBuffer in
      guard let source = rawBuffer.baseAddress else { return }
      memcpy(channelData, source, data.count)
    }
    buffer.frameLength = AVAudioFrameCount(frameCount)

    guard audioEngine?.isRunning == true else {
      result(FlutterError(
        code: "INVALID_STATE",
        message: "实时 PCM 播放引擎未运行",
        details: nil
      ))
      return
    }
    node.scheduleBuffer(buffer, completionHandler: nil)
    result(true)
  }

  private func stopPlayback(result: @escaping FlutterResult) {
    stopPlaybackInternal()
    result(true)
  }

  private func stopPlaybackInternal() {
    playbackActive = false
    playerNode?.stop()
    playerNode?.reset()
    shutdownIfIdle()
  }

  // MARK: - Audio session and engine

  private func activateAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .default,
      options: [.defaultToSpeaker, .allowBluetoothHFP]
    )
    // Hardware routes commonly expose 48 kHz and/or two input channels. The
    // converter below deliberately normalizes those routes to the protocol's
    // 16 kHz mono PCM16 contract. Request mono when the route allows it, but
    // do not reject a route that cannot honor the preference.
    try? session.setPreferredInputNumberOfChannels(Self.channels)
    try session.setActive(true, options: [])
    audioSessionActive = true
  }

  private func audioEngineOrCreate() -> AVAudioEngine {
    if let audioEngine { return audioEngine }
    let engine = AVAudioEngine()
    audioEngine = engine
    return engine
  }

  private func startAudioEngine(_ engine: AVAudioEngine) throws {
    guard !engine.isRunning else { return }
    engine.prepare()
    try engine.start()
  }

  private func shutdownIfIdle() {
    guard !captureActive, !playbackActive else { return }
    shutdownEngineAndSession()
  }

  private func shutdownEngineAndSession() {
    audioEngine?.stop()
    playerNode?.stop()
    playerNode?.reset()
    audioEngine = nil
    playerNode = nil
    outputFormat = nil
    inputConverter = nil
    inputSourceFormat = nil
    inputTargetFormat = nil
    if audioSessionActive {
      try? AVAudioSession.sharedInstance().setActive(
        false,
        options: [.notifyOthersOnDeactivation]
      )
    }
    audioSessionActive = false
  }

  private func pcmFormat(sampleRate: Double) -> AVAudioFormat? {
    AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: sampleRate,
      channels: AVAudioChannelCount(Self.channels),
      // A non-interleaved mono buffer has the same PCM16 byte representation,
      // while guaranteeing int16ChannelData is available for both converter
      // output and player input.
      interleaved: false
    )
  }

  private func restoreCaptureEngineIfNeeded() {
    guard captureActive,
          let engine = audioEngine,
          !engine.isRunning else {
      return
    }
    do {
      try startAudioEngine(engine)
    } catch {
      stopCaptureInternal()
    }
  }

  private func diagnostics() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    return [
      "platform": "ios",
      "captureActive": captureActive,
      "playbackActive": playbackActive,
      "audioEngineRunning": audioEngine?.isRunning == true,
      "audioSessionActive": audioSessionActive,
      "sessionCategory": session.category.rawValue,
      "sessionMode": session.mode.rawValue,
      "inputSourceSampleRate": inputSourceFormat?.sampleRate ?? 0,
      "inputSourceChannels": inputSourceFormat.map { Int($0.channelCount) } ?? 0,
      "inputTargetSampleRate": inputTargetFormat?.sampleRate ?? 0,
      "inputTargetChannels": inputTargetFormat.map { Int($0.channelCount) } ?? 0,
      "inputTargetBitsPerSample": bitsPerChannel(inputTargetFormat),
      "outputSampleRate": outputFormat?.sampleRate ?? 0,
      "outputChannels": outputFormat.map { Int($0.channelCount) } ?? 0,
      "outputBitsPerSample": bitsPerChannel(outputFormat),
      "protocolInputSampleRate": Self.inputSampleRate,
      "protocolOutputSampleRate": Self.outputSampleRate,
      "channels": Self.channels,
      "bitsPerSample": Self.bitsPerSample,
      "inputRoute": session.currentRoute.inputs.map { $0.portType.rawValue },
      "outputRoute": session.currentRoute.outputs.map { $0.portType.rawValue },
      "notificationObserverCount": notificationObservers.count,
      "lastExternalStopCode": lastExternalStopCode as Any,
      "writesAudioFiles": false,
    ]
  }

  private func bitsPerChannel(_ format: AVAudioFormat?) -> Int {
    guard let format else { return 0 }
    return Int(format.streamDescription.pointee.mBitsPerChannel)
  }

  // MARK: - Lifecycle and interruptions

  private func registerNotificationObservers() {
    let center = NotificationCenter.default
    notificationObservers.append(
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.stopForExternalEvent(
          code: "APP_LIFECYCLE_STOPPED",
          message: "应用进入后台，实时 PCM 音频已停止"
        )
      }
    )
    notificationObservers.append(
      center.addObserver(
        forName: UIApplication.willTerminateNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        self?.stopForExternalEvent(
          code: "APP_LIFECYCLE_STOPPED",
          message: "应用即将退出，实时 PCM 音频已停止"
        )
      }
    )
    notificationObservers.append(
      center.addObserver(
        forName: AVAudioSession.interruptionNotification,
        object: AVAudioSession.sharedInstance(),
        queue: .main
      ) { [weak self] notification in
        self?.handleAudioSessionInterruption(notification)
      }
    )
    notificationObservers.append(
      center.addObserver(
        forName: AVAudioSession.routeChangeNotification,
        object: AVAudioSession.sharedInstance(),
        queue: .main
      ) { [weak self] notification in
        self?.handleAudioRouteChange(notification)
      }
    )
    notificationObservers.append(
      center.addObserver(
        forName: AVAudioSession.mediaServicesWereResetNotification,
        object: AVAudioSession.sharedInstance(),
        queue: .main
      ) { [weak self] _ in
        self?.stopForExternalEvent(
          code: "AUDIO_SESSION_RESET",
          message: "系统音频服务已重置，实时 PCM 音频已停止"
        )
      }
    )
  }

  private func handleAudioSessionInterruption(_ notification: Notification) {
    guard let rawType = unsignedUserInfoValue(
      notification.userInfo?[AVAudioSessionInterruptionTypeKey]
    ),
          let type = AVAudioSession.InterruptionType(rawValue: rawType),
          type == .began else {
      return
    }
    stopForExternalEvent(
      code: "AUDIO_SESSION_INTERRUPTED",
      message: "实时 PCM 音频被系统音频会话中断"
    )
  }

  private func handleAudioRouteChange(_ notification: Notification) {
    guard let rawReason = unsignedUserInfoValue(
      notification.userInfo?[AVAudioSessionRouteChangeReasonKey]
    ),
          let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else {
      return
    }
    switch reason {
    case .unknown,
         .newDeviceAvailable,
         .oldDeviceUnavailable,
         .override,
         .wakeFromSleep,
         .noSuitableRouteForCategory,
         .routeConfigurationChange:
      stopForExternalEvent(
        code: "AUDIO_ROUTE_CHANGED",
        message: "实时 PCM 音频路由已变化，音频已停止"
      )
    // setCategory(.playAndRecord) during our own activation can emit
    // categoryChange. It is not a physical route transition; treating it as
    // one would stop a session immediately after startPlayback/startCapture.
    case .categoryChange:
      break
    default:
      break
    }
  }

  private func stopForExternalEvent(code: String, message: String) {
    guard captureActive || playbackActive || pendingCaptureStartResult != nil else {
      return
    }
    lastExternalStopCode = code
    if let pending = pendingCaptureStartResult {
      pendingCaptureStartResult = nil
      pending(FlutterError(code: code, message: message, details: nil))
    }
    emitEventError(code: code, message: message)
    stopCaptureInternal()
    stopPlaybackInternal()
  }

  private func unsignedUserInfoValue(_ value: Any?) -> UInt? {
    if let value = value as? UInt {
      return value
    }
    if let value = value as? NSNumber {
      return value.uintValue
    }
    return nil
  }

  private func emitEventError(code: String, message: String) {
    eventSink?(FlutterError(code: code, message: message, details: nil))
  }

#if DEBUG
  /// Posts the same notification that AVAudioSession sends when a phone call,
  /// alarm, or another system audio owner interrupts this session. This hook
  /// is compiled into Debug only and is used by the iOS integration smoke; it
  /// is not part of the release API surface.
  private func postDebugInterruption(result: @escaping FlutterResult) {
    NotificationCenter.default.post(
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      userInfo: [
        AVAudioSessionInterruptionTypeKey:
          AVAudioSession.InterruptionType.began.rawValue,
      ]
    )
    result(true)
  }

  /// Posts an old-device-unavailable route change for deterministic Debug
  /// coverage. Physical headset/Bluetooth route changes still exercise the
  /// same observer in release builds.
  private func postDebugRouteUnavailable(result: @escaping FlutterResult) {
    NotificationCenter.default.post(
      name: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(),
      userInfo: [
        AVAudioSessionRouteChangeReasonKey:
          AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue,
      ]
    )
    result(true)
  }
#endif

  // MARK: - Argument helpers

  private func acceptsCaptureArguments(_ arguments: [String: Any]?) -> Bool {
    intArgument(arguments, key: "sampleRate", fallback: Self.inputSampleRate) == Self.inputSampleRate &&
      intArgument(arguments, key: "channels", fallback: Self.channels) == Self.channels &&
      intArgument(arguments, key: "bitsPerSample", fallback: Self.bitsPerSample) == Self.bitsPerSample
  }

  private func acceptsPlaybackArguments(_ arguments: [String: Any]?) -> Bool {
    intArgument(arguments, key: "sampleRate", fallback: Self.outputSampleRate) == Self.outputSampleRate &&
      intArgument(arguments, key: "channels", fallback: Self.channels) == Self.channels &&
      intArgument(arguments, key: "bitsPerSample", fallback: Self.bitsPerSample) == Self.bitsPerSample
  }

  private func intArgument(
    _ arguments: [String: Any]?,
    key: String,
    fallback: Int
  ) -> Int {
    if let value = arguments?[key] as? Int {
      return value
    }
    if let value = arguments?[key] as? NSNumber {
      return value.intValue
    }
    return fallback
  }

  private func dataArgument(_ arguments: [String: Any]?) -> Data? {
    guard let value = arguments?["bytes"] else { return nil }
    if let typed = value as? FlutterStandardTypedData {
      return typed.data
    }
    if let data = value as? Data {
      return data
    }
    if let bytes = value as? [UInt8] {
      return Data(bytes)
    }
    if let bytes = value as? [NSNumber] {
      return Data(bytes.map { $0.uint8Value })
    }
    return nil
  }
}
