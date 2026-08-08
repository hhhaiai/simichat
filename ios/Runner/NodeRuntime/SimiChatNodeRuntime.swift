import Foundation

/// Owns the NodeMobile.framework instance shipped inside the iOS app.
/// Node runs on a private queue for the lifetime of the app process; Flutter
/// only observes its local HTTP health/SSE endpoint.
final class SimiChatNodeRuntime {
  static let channel = "top.simitalk.aichat/node_runtime"
  private let bundle: Bundle
  private let queue = DispatchQueue(label: "top.simitalk.aichat.node-runtime", qos: .utility)
  private let lock = NSLock()
  private var started = false
  private var running = false
  private var state = 0 // stopped, starting, running, crashed
  private var exitCode = 0
  private var restartCount = 0
  private var lastError = ""
  private var scriptPath = ""
  private let port = 37651

  init(bundle: Bundle = .main) {
    self.bundle = bundle
  }

  func start() -> [String: Any] {
    do {
      try prepareRuntimeFiles()
    } catch {
      lock.lock()
      state = 3
      lastError = error.localizedDescription
      lock.unlock()
      return info(running: false)
    }

    lock.lock()
    if started {
      let result = infoLocked(running: running || state == 1)
      lock.unlock()
      return result
    }
    started = true
    state = 1
    exitCode = 0
    lastError = ""
    let script = scriptPath
    lock.unlock()

    queue.async { [weak self] in
      guard let self else { return }
      let support = self.applicationSupportDirectory()
      let extensionRoot = support.deletingLastPathComponent().path
      setenv("HOME", support.path, 1)
      setenv("TMPDIR", FileManager.default.temporaryDirectory.path, 1)
      setenv("NODE_PATH", support.path, 1)
      setenv("MCP_RUNTIME_HOST", "127.0.0.1", 1)
      setenv("MCP_RUNTIME_PORT", String(self.port), 1)
      setenv("MCP_RUNTIME_WORKSPACE_ROOT", support.path, 1)
      setenv("MCP_RUNTIME_EXTENSION_ROOT", extensionRoot, 1)
      setenv("SIMICHAT_NODE_RUNTIME_KIND", "ios-embedded", 1)
      setenv("SIMICHAT_NODE_APP_MANAGED", "true", 1)

      let arguments = ["node", script]
      var cArguments = arguments.map { strdup($0) }
      self.lock.lock()
      self.running = true
      self.state = 2
      self.lock.unlock()
      let code = cArguments.withUnsafeMutableBufferPointer { buffer in
        simichat_node_start(Int32(arguments.count), buffer.baseAddress)
      }
      cArguments.forEach { free($0) }
      self.lock.lock()
      self.running = false
      self.started = false
      self.exitCode = Int(code)
      self.state = code == 0 ? 0 : 3
      if code != 0 { self.lastError = "embedded Node exited with code \(code)" }
      self.lock.unlock()
    }
    return info(running: true)
  }

  func status() -> [String: Any] {
    lock.lock()
    let result = infoLocked(running: running || state == 1)
    lock.unlock()
    return result
  }

  func stop() -> [String: Any] {
    var result = status()
    result["stopSupported"] = false
    return result
  }

  private func info(running: Bool) -> [String: Any] {
    lock.lock()
    let result = infoLocked(running: running)
    lock.unlock()
    return result
  }

  private func infoLocked(running: Bool) -> [String: Any] {
    [
      "running": running,
      "state": stateName(state),
      "nativeState": state,
      "nativeExitCode": exitCode,
      "restartCount": restartCount,
      "lastError": lastError,
      "runtime": "simichat-node-ios-embedded",
      "dependencyMode": "node-mobile-framework",
      "externalProcess": false,
      "appManaged": true,
      "requiresHostNode": false,
      "requiresHostNpx": false,
      "requiresDocker": false,
      "nodeVersion": "18.20.4-mobile",
      "healthUrl": "http://127.0.0.1:\(port)/health",
      "sseUrl": "http://127.0.0.1:\(port)/mcp/sse/simichat-node",
      "scriptPath": scriptPath,
      "stopSupported": false,
    ]
  }

  private func stateName(_ value: Int) -> String {
    switch value {
    case 1: return "starting"
    case 2: return "running"
    case 3: return "crashed"
    default: return "stopped"
    }
  }

  private func applicationSupportDirectory() -> URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("simichat_bundled_node", isDirectory: true)
  }

  private func prepareRuntimeFiles() throws {
    let runtimeRoot = applicationSupportDirectory()
    try FileManager.default.createDirectory(at: runtimeRoot, withIntermediateDirectories: true)
    let target = runtimeRoot.appendingPathComponent("runtime-server.mjs")
    let candidates = [
      bundle.bundleURL.appendingPathComponent("Frameworks/App.framework/flutter_assets/tools/mcp_runtime/container/runtime-server.mjs"),
      bundle.bundleURL.appendingPathComponent("flutter_assets/tools/mcp_runtime/container/runtime-server.mjs"),
      bundle.url(forResource: "runtime-server", withExtension: "mjs"),
    ].compactMap { $0 }
    guard let source = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
      throw NSError(domain: "SimiChatNodeRuntime", code: 1, userInfo: [NSLocalizedDescriptionKey: "Flutter runtime-server.mjs asset not found"])
    }
    if FileManager.default.fileExists(atPath: target.path) {
      try FileManager.default.removeItem(at: target)
    }
    try FileManager.default.copyItem(at: source, to: target)
    scriptPath = target.path
  }
}
